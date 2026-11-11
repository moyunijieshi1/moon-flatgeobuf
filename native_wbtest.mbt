///|
fn native_curve_case(indexed : Bool) -> NativeDataset {
  let geometry = {
    ..NativeGeometry::new(8),
    xy: Some([{ x: 0.0, y: 0.0, }, { x: 1.0, y: 2.0, }, { x: 2.0, y: 0.0, }]),
    z: Some([10.0, 20.0, 30.0]),
    m: Some([1.0, 2.0, 3.0]),
    t: Some([2026.5, 2026.75, 2026.875]),
    tm: Some([0UL, 9007199254740993UL, 18446744073709551615UL]),
  }
  let feature : NativeFeature = {
    geometry: Some(geometry),
    properties: [Integer(-9223372036854775808L), Text("原生弧线")],
    columns: Some([NativeColumn::new("id", 7), NativeColumn::new("name", 11)]),
  }
  let header = {
    ..NativeHeader::new(8),
    name: Some("curve"),
    title: Some(""),
    has_z: true,
    has_m: true,
    has_t: true,
    has_tm: true,
    features_count: if indexed {
      1
    } else {
      0
    },
    index_node_size: if indexed {
      4
    } else {
      0
    },
    envelope: Some([
      -10.0, -10.0, -1.0e20, -1.0e20, -1.0e20, -1.0e20, 10.0, 10.0, 1.0e20, 1.0e20,
      1.0e20, 1.0e20,
    ]),
    crs: Some(NativeCrs::epsg(4326)),
  }
  { header, features: [feature], }
}

///|
test "native binary preserves curves dimensions local schema metadata and unknown counts" {
  for indexed in [false, true] {
    let source = native_curve_case(indexed)
    let bytes = write_native_dataset(source)
    let reader = NativeReader::open(bytes)
    reader.validate()
    assert_eq(reader.read_all(), source)
    assert_eq(reader.at(0).feature, source.features[0])
    let hits = reader.query({ min_x: 2.1, min_y: 0.0, max_x: 2.2, max_y: 2.0, })
    assert_eq(hits.map(r => r.feature), source.features)
    assert_eq(
      reader.query({ min_x: 3.0, min_y: 0.0, max_x: 4.0, max_y: 2.0, }).length(),
      0,
    )
  }
}

///|
test "native schema overrides distinguish absent empty and repeated names" {
  let header = {
    ..NativeHeader::new(0),
    columns: Some([NativeColumn::new("shared", 5)]),
  }
  let features : Array[NativeFeature] = [
    { geometry: None, columns: None, properties: [Integer(7L)], },
    {
      geometry: Some({ ..NativeGeometry::new(7), parts: Some([]), }),
      columns: Some([]),
      properties: [],
    },
    {
      geometry: Some({ ..NativeGeometry::new(2), xy: Some([]), }),
      columns: Some([
        NativeColumn::new("duplicate", 7),
        NativeColumn::new("duplicate", 8),
      ]),
      properties: [Integer(-1L), Unsigned(18446744073709551615UL)],
    },
  ]
  let dataset : NativeDataset = { header, features, }
  assert_eq(read_native_dataset(write_native_dataset(dataset)), dataset)
  assert_eq(features[0].effective_columns(header), header.columns.unwrap())
  assert_true(features[1].effective_columns(header).is_empty())
  assert_eq(features[2].effective_columns(header).length(), 2)
  assert_eq(features[1].bounds(), None)
  assert_eq(features[2].bounds(), None)
}

