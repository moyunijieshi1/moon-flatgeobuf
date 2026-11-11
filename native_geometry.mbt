///|
fn native_kind_matches(expected : Int32, actual : Int32) -> Bool {
  expected == 0 ||
  expected == actual ||
  (expected == 13 && (actual == 2 || actual == 8 || actual == 9)) ||
  (
    expected == 14 &&
    (
      actual == 3 ||
      actual == 10 ||
      actual == 15 ||
      actual == 16 ||
      actual == 17
    )
  )
}

///|
fn native_parts_kind(kind : Int32) -> Bool {
  kind == 6 ||
  kind == 7 ||
  kind == 9 ||
  kind == 10 ||
  kind == 11 ||
  kind == 12 ||
  kind == 15
}

///|
fn native_geometry_empty(g : NativeGeometry) -> Bool {
  let xy = g.xy.unwrap_or([])
  let point_nan = g.kind == 1 &&
    xy.length() == 1 &&
    xy[0].x != xy[0].x &&
    xy[0].y != xy[0].y
  (xy.is_empty() || point_nan) &&
  g.parts.unwrap_or([]).all(native_geometry_empty)
}

///|
fn native_curve_ends(g : NativeGeometry) -> (Coordinate, Coordinate)? {
  let xy = g.xy.unwrap_or([])
  if !xy.is_empty() {
    return Some((xy[0], xy[xy.length() - 1]))
  }
  let mut ends = None
  for child in g.parts.unwrap_or([]) {
    if native_curve_ends(child) is Some((first, last)) {
      ends = match ends {
        Some((start, _)) => Some((start, last))
        None => Some((first, last))
      }
    }
  }
  ends
}

