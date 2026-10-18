///|
test "geometry validation rejects invalid ends and open rings" {
  let g : Geometry = {
    kind: Polygon,
    xy: [
      { x: 0.0, y: 0.0, },
      { x: 1.0, y: 0.0, },
      { x: 1.0, y: 1.0, },
      { x: 0.0, y: 1.0, },
    ],
    ends: [],
    parts: [],
  }
  assert_true(
    try {
      g.validate()
      false
    } catch {
      _ => true
    },
  )
  let closed = { ..g, xy: [g.xy[0], g.xy[1], g.xy[2], g.xy[0]], }
  closed.validate()
  assert_eq(closed.coordinate_count(), 4)
  assert_eq(
    closed.bounds(),
    Some({ min_x: 0.0, min_y: 0.0, max_x: 1.0, max_y: 1.0, }),
  )
}

///|
test "six supported geometries survive FlatBuffers encoding" {
  let polygon : Geometry = {
    kind: Polygon,
    ends: [],
    parts: [],
    xy: [
      { x: 0.0, y: 0.0, },
      { x: 2.0, y: 0.0, },
      { x: 0.0, y: 2.0, },
      { x: 0.0, y: 0.0, },
    ],
  }
  let geometries = [
    Geometry::point(3.5, -2.0),
    {
      kind: LineString,
      xy: [polygon.xy[0], polygon.xy[1]],
      ends: [],
      parts: [],
    },
    polygon,
    {
      kind: MultiPoint,
      xy: [polygon.xy[0], polygon.xy[1]],
      ends: [],
      parts: [],
    },
    {
      kind: MultiLineString,
      xy: [polygon.xy[0], polygon.xy[1]],
      ends: [2],
      parts: [],
    },
    { kind: MultiPolygon, xy: [], ends: [], parts: [polygon], },
  ]
  for geometry in geometries {
    geometry.validate()
    let b = FbBuilder::new()
    let root = write_geometry(b, geometry)
    let bytes = sized_payload(b.finish(root), 0, 10000)
    let decoded = read_geometry(
      bytes,
      size32(bytes, 0),
      Unknown,
      Limits::default(),
      1,
      Ref(0),
    )
    assert_eq(decoded, geometry)
  }
}