///|
test "native empty Point and nonfinite auxiliary measurements survive binary round trips" {
  let nan = 0x7ff8000000000000UL.reinterpret_as_double()
  let header = {
    ..NativeHeader::new(1),
    has_m: true,
    columns: Some([NativeColumn::new("f", 10)]),
  }
  let empty : NativeFeature = {
    geometry: Some(NativeGeometry::point(nan, nan)),
    columns: None,
    properties: [Real(1.0 / 0.0)],
  }
  let regular = {
    ..empty,
    geometry: Some({ ..NativeGeometry::point(1.0, 2.0), m: Some([nan]), }),
  }
  let decoded = read_native_dataset(
    write_native_dataset({ header, features: [empty, regular], }),
  )
  assert_eq(decoded.features[0].bounds(), None)
  let p = decoded.features[0].geometry.unwrap().xy.unwrap()[0]
  assert_true(p.x != p.x && p.y != p.y)
  let m = decoded.features[1].geometry.unwrap().m.unwrap()[0]
  assert_true(m != m)
  assert_eq(decoded.features[1].properties[0], Real(1.0 / 0.0))
}

///|
test "native stream writer and decoder keep types through arbitrary chunk boundaries" {
  let source = native_curve_case(true)
  let writer = NativeStreamWriter::new(source.header)
  let output = ByteWriter::new()
  output.bytes(writer.begin())
  output.bytes(writer.append(source.features[0]))
  writer.finish()
  let bytes = output.finish()
  let decoder = NativeStreamDecoder::new()
  let records : Array[NativeFeatureRecord] = []
  for i in 0..<bytes.length() {
    for r in decoder.push(Bytes::makei(1, _ => bytes[i])) {
      records.push(r)
    }
  }
  decoder.finish()
  assert_eq(records.map(r => r.feature), source.features)
  assert_eq(decoder.header().unwrap(), {
    ..source.header,
    features_count: 0,
    index_node_size: 0,
    envelope: None,
  })
  assert_eq(writer.features_written(), 1)
  assert_eq(writer.bytes_written(), bytes.length())
  assert_true(
    try {
      writer.append(source.features[0]) |> ignore
      false
    } catch {
      _ => true
    },
  )
}

///|
test "native range preserves full schema and dimensions for both archive layouts" {
  let query : Bounds = { min_x: 2.1, min_y: 0.0, max_x: 2.2, max_y: 2.0, }
  for indexed in [false, true] {
    let dataset = native_curve_case(indexed)
    let bytes = write_native_dataset(dataset)
    let session = NativeRangeQuery::new(query)
    let mut requests = 0
    while session.request() is Some(r) {
      requests += 1
      assert_true(requests < 20)
      session.accept({
        status: 206,
        etag: "\"native\"",
        content_range: "bytes \{r.start}-\{r.end_inclusive()}/\{bytes.length()}",
        body: slice_bytes(bytes, r.start, r.length),
      })
    }
    assert_true(session.is_complete())
    assert_eq(session.result().features, dataset.features)
    assert_eq(session.stats().matched, 1)
    assert_eq(session.header().unwrap(), dataset.header)
  }
}

///|
test "native parser and stream reject truncation and enforce configured limits" {
  let source = native_curve_case(true)
  let bytes = write_native_dataset(source)
  for at in [0, 8, 11, bytes.length() - 1] {
    let cut = slice_bytes(bytes, 0, at)
    assert_true(
      try {
        read_native_dataset(cut) |> ignore
        false
      } catch {
        _ => true
      },
    )
  }
  let limits = { ..Limits::default(), max_coordinates: 2, }
  assert_true(
    try {
      read_native_dataset(bytes, limits~) |> ignore
      false
    } catch {
      LimitExceeded(_) => true
      _ => false
    },
  )
  let decoder = NativeStreamDecoder::new()
  decoder.push(slice_bytes(bytes, 0, bytes.length() - 1)) |> ignore
  assert_true(
    try {
      decoder.finish()
      false
    } catch {
      _ => true
    },
  )
  assert_true(decoder.is_failed())
  let feature = source.features[0]
  let invalid = { ..feature.geometry.unwrap(), tm: Some([0UL]), }
  assert_true(
    try {
      encode_native_feature(
        { ..feature, geometry: Some(invalid), },
        source.header,
      )
      |> ignore
      false
    } catch {
      InvalidArgument(_) => true
      _ => false
    },
  )
}
