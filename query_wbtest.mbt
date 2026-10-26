///|
fn selection_world() -> Bounds {
  { min_x: -10.0, min_y: -10.0, max_x: 200.0, max_y: 20.0, }
}

///|
test "selection removes spatial false positives before counting offset" {
  let bytes = write_dataset(sample_dataset(3), options={
    index_node_size: 4,
    hilbert_sort: false,
  })
  let reader = Reader::open(bytes)
  let levels = index_levels(3, 4)
  let expanded = ByteWriter::new()
  expanded.bytes(bytes)
  let leaf = reader.index_start + levels[0].start * 40
  expanded.patch_long(leaf + 16, 2.0.reinterpret_as_uint64())
  expanded.patch_long(leaf + 24, 2.0.reinterpret_as_uint64())
  let reader = Reader::open(expanded.finish())
  reader.validate()
  let result = reader.select({
    ..Selection::all(),
    bounds: Some({ min_x: 1.0, min_y: 0.0, max_x: 2.0, max_y: 2.0, }),
    offset: 1,
    limit: 1,
  })
  assert_eq(result.features.map(f => f.properties[0]), [Integer(2L)])
}

///|
test "selection stops decoding once the requested page is full" {
  for indexed in [true, false] {
    let bytes = write_dataset(sample_dataset(17), options={
      index_node_size: if indexed {
        4
      } else {
        0
      },
      hilbert_sort: false,
    })
    // A corrupt later record proves that the earlier page does not decode it.
    let reader = Reader::open(slice_bytes(bytes, 0, bytes.length() - 1))
    for bounds in [None, Some(selection_world())] {
      let selection = { ..Selection::all(), bounds, limit: 1, }
      let page = reader.select(selection)
      assert_eq(page.features[0].properties, [Integer(0L)])
      assert_true(
        try {
          reader.select({ ..selection, limit: 17, }) |> ignore
          false
        } catch {
          _ => true
        },
      )
    }
  }
}

///|
test "selection applies predicates then offset then projection in file order" {
  for node_size in [0, 2, 4, 16] {
    let reader = Reader::open(
      write_dataset(sample_dataset(50), options={
        index_node_size: node_size,
        hilbert_sort: false,
      }),
    )
    for bounds in [None, Some(selection_world())] {
      let result = reader.select({
        bounds,
        predicate: Some(
          All([
            NumericRange("id", Some(5.0), Some(12.0)),
            IsNotNull("id"),
            Any([Equal("id", Integer(6L)), Not(Equal("id", Integer(8L)))]),
          ]),
        ),
        fields: Some(["id"]),
        offset: 2,
        limit: 3,
      })
      assert_eq(result.features.map(f => f.properties[0]), [
        Integer(7L),
        Integer(9L),
        Integer(10L),
      ])
      assert_eq(result.header.features_count, 3)
      assert_eq(result.header.index_node_size, 0)
      assert_eq(result.header.columns.map(c => c.name), ["id"])
    }
  }
}

///|
test "bound text null equality and Boolean expressions retain public semantics" {
  let dataset : Dataset = {
    header: Header::new(Point, [Column::new("id", 5), Column::new("name", 11)]),
    features: Array::makei(6, i => {
      geometry: Some(Geometry::point(i.to_double(), 0.0)),
      properties: [
        Integer(i.to_int64()),
        if i % 2 == 0 {
          Null
        } else {
          Text("站点-\{i}")
        },
      ],
    }),
  }
  let reader = Reader::open(
    write_dataset(dataset, options={ index_node_size: 4, hilbert_sort: false, }),
  )
  let cases : Array[(Predicate, Array[Int64])] = [
    (IsNull("name"), [0L, 2L, 4L]),
    (IsNotNull("name"), [1L, 3L, 5L]),
    (TextContains("name", "站点-3"), [3L]),
    (Equal("name", Null), [0L, 2L, 4L]),
    (NotEqual("name", Null), [1L, 3L, 5L]),
    (All([]), [0L, 1L, 2L, 3L, 4L, 5L]),
    (Any([]), []),
    (Not(Any([IsNull("name"), Equal("id", Integer(3L))])), [1L, 5L]),
  ]
  for (predicate, ids) in cases {
    let result = reader.select({
      ..Selection::all(),
      predicate: Some(predicate),
      fields: Some(["name", "id"]),
    })
    assert_eq(result.header.columns.map(c => c.name), ["name", "id"])
    assert_eq(
      result.features.map(f => f.properties[1]),
      ids.map(id => Integer(id)),
    )
  }
}

///|
test "zero page validates all arguments before reading malformed feature data" {
  let bytes = write_dataset(sample_dataset(2))
  let reader = Reader::open(slice_bytes(bytes, 0, bytes.length() - 1))
  let empty = { ..Selection::all(), limit: 0, fields: Some([]), }
  let result = reader.select(empty)
  assert_eq(result.features, [])
  assert_eq(result.header.columns, [])
  assert_eq(result.header.features_count, 0)
  assert_eq(result.header.envelope, None)
  let invalid = [
    { ..empty, fields: Some(["missing"]), },
    { ..empty, fields: Some(["id", "id"]), },
    { ..empty, predicate: Some(Equal("missing", Null)), },
    { ..empty, predicate: Some(TextContains("id", "x")), },
    { ..empty, predicate: Some(NumericRange("id", Some(2.0), Some(1.0))), },
    { ..empty, offset: -1, },
    { ..empty, limit: -1, },
    {
      ..empty,
      bounds: Some({ min_x: 2.0, min_y: 0.0, max_x: 1.0, max_y: 1.0, }),
    },
  ]
  for selection in invalid {
    assert_true(
      try {
        reader.select(selection) |> ignore
        false
      } catch {
        InvalidArgument(_) => true
        _ => false
      },
    )
  }
}

///|
test "selection preserves an active cursor on both success and decoding failure" {
  for node_size in [0, 4] {
    let bytes = write_dataset(sample_dataset(17), options={
      index_node_size: node_size,
      hilbert_sort: false,
    })
    let reader = Reader::open(slice_bytes(bytes, 0, bytes.length() - 1))
    reader.next() |> ignore
    let cursor = reader.cursor
    for bounds in [None, Some(selection_world())] {
      reader.select({ ..Selection::all(), bounds, limit: 2, }) |> ignore
      assert_eq(reader.cursor, cursor)
      assert_eq(reader.ordinal, 1)
      assert_true(
        try {
          reader.select({ ..Selection::all(), bounds, }) |> ignore
          false
        } catch {
          _ => true
        },
      )
      assert_eq(reader.cursor, cursor)
      assert_eq(reader.ordinal, 1)
    }
  }
}

///|
test "incremental packed traversal retains ordinal order across tree depths" {
  for count in [1, 2, 17, 103] {
    for node_size in [2, 4, 16] {
      let reader = Reader::open(
        write_dataset(sample_dataset(count), options={
          index_node_size: node_size,
          hilbert_sort: false,
        }),
      )
      let hits = reader.query(selection_world())
      assert_eq(hits.map(h => h.ordinal), Array::makei(count, i => i))
      let selected = reader.select({
        ..Selection::all(),
        bounds: Some(selection_world()),
        offset: 1,
        limit: 2,
      })
      assert_eq(
        selected.features.map(f => f.properties[0]),
        hits
        .filter(h => h.ordinal >= 1 && h.ordinal < 3)
        .map(h => h.feature.properties[0]),
      )
    }
  }
}
