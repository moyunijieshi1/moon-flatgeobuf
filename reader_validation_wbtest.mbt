///|
test "archive validation preserves an active cursor and EOF for both layouts" {
  for indexed in [true, false] {
    let bytes = write_dataset(sample_dataset(17), options={
      index_node_size: if indexed {
        4
      } else {
        0
      },
      hilbert_sort: false,
    })
    let reader = Reader::open(bytes)
    reader.next() |> ignore
    let cursor = reader.cursor
    reader.validate()
    assert_eq(reader.cursor, cursor)
    guard reader.next() is Some(second) else { fail("lost cursor") }
    assert_eq(second.ordinal, 1)
    while reader.next() is Some(_) {
      ()
    }
    reader.validate()
    assert_eq(reader.next(), None)
  }
}

///|
test "single pass validation catches late truncation without moving caller cursor" {
  for indexed in [true, false] {
    let bytes = write_dataset(sample_dataset(17), options={
      index_node_size: if indexed {
        4
      } else {
        0
      },
      hilbert_sort: false,
    })
    let reader = Reader::open(slice_bytes(bytes, 0, bytes.length() - 1))
    reader.next() |> ignore
    let cursor = reader.cursor
    let rejected = try {
      reader.validate()
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
    assert_eq(reader.cursor, cursor)
    assert_eq(reader.ordinal, 1)
  }
}

///|
test "validation checks feature boundaries even when index offsets are increasing" {
  let bytes = write_dataset(sample_dataset(3), options={
    index_node_size: 4,
    hilbert_sort: false,
  })
  let reader = Reader::open(bytes)
  let levels = index_levels(3, 4)
  let at = reader.index_start + (levels[0].start + 1) * 40 + 32
  let modified = ByteWriter::new()
  modified.bytes(bytes)
  modified.patch_long(at, (size64(bytes, at) + 1).to_uint64())
  assert_true(
    try {
      Reader::open(modified.finish()).validate()
      false
    } catch {
      _ => true
    },
  )
}