///|
fn native_check_geometry(
  g : NativeGeometry,
  header : NativeHeader,
  limits : Limits,
  depth : Int32,
  nodes : Ref[Int32],
  coordinates : Ref[Int32],
) -> Unit raise FgbError {
  enforce(depth, limits.max_depth, "geometry depth")
  nodes.val = checked_add(nodes.val, 1)
  enforce(nodes.val, limits.max_geometry_nodes, "geometry nodes")
  if g.kind < 1 || g.kind > 17 || g.kind == 13 || g.kind == 14 {
    raise InvalidArgument("geometry requires a concrete WKB type")
  }
  if g.declared_type < 0 ||
    g.declared_type > 17 ||
    (g.declared_type != 0 && g.declared_type != g.kind) {
    raise InvalidArgument("declared geometry type conflicts with resolved type")
  }
  let xy = g.xy.unwrap_or([])
  let n = xy.length()
  coordinates.val = checked_add(coordinates.val, n)
  enforce(coordinates.val, limits.max_coordinates, "geometry coordinates")
  let nan_empty = g.kind == 1 &&
    n == 1 &&
    xy[0].x != xy[0].x &&
    xy[0].y != xy[0].y
  if !nan_empty {
    for point in xy {
      if !finite(point.x) || !finite(point.y) {
        raise InvalidArgument("nonfinite coordinate outside empty Point")
      }
    }
  }
  for
    (enabled, values) in [
      (header.has_z, g.z),
      (header.has_m, g.m),
      (header.has_t, g.t),
    ] {
    match values {
      Some(values) =>
        if values.length() != n {
          raise InvalidArgument("dimensional vector length differs from XY")
        }
      // Preserve auxiliary IEEE-754 measurements, including missing-data
      // NaNs. Only XY participates in the packed spatial index.
      None =>
        if enabled && n > 0 && !nan_empty {
          raise InvalidArgument("missing required dimensional vector")
        }
    }
  }
  match g.tm {
    Some(values) =>
      if values.length() != n {
        raise InvalidArgument("TM vector length differs from XY")
      }
    None =>
      if header.has_tm && n > 0 && !nan_empty {
        raise InvalidArgument("missing TM vector")
      }
  }
  let parts = g.parts.unwrap_or([])
  let ends = g.ends.unwrap_or([])
  nodes.val = checked_add(nodes.val, ends.length())
  enforce(
    nodes.val,
    limits.max_geometry_nodes,
    "geometry nodes and end entries",
  )
  let mut previous = 0
  for end in ends {
    if end < previous || end > n {
      raise InvalidArgument("geometry end outside coordinate vector")
    }
    previous = end
  }
  if !ends.is_empty() && previous != n {
    raise InvalidArgument("geometry ends do not cover coordinates")
  }
  if native_parts_kind(g.kind) {
    if n != 0 || !ends.is_empty() {
      raise InvalidArgument("collection geometry must use parts")
    }
  } else if !parts.is_empty() {
    raise InvalidArgument("flat geometry cannot contain parts")
  }
  match g.kind {
    1 =>
      if n > 1 || !ends.is_empty() {
        raise InvalidArgument("Point has more than one coordinate")
      }
    2 =>
      if (n != 0 && n < 2) || !ends.is_empty() {
        raise InvalidArgument("invalid LineString")
      }
    4 =>
      if !ends.is_empty() {
        raise InvalidArgument("MultiPoint cannot have ends")
      }
    8 =>
      if (n != 0 && (n < 3 || n % 2 != 1)) || !ends.is_empty() {
        raise InvalidArgument(
          "CircularString needs an odd number of at least three points",
        )
      }
    3 | 5 | 16 | 17 => {
      let boundaries = if ends.is_empty() {
        if n == 0 {
          []
        } else {
          [n]
        }
      } else {
        ends
      }
      let mut start = 0
      if g.kind == 17 && boundaries.length() > 1 {
        raise InvalidArgument("Triangle has multiple rings")
      }
      for end in boundaries {
        let length = end - start
        if g.kind == 5 {
          if length == 1 {
            raise InvalidArgument("line part has one coordinate")
          }
        } else if length > 0 {
          if length < 4 || xy[start] != xy[end - 1] {
            raise InvalidArgument("ring is not closed")
          }
          if (g.kind == 16 || g.kind == 17) && length != 4 {
            raise InvalidArgument("triangle requires four ring coordinates")
          }
        }
        start = end
      }
    }
    _ => ()
  }
  enforce(parts.length(), limits.max_geometry_nodes, "geometry parts")
  let mut last : Coordinate? = None
  for child in parts {
    let allowed = match g.kind {
      6 => child.kind == 3
      9 => child.kind == 2 || child.kind == 8
      10 | 11 => child.kind == 2 || child.kind == 8 || child.kind == 9
      12 =>
        child.kind == 3 ||
        child.kind == 10 ||
        child.kind == 15 ||
        child.kind == 16 ||
        child.kind == 17
      15 => child.kind == 3 || child.kind == 17
      7 => true
      _ => false
    }
    if !allowed {
      raise InvalidArgument("invalid child type for collection geometry")
    }
    if child.declared_type == 0 && g.kind != 6 {
      raise InvalidArgument("collection member requires concrete type")
    }
    native_check_geometry(child, header, limits, depth + 1, nodes, coordinates)
    if (g.kind == 9 || g.kind == 10) &&
      native_curve_ends(child) is Some((start, end)) {
      if g.kind == 10 && start != end {
        raise InvalidArgument("CurvePolygon ring is not closed")
      }
      if g.kind == 9 && last is Some(previous) && previous != start {
        raise InvalidArgument("CompoundCurve members are not connected")
      }
      last = Some(end)
    }
  }
}

///|
pub fn NativeGeometry::validate(
  self : NativeGeometry,
  header : NativeHeader,
  limits~ : Limits = Limits::default(),
) -> Unit raise FgbError {
  limits.validate()
  if !native_kind_matches(header.geometry_type, self.kind) {
    raise InvalidArgument("geometry conflicts with header")
  }
  if self.declared_type == 0 &&
    (
      header.geometry_type == 0 ||
      header.geometry_type == 13 ||
      header.geometry_type == 14
    ) {
    raise InvalidArgument("heterogeneous feature must declare concrete type")
  }
  native_check_geometry(self, header, limits, 1, Ref(0), Ref(0))
}

