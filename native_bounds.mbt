///|
fn native_union(a : Bounds?, b : Bounds?) -> Bounds? {
  match (a, b) {
    (None, b) => b
    (a, None) => a
    (Some(a), Some(b)) => Some(a.union(b))
  }
}

///|
fn native_xy_bounds(xy : Array[Coordinate]) -> Bounds? {
  let mut result : Bounds? = None
  for p in xy {
    if finite(p.x) && finite(p.y) {
      result = native_union(
        result,
        Some({ min_x: p.x, min_y: p.y, max_x: p.x, max_y: p.y, }),
      )
    }
  }
  result
}

///|
fn native_angle_delta(from : Double, to : Double) -> Double {
  let d = to - from
  if d < 0.0 {
    d + 6.283185307179586
  } else {
    d
  }
}

///|
fn native_abs(x : Double) -> Double {
  if x < 0.0 {
    -x
  } else {
    x
  }
}

///|
fn native_full_bounds() -> Bounds {
  {
    min_x: -1.7976931348623157e308,
    min_y: -1.7976931348623157e308,
    max_x: 1.7976931348623157e308,
    max_y: 1.7976931348623157e308,
  }
}

///|
fn native_arc_bounds(a : Coordinate, b : Coordinate, c : Coordinate) -> Bounds {
  let initial = native_xy_bounds([a, b, c]).unwrap()
  let mut scale = 1.0
  for value in [a.x, a.y, b.x, b.y, c.x, c.y] {
    if native_abs(value) > scale {
      scale = native_abs(value)
    }
  }
  let ax = a.x / scale
  let ay = a.y / scale
  let ux = b.x / scale - ax
  let uy = b.y / scale - ay
  let vx = c.x / scale - ax
  let vy = c.y / scale - ay
  let full = a == c
  let det = 2.0 * (ux * vy - uy * vx)
  let (cx, cy, radius) = if full {
    (
      a.x / 2.0 + b.x / 2.0,
      a.y / 2.0 + b.y / 2.0,
      @math.hypot(ux, uy) * (scale / 2.0),
    )
  } else if det == 0.0 {
    return initial
  } else {
    let u2 = ux * ux + uy * uy
    let v2 = vx * vx + vy * vy
    let rx = (u2 * vy - v2 * uy) / det
    let ry = (ux * v2 - vx * u2) / det
    ((ax + rx) * scale, (ay + ry) * scale, @math.hypot(rx, ry) * scale)
  }
  if !finite(cx) || !finite(cy) || !finite(radius) {
    return native_full_bounds()
  }
  let start = @math.atan2(a.y / scale - cy / scale, a.x / scale - cx / scale)
  let middle = @math.atan2(b.y / scale - cy / scale, b.x / scale - cx / scale)
  let stop = @math.atan2(c.y / scale - cy / scale, c.x / scale - cx / scale)
  let ccw = native_angle_delta(start, middle) <= native_angle_delta(start, stop)
  let mut result = initial
  for
    (angle, x, y) in [
      (0.0, cx + radius, cy),
      (1.5707963267948966, cx, cy + radius),
      (3.141592653589793, cx - radius, cy),
      (-1.5707963267948966, cx, cy - radius),
    ] {
    let inside = full ||
      (if ccw {
        native_angle_delta(start, angle) <=
        native_angle_delta(start, stop) + 1.0e-14
      } else {
        native_angle_delta(angle, start) <=
        native_angle_delta(stop, start) + 1.0e-14
      })
    if inside {
      if !finite(x) || !finite(y) {
        return native_full_bounds()
      }
      result = result.union({ min_x: x, min_y: y, max_x: x, max_y: y, })
    }
  }
  result
}

///|
/// XY bounding box, including cardinal extrema along CircularString arcs.
/// Numerically unrepresentable circle bounds fall back to a conservative box.
pub fn NativeGeometry::bounds(self : NativeGeometry) -> Bounds? {
  if native_geometry_empty(self) {
    return None
  }
  let xy = self.xy.unwrap_or([])
  let mut result = native_xy_bounds(xy)
  if self.kind == 8 {
    for i = 0; i + 2 < xy.length(); i = i + 2 {
      result = native_union(
        result,
        Some(native_arc_bounds(xy[i], xy[i + 1], xy[i + 2])),
      )
    }
  }
  for part in self.parts.unwrap_or([]) {
    result = native_union(result, part.bounds())
  }
  result
}

///|
pub fn NativeFeature::bounds(self : NativeFeature) -> Bounds? {
  match self.geometry {
    None => None
    Some(g) => g.bounds()
  }
}

///|
fn native_envelope_xy(header : NativeHeader) -> Bounds? {
  match header.envelope {
    Some(values) if values.length() >= 4 => {
      let half = values.length() / 2
      Some({
        min_x: values[0],
        min_y: values[1],
        max_x: values[half],
        max_y: values[half + 1],
      })
    }
    _ => None
  }
}

///|
fn native_contains(outer : Bounds, inner : Bounds) -> Bool {
  // Independent circle calculations can differ by a few ULPs at extrema.
  let near = fn(a : Double, b : Double) {
    let scale = if native_abs(a) > native_abs(b) {
      native_abs(a)
    } else {
      native_abs(b)
    }
    native_abs(a - b) <= (if scale > 1.0 { scale } else { 1.0 }) * 1.0e-12
  }
  (outer.min_x <= inner.min_x || near(outer.min_x, inner.min_x)) &&
  (outer.min_y <= inner.min_y || near(outer.min_y, inner.min_y)) &&
  (outer.max_x >= inner.max_x || near(outer.max_x, inner.max_x)) &&
  (outer.max_y >= inner.max_y || near(outer.max_y, inner.max_y))
}
