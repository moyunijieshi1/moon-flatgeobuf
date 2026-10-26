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
      Ref(0),
    )
    assert_eq(decoded, geometry)
  }
}

///|
test "single geometry tree validation still rejects malformed nested children" {
  let invalid : Array[Geometry] = [
    { kind: Point, xy: [], ends: [], parts: [], },
    { kind: LineString, xy: [{ x: 0.0, y: 0.0, }], ends: [], parts: [], },
    {
      kind: Polygon,
      xy: [
        { x: 0.0, y: 0.0, },
        { x: 1.0, y: 0.0, },
        { x: 1.0, y: 1.0, },
        { x: 0.0, y: 1.0, },
      ],
      ends: [],
      parts: [],
    },
    {
      kind: MultiPolygon,
      xy: [],
      ends: [],
      parts: [Geometry::point(0.0, 0.0)],
    },
  ]
  for child in invalid {
    let geometry = collection([Geometry::point(2.0, 3.0), collection([child])])
    let builder = FbBuilder::new()
    let at = write_geometry(builder, geometry)
    let payload = sized_payload(builder.finish(at), 0, 10000)
    assert_true(
      try {
        read_geometry(
          payload,
          size32(payload, 0),
          Unknown,
          Limits::default(),
          1,
          Ref(0),
          Ref(0),
        )
        |> ignore
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "deep collection decoding respects the exact shared depth budget" {
  let mut geometry = Geometry::point(3.0, 4.0)
  for _ in 0..<15 {
    geometry = collection([geometry])
  }
  let header = Header::new(GeometryCollection, [])
  let feature : Feature = { geometry: Some(geometry), properties: [], }
  let limits = {
    ..Limits::default(),
    max_depth: 16,
    max_geometry_nodes: 16,
    max_coordinates: 1,
  }
  let bytes = encode_feature(feature, header, limits~)
  assert_eq(decode_feature(bytes, header, limits~), feature)
  assert_true(
    try {
      decode_feature(bytes, header, limits={ ..limits, max_depth: 15, })
      |> ignore
      false
    } catch {
      LimitExceeded(_) => true
      _ => false
    },
  )
  assert_true(
    try {
      decode_feature(bytes, header, limits={ ..limits, max_geometry_nodes: 15, })
      |> ignore
      false
    } catch {
      LimitExceeded(_) => true
      _ => false
    },
  )
}
