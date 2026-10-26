///|
test "header retains schema metadata and CRS" {
  let h = {
    ..Header::new(Polygon, [Column::new("name", 11)]),
    name: "regions",
    features_count: 12,
    index_node_size: 16,
    crs: Some(Crs::epsg(4326)),
    envelope: Some({ min_x: -180.0, min_y: -90.0, max_x: 180.0, max_y: 90.0, }),
  }
  assert_eq(decode_header(encode_header(h)), h)
}

///|
test "magic accepts compatible patch revisions and rejects major changes" {
  validate_magic(b"\x66\x67\x62\x03\x66\x67\x62\x09")
  let rejected = try {
    validate_magic(b"\x66\x67\x62\x04\x66\x67\x62\x01")
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
test "all header column and CRS strings honor the configured byte limit" {
  let base = Header::new(Point, [Column::new("x", 11)])
  let text = "天地"
  let limits = { ..Limits::default(), max_string_bytes: 4, }
  let headers = [
    { ..base, name: text, },
    { ..base, title: text, },
    { ..base, description: text, },
    { ..base, metadata: text, },
    { ..base, columns: [{ ..base.columns[0], name: text, }], },
    { ..base, columns: [{ ..base.columns[0], title: text, }], },
    { ..base, columns: [{ ..base.columns[0], description: text, }], },
    { ..base, columns: [{ ..base.columns[0], metadata: text, }], },
    { ..base, crs: Some({ ..Crs::epsg(4326), org: text, }), },
    { ..base, crs: Some({ ..Crs::epsg(4326), name: text, }), },
    { ..base, crs: Some({ ..Crs::epsg(4326), description: text, }), },
    { ..base, crs: Some({ ..Crs::epsg(4326), wkt: text, }), },
    { ..base, crs: Some({ ..Crs::epsg(4326), code_string: text, }), },
  ]
  for header in headers {
    assert_true(
      try {
        encode_header(header, limits~) |> ignore
        false
      } catch {
        LimitExceeded(_) => true
        _ => false
      },
    )
    assert_true(
      try {
        decode_header(encode_header(header), limits~) |> ignore
        false
      } catch {
        LimitExceeded(_) => true
        _ => false
      },
    )
  }
}

///|
test "header string budgets measure UTF8 bytes and include exact boundaries" {
  let header = { ..Header::new(Point, [Column::new("中", 11)]), title: "文", }
  let limits = { ..Limits::default(), max_string_bytes: 3, }
  assert_eq(decode_header(encode_header(header, limits~), limits~), header)
  assert_true(
    try {
      validate_header(header, limits={ ..limits, max_string_bytes: 0, })
      false
    } catch {
      InvalidArgument(_) => true
      _ => false
    },
  )
}
