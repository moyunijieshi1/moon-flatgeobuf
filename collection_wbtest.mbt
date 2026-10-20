///|
fn collection(parts : Array[Geometry]) -> Geometry {
  { kind: GeometryCollection, xy: [], ends: [], parts, }
}

///|
fn collection_fixture() -> Geometry {
  collection([
    Geometry::point(-2.0, 3.0),
    {
      kind: LineString,
      xy: [{ x: 0.0, y: 0.0, }, { x: 9.0, y: 4.0, }],
      ends: [],
      parts: [],
    },
    collection([Geometry::point(1.0, -5.0), collection([])]),
  ])
}

///|
test "collection type code empty and nested geometry round trips" {
  assert_eq(GeometryCollection.code(), 7)
  for geometry in [collection([]), collection_fixture()] {
    let header = Header::new(GeometryCollection, [Column::new("name", 11)])
    let feature : Feature = {
      geometry: Some(geometry),
      properties: [Text("集合")],
    }
    let bytes = encode_feature(feature, header)
    assert_eq(decode_feature(bytes, header), feature)
    let generic = { ..header, geometry_kind: Unknown, }
    assert_eq(
      decode_feature(encode_feature(feature, generic), generic),
      feature,
    )
    let json = geometry.to_geojson()
    assert_eq(geometry_from_geojson(json), geometry)
  }
}

///|
test "collection bounds and indexed queries include every nested member" {
  let geometry = collection_fixture()
  assert_eq(
    geometry.bounds(),
    Some({ min_x: -2.0, min_y: -5.0, max_x: 9.0, max_y: 4.0, }),
  )
  assert_eq(geometry.coordinate_count(), 4)
  let dataset : Dataset = {
    header: Header::new(GeometryCollection, []),
    features: [{ geometry: Some(geometry), properties: [], }],
  }
  let bytes = write_dataset(dataset)
  let reader = Reader::open(bytes)
  reader.validate()
  let bounds : Bounds = { min_x: 0.5, min_y: -5.0, max_x: 1.5, max_y: -4.5, }
  assert_eq(reader.query(bounds).length(), 1)
  let session = RangeQuery::new(bounds)
  assert_eq(feed_range_session(session, bytes).features, dataset.features)
  let stream = StreamDecoder::new()
  let records : Array[FeatureRecord] = []
  for byte in bytes {
    for record in stream.push(Bytes::makei(1, _ => byte)) {
      records.push(record)
    }
  }
  stream.finish()
  assert_eq(records[0].feature, dataset.features[0])
}

///|
test "empty collection is retained in unindexed files and explicitly rejected for index building" {
  let dataset : Dataset = {
    header: Header::new(GeometryCollection, []),
    features: [{ geometry: Some(collection([])), properties: [], }],
  }
  let bytes = write_dataset(dataset, options={
    index_node_size: 0,
    hilbert_sort: false,
  })
  assert_eq(read_dataset(bytes).features, dataset.features)
  assert_true(
    try {
      write_dataset(dataset) |> ignore
      false
    } catch {
      _ => true
    },
  )
}

///|
test "collections enforce shared node coordinate and nesting budgets" {
  let geometry = collection_fixture()
  assert_true(
    try {
      geometry.validate(limits={ ..Limits::default(), max_geometry_nodes: 3, })
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      geometry.validate(limits={ ..Limits::default(), max_coordinates: 3, })
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      geometry.validate(limits={ ..Limits::default(), max_depth: 2, })
      false
    } catch {
      _ => true
    },
  )
  let json = geometry.to_geojson()
  assert_true(
    try {
      geometry_from_geojson(json, limits={
        ..Limits::default(),
        max_coordinates: 3,
      })
      |> ignore
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      geometry_from_geojson(json, limits={
        ..Limits::default(),
        max_geometry_nodes: 3,
      })
      |> ignore
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      geometry_from_geojson(json, limits={ ..Limits::default(), max_depth: 2, })
      |> ignore
      false
    } catch {
      _ => true
    },
  )
  let header = Header::new(GeometryCollection, [])
  let bytes = encode_feature(
    { geometry: Some(geometry), properties: [], },
    header,
  )
  assert_true(
    try {
      decode_feature(bytes, header, limits={
        ..Limits::default(),
        max_geometry_nodes: 3,
      })
      |> ignore
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      decode_feature(bytes, header, limits={
        ..Limits::default(),
        max_depth: 2,
      })
      |> ignore
      false
    } catch {
      _ => true
    },
  )
}

///|
test "collection rejects parent coordinate vectors and unknown child types" {
  let bad = { ..collection([]), xy: [{ x: 0.0, y: 1.0, }], }
  assert_true(
    try {
      bad.validate()
      false
    } catch {
      _ => true
    },
  )
  let b = FbBuilder::new()
  let root = b.table(8)
  b.scalar(root, 6, 7)
  let vector = b.vector(1, 4)
  b.writer.zeros(4)
  let child = b.table(8)
  b.reference(root, 7, vector)
  b.writer.patch_word(vector + 4, child - vector - 4)
  let bytes = sized_payload(b.finish(root), 0, 10000)
  assert_true(
    try {
      read_geometry(
        bytes,
        size32(bytes, 0),
        GeometryCollection,
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

///|
test "GeoJSON schema inference recognizes homogeneous and mixed collections" {
  let input = @json.parse(
    (
      #|{"type":"FeatureCollection","features":[{"type":"Feature","geometry":{"type":"GeometryCollection","geometries":[]},"properties":{}},{"type":"Feature","geometry":{"type":"Point","coordinates":[1,2]},"properties":{}}]}
    ),
  )
  let dataset = import_geojson(input)
  assert_eq(dataset.header.geometry_kind, Unknown)
  assert_eq(dataset.to_geojson(), input)
}
