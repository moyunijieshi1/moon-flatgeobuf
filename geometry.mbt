///|
pub fn Geometry::bounds(self : Geometry) -> Bounds? {
  let mut result : Bounds? = None
  for coordinate in self.xy {
    let b : Bounds = {
      min_x: coordinate.x,
      min_y: coordinate.y,
      max_x: coordinate.x,
      max_y: coordinate.y,
    }
    result = Some(
      match result {
        None => b
        Some(old) => old.union(b)
      },
    )
  }
  for part in self.parts {
    match part.bounds() {
      None => ()
      Some(b) =>
        result = Some(
          match result {
            None => b
            Some(old) => old.union(b)
          },
        )
    }
  }
  result
}

///|
pub fn Geometry::coordinate_count(self : Geometry) -> Int {
  let mut count = self.xy.length()
  for part in self.parts {
    count += part.coordinate_count()
  }
  count
}

///|
fn part_ends(geometry : Geometry) -> Array[Int] {
  if geometry.ends.is_empty() && !geometry.xy.is_empty() {
    [geometry.xy.length()]
  } else {
    geometry.ends
  }
}

///|
fn validate_geometry_inner(
  g : Geometry,
  limits : Limits,
  depth : Int,
) -> Int raise FgbError {
  enforce(depth, limits.max_depth, "geometry depth")
  enforce(g.xy.length(), limits.max_coordinates, "coordinate count")
  for coordinate in g.xy {
    if !finite(coordinate.x) || !finite(coordinate.y) {
      raise InvalidArgument("geometry coordinates must be finite")
    }
  }
  let mut previous = 0
  for end in g.ends {
    if end <= previous || end > g.xy.length() {
      raise InvalidArgument("geometry ends must strictly increase within xy")
    }
    previous = end
  }
  if !g.ends.is_empty() && previous != g.xy.length() {
    raise InvalidArgument("last part end must equal coordinate count")
  }
  match g.kind {
    Unknown => raise InvalidArgument("concrete geometry needs a known type")
    Point =>
      if g.xy.length() != 1 || !g.parts.is_empty() || !g.ends.is_empty() {
        raise InvalidArgument("Point requires exactly one xy pair")
      }
    MultiPoint =>
      if g.xy.is_empty() || !g.parts.is_empty() || !g.ends.is_empty() {
        raise InvalidArgument("MultiPoint needs xy pairs without ends or parts")
      }
    LineString =>
      if g.xy.length() < 2 || !g.parts.is_empty() || !g.ends.is_empty() {
        raise InvalidArgument("LineString requires at least two xy pairs")
      }
    MultiLineString => {
      if !g.parts.is_empty() || g.xy.is_empty() {
        raise InvalidArgument("MultiLineString requires flat xy and ends")
      }
      let mut start = 0
      for end in part_ends(g) {
        if end - start < 2 {
          raise InvalidArgument(
            "each line must contain at least two coordinates",
          )
        }
        start = end
      }
    }
    Polygon => {
      if !g.parts.is_empty() || g.xy.is_empty() {
        raise InvalidArgument("Polygon requires flat rings")
      }
      let mut start = 0
      for end in part_ends(g) {
        if end - start < 4 || g.xy[start] != g.xy[end - 1] {
          raise InvalidArgument(
            "polygon rings must be closed and contain four coordinates",
          )
        }
        start = end
      }
    }
    MultiPolygon => {
      if !g.xy.is_empty() || !g.ends.is_empty() || g.parts.is_empty() {
        raise InvalidArgument("MultiPolygon requires Polygon parts")
      }
      for part in g.parts {
        if part.kind != Polygon {
          raise InvalidArgument("MultiPolygon children must be Polygon")
        }
      }
    }
  }
  let mut count = g.xy.length()
  for child in g.parts {
    count = checked_add(
      count,
      validate_geometry_inner(child, limits, depth + 1),
    )
    enforce(count, limits.max_coordinates, "total coordinates")
  }
  count
}

///|
pub fn Geometry::validate(
  self : Geometry,
  limits? : Limits = Limits::default(),
) -> Unit raise FgbError {
  limits.validate()
  validate_geometry_inner(self, limits, 1) |> ignore
}

///|
fn read_geometry(
  data : Bytes,
  at : Int,
  kind : GeometryKind,
  limits : Limits,
  depth : Int,
  budget : Ref[Int],
) -> Geometry raise FgbError {
  enforce(depth, limits.max_depth, "geometry depth")
  let table = TableView::open(data, at)
  for field in 2..<6 {
    if table.reference(field) != 0 {
      raise Unsupported("Z/M/T/TM geometry vector")
    }
  }
  let declared = kind_from_code(table.byte(6))
  let resolved = if kind == Unknown { declared } else { kind }
  if declared != Unknown && declared != resolved {
    raise InvalidData(at, "geometry type conflicts with header")
  }
  let (xy_at, xy_count) = table.vector(
    1,
    8,
    checked_mul(limits.max_coordinates, 2),
  )
  if xy_count % 2 != 0 {
    raise InvalidData(xy_at, "odd xy vector length")
  }
  budget.val = checked_add(budget.val, xy_count / 2)
  enforce(budget.val, limits.max_coordinates, "total coordinates")
  let xy : Array[Coordinate] = []
  for i in 0..<(xy_count / 2) {
    xy.push({ x: f64(data, xy_at + i * 16), y: f64(data, xy_at + i * 16 + 8), })
  }
  let (ends_at, ends_count) = table.vector(0, 4, limits.max_coordinates)
  let ends : Array[Int] = []
  for i in 0..<ends_count {
    ends.push(size32(data, ends_at + i * 4))
  }
  let (parts_at, parts_count) = table.vector(7, 4, limits.max_coordinates)
  let parts : Array[Geometry] = []
  if parts_count > 0 && resolved != MultiPolygon {
    raise Unsupported("parts on a geometry other than MultiPolygon")
  }
  for i in 0..<parts_count {
    let child = indirect(data, parts_at + i * 4)
    parts.push(read_geometry(data, child, Polygon, limits, depth + 1, budget))
  }
  let result : Geometry = { kind: resolved, xy, ends, parts, }
  // Validation here checks shape rules without trusting the binary representation.
  validate_geometry_inner(result, limits, depth) |> ignore
  result
}

///|
fn write_geometry(b : FbBuilder, g : Geometry) -> Int {
  let table = b.table(8)
  if !g.ends.is_empty() {
    let at = b.vector(g.ends.length(), 4)
    for end in g.ends {
      b.writer.word(end.reinterpret_as_uint())
    }
    b.reference(table, 0, at)
  }
  if !g.xy.is_empty() {
    let at = b.vector(g.xy.length() * 2, 8)
    for coordinate in g.xy {
      b.writer.double(coordinate.x)
      b.writer.double(coordinate.y)
    }
    b.reference(table, 1, at)
  }
  b.scalar(table, 6, g.kind.code())
  if !g.parts.is_empty() {
    let vector = b.vector(g.parts.length(), 4)
    b.writer.zeros(g.parts.length() * 4)
    for i in 0..<g.parts.length() {
      let child = write_geometry(b, g.parts[i])
      let slot = vector + 4 + 4 * i
      b.writer.patch_word(slot, child - slot)
    }
    b.reference(table, 7, vector)
  }
  table
}

///|
pub fn Feature::bounds(self : Feature) -> Bounds? {
  match self.geometry {
    Some(g) => g.bounds()
    None => None
  }
}
