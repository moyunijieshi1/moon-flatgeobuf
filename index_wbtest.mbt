///|
test "packed level sizes include singleton root and check overflow" {
  assert_eq(index_byte_length(1, 16), 80)
  assert_eq(index_byte_length(17, 16), 800)
  assert_eq(index_byte_length(100, 0), 0)
  assert_true(try { index_byte_length(10, 1) |> ignore; false } catch { _ => true })
}

///|
test "index validates child containment and finds boundary contacts" {
  let w = ByteWriter::new()
  for (bounds, offset) in [
    ({ min_x: 0.0, min_y: 0.0, max_x: 5.0, max_y: 5.0 }, 1),
    ({ min_x: 0.0, min_y: 0.0, max_x: 1.0, max_y: 1.0 }, 0),
    ({ min_x: 4.0, min_y: 4.0, max_x: 5.0, max_y: 5.0 }, 100),
  ] {
    w.double(bounds.min_x)
    w.double(bounds.min_y)
    w.double(bounds.max_x)
    w.double(bounds.max_y)
    w.long(offset.to_uint64())
  }
  let data = w.finish()
  validate_index(data, 2, 16, 200)
  let hits = query_index(data, 2, 16, { min_x: 1.0, min_y: 1.0, max_x: 2.0, max_y: 2.0 })
  assert_eq(hits, [{ ordinal: 0, offset: 0 }])
  let broken = ByteWriter::new()
  broken.bytes(data)
  broken.patch_long(32, 2UL)
  assert_true(try { validate_index(broken.finish(), 2, 16, 200); false } catch { _ => true })
}
