///|
test "integer-valued decimal notation imports without loss" {
  let input = @json.parse(
    (
      #|{"type":"FeatureCollection","features":[{"type":"Feature","geometry":null,"properties":{"id":1.0}}]}
    ),
  )
  assert_eq(import_geojson(input).features[0].properties, [Integer(1L)])
  let mixed = @json.parse(
    (
      #|{"type":"FeatureCollection","features":[{"type":"Feature","geometry":null,"properties":{"n":9223372036854775807}},{"type":"Feature","geometry":null,"properties":{"n":0.5}}]}
    ),
  )
  assert_true(
    try {
      import_geojson(mixed) |> ignore
      false
    } catch {
      _ => true
    },
  )
}

///|
test "GeoJSON schema inference preserves nulls Unicode and exact integers" {
  let input = @json.parse(
    (
      #|{"type":"FeatureCollection","features":[{"type":"Feature","geometry":{"type":"Point","coordinates":[120,30]},"properties":{"name":"杭州","id":9223372036854775807}},{"type":"Feature","geometry":null,"properties":{"name":null,"id":2}}]}
    ),
  )
  let d = import_geojson(input)
  assert_eq(d.header.columns[0].name, "id")
  assert_eq(d.header.columns[0].type_code, 7)
  assert_eq(d.features[0].properties[0], Integer(9223372036854775807L))
  let bytes = write_dataset(d, options={
    index_node_size: 0,
    hilbert_sort: false,
  })
  let text = read_dataset(bytes).to_geojson().stringify()
  assert_true(text.contains("9223372036854775807"))
  assert_eq(@json.parse(text), input)
}

///|
test "GeoJSON rejects third coordinate unsupported types and unknown fields" {
  assert_true(
    try {
      geometry_from_geojson(
        @json.parse("{\"type\":\"Point\",\"coordinates\":[1,2,3]}"),
      )
      |> ignore
      false
    } catch {
      _ => true
    },
  )
  let h = Header::new(Point, [])
  assert_true(
    try {
      feature_from_geojson(
        @json.parse(
          "{\"type\":\"Feature\",\"geometry\":null,\"properties\":{\"x\":1}}",
        ),
        h,
      )
      |> ignore
      false
    } catch {
      _ => true
    },
  )
}

///|
test "selection composes spatial filtering predicates projection and pagination" {
  let reader = Reader::open(write_dataset(sample_dataset(50)))
  let s : Selection = {
    bounds: Some({ min_x: 10.0, min_y: 0.0, max_x: 30.0, max_y: 6.0, }),
    predicate: Some(NumericRange("id", Some(15.0), Some(25.0))),
    fields: Some(["id"]),
    offset: 2,
    limit: 3,
  }
  let d = reader.select(s)
  assert_eq(d.features.length(), 3)
  assert_eq(d.header.features_count, 3)
  assert_eq(d.header.index_node_size, 0)
  assert_true(
    try {
      reader.select({ ..s, fields: Some(["missing"]), }) |> ignore
      false
    } catch {
      _ => true
    },
  )
}
