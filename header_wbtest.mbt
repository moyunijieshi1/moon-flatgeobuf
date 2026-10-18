///|
test "header retains schema metadata and CRS" {
  let h = {
    ..Header::new(Polygon, [Column::new("name", 11)]),
    name: "regions", features_count: 12, index_node_size: 16,
    crs: Some(Crs::epsg(4326)),
    envelope: Some({ min_x: -180.0, min_y: -90.0, max_x: 180.0, max_y: 90.0 }),
  }
  assert_eq(decode_header(encode_header(h)), h)
}

///|
test "magic accepts compatible patch revisions and rejects major changes" {
  validate_magic(b"\x66\x67\x62\x03\x66\x67\x62\x09")
  let rejected = try {
    validate_magic(b"\x66\x67\x62\x04\x66\x67\x62\x01")
    false
  } catch { _ => true }
  assert_true(rejected)
}