///|
fn native_read_geometry(
  data : Bytes,
  at : Int32,
  expected : Int32,
  limits : Limits,
  depth : Int32,
  nodes : Ref[Int32],
  coordinates : Ref[Int32],
) -> NativeGeometry raise FgbError {
  enforce(depth, limits.max_depth, "geometry depth")
  nodes.val = checked_add(nodes.val, 1)
  enforce(nodes.val, limits.max_geometry_nodes, "geometry nodes")
  let table = TableView::open(data, at)
  let declared_type = table.byte(6)
  let kind = if declared_type == 0 { expected } else { declared_type }
  if !native_kind_matches(expected, kind) {
    raise InvalidData(at, "geometry type conflicts with container")
  }
  let xy = if table.reference(1) == 0 {
    None
  } else {
    let (start, count) = table.vector(
      1,
      8,
      checked_mul(limits.max_coordinates, 2),
    )
    if count % 2 != 0 {
      raise InvalidData(start, "odd XY vector length")
    }
    coordinates.val = checked_add(coordinates.val, count / 2)
    enforce(coordinates.val, limits.max_coordinates, "geometry coordinates")
    Some(
      Array::makei(count / 2, i => {
        x: u64(data, start + i * 16).reinterpret_as_double(),
        y: u64(data, start + i * 16 + 8).reinterpret_as_double(),
      }),
    )
  }
  let n = match xy {
    Some(xy) => xy.length()
    None => 0
  }
  let ends = if table.reference(0) == 0 {
    None
  } else {
    let (start, count) = table.vector(0, 4, limits.max_geometry_nodes)
    nodes.val = checked_add(nodes.val, count)
    enforce(
      nodes.val,
      limits.max_geometry_nodes,
      "geometry nodes and end entries",
    )
    Some(Array::makei(count, i => size32(data, start + i * 4)))
  }
  let tm = if table.reference(5) == 0 {
    None
  } else {
    let (start, count) = table.vector(5, 8, n)
    Some(Array::makei(count, i => u64(data, start + i * 8)))
  }
  let parts = if table.reference(7) == 0 {
    None
  } else {
    let (start, count) = table.vector(7, 4, limits.max_geometry_nodes)
    let values : Array[NativeGeometry] = []
    for i in 0..<count {
      values.push(
        native_read_geometry(
          data,
          indirect(data, start + i * 4),
          if kind == 6 {
            3
          } else {
            0
          },
          limits,
          depth + 1,
          nodes,
          coordinates,
        ),
      )
    }
    Some(values)
  }
  {
    kind,
    declared_type,
    xy,
    ends,
    tm,
    parts,
    z: native_read_doubles(table, 2, n),
    m: native_read_doubles(table, 3, n),
    t: native_read_doubles(table, 4, n),
  }
}

///|
fn native_write_geometry(b : FbBuilder, g : NativeGeometry) -> Int32 {
  let table = b.table(8)
  match g.ends {
    None => ()
    Some(values) => {
      let at = b.vector(values.length(), 4)
      for value in values {
        b.writer.word(value.reinterpret_as_uint())
      }
      b.reference(table, 0, at)
    }
  }
  match g.xy {
    None => ()
    Some(values) => {
      let at = b.vector(values.length() * 2, 8)
      for value in values {
        b.writer.double(value.x)
        b.writer.double(value.y)
      }
      b.reference(table, 1, at)
    }
  }
  native_write_doubles(b, table, 2, g.z)
  native_write_doubles(b, table, 3, g.m)
  native_write_doubles(b, table, 4, g.t)
  match g.tm {
    None => ()
    Some(values) => {
      let at = b.vector(values.length(), 8)
      for value in values {
        b.writer.long(value)
      }
      b.reference(table, 5, at)
    }
  }
  if g.declared_type != 0 {
    b.scalar(table, 6, g.declared_type)
  }
  match g.parts {
    None => ()
    Some(values) => {
      let at = b.vector(values.length(), 4)
      b.writer.zeros(values.length() * 4)
      for i in 0..<values.length() {
        let child = native_write_geometry(b, values[i])
        b.writer.patch_word(at + 4 + i * 4, child - (at + 4 + i * 4))
      }
      b.reference(table, 7, at)
    }
  }
  table
}
