///|
fn sample_dataset(count : Int) -> Dataset {
  {
    header: Header::new(Point, [Column::new("id", 5)]),
    features: Array::makei(count, i => {
      geometry: Some(Geometry::point(i.to_double(), (i % 7).to_double())),
      properties: [Integer(i.to_int64())],
    }),
  }
}

///|
test "indexed writer and sequential reader preserve feature identity" {
  let input = sample_dataset(100)
  let bytes = write_dataset(input)
  let reader = Reader::open(bytes)
  reader.validate()
  let output = reader.read_all()
  assert_eq(output.features.length(), 100)
  let ids : Map[Int64, Bool] = Map([])
  for feature in output.features {
    guard feature.properties[0] is Integer(id) else { fail("missing id") }
    ids[id] = true
    assert_eq(feature.geometry, Some(Geometry::point(id.to_double(), (id % 7L).to_double())))
  }
  assert_eq(ids.length(), 100)
  let q : Bounds = { min_x: 10.0, min_y: 0.0, max_x: 30.0, max_y: 6.0 }
  assert_eq(reader.query(q).length(), 21)
  for hit in reader.query(q) {
    assert_eq(reader.at(hit.ordinal), hit)
  }
}

///|
test "indexed queries agree with full scans for many boxes" {
  let d = sample_dataset(103)
  let indexed = Reader::open(write_dataset(d, options={ index_node_size: 4, hilbert_sort: true }))
  let scanned = Reader::open(write_dataset(d, options={ index_node_size: 0, hilbert_sort: false }))
  for i in 0..<40 {
    let b : Bounds = { min_x: (i - 3).to_double(), min_y: 1.0, max_x: (i + 9).to_double(), max_y: 4.0 }
    let a = indexed.query(b).map(r => r.feature.properties[0])
    let c = scanned.query(b).map(r => r.feature.properties[0])
    assert_eq(a.length(), c.length())
    for item in a { assert_true(c.contains(item)) }
  }
}

///|
test "empty singleton null and unknown-count files are handled explicitly" {
  let empty = Reader::open(write_dataset(sample_dataset(0)))
  assert_false(empty.has_index())
  assert_eq(empty.read_all().features.length(), 0)
  Reader::open(write_dataset(sample_dataset(1))).validate()
  let d : Dataset = {
    header: Header::new(Unknown, []),
    features: [{ geometry: None, properties: [] }],
  }
  let no_index : WriteOptions = { index_node_size: 0, hilbert_sort: false }
  assert_eq(read_dataset(write_dataset(d, options=no_index)).features, d.features)
  assert_true(try { write_dataset(d) |> ignore; false } catch { _ => true })
}

///|
test "truncated feature buffers and false declared counts are rejected" {
  let bytes = write_dataset(sample_dataset(5))
  let shortened = slice_bytes(bytes, 0, bytes.length() - 1)
  assert_true(try { read_dataset(shortened) |> ignore; false } catch { _ => true })
  let reader = Reader::open(bytes)
  assert_true(try { reader.at(-1) |> ignore; false } catch { _ => true })
  assert_true(try { reader.at(5) |> ignore; false } catch { _ => true })
}
