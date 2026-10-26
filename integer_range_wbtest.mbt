///|
fn integer_range_reader(
  code : Int32,
  values : Array[Property],
  indexed : Bool,
) -> Reader raise FgbError {
  let dataset : Dataset = {
    header: Header::new(Point, [Column::new("value", code)]),
    features: values.mapi((i, value) => {
      geometry: Some(Geometry::point(i.to_double(), 0.0)),
      properties: [value],
    }),
  }
  Reader::open(
    write_dataset(dataset, options={
      index_node_size: if indexed {
        4
      } else {
        0
      },
      hilbert_sort: false,
    }),
  )
}

///|
test "signed integer ranges distinguish adjacent values above double precision" {
  let values : Array[Property] = [
    Integer(-9223372036854775808L),
    Integer(-9007199254740993L),
    Integer(-9007199254740992L),
    Integer(9007199254740992L),
    Integer(9007199254740993L),
    Integer(9223372036854775807L),
    Null,
  ]
  let cases : Array[(Predicate, Array[Property])] = [
    (
      Int64Range("value", Some(9007199254740993L), Some(9007199254740993L)),
      [values[4]],
    ),
    (
      Int64Range("value", Some(-9007199254740993L), Some(-9007199254740993L)),
      [values[1]],
    ),
    (
      Int64Range("value", None, Some(-9007199254740993L)),
      [values[0], values[1]],
    ),
    (Int64Range("value", Some(9223372036854775807L), None), [values[5]]),
    (Int64Range("value", None, None), values.filter(v => v != Null)),
  ]
  for indexed in [false, true] {
    let reader = integer_range_reader(7, values, indexed)
    for (predicate, expected) in cases {
      let result = reader.select({
        ..Selection::all(),
        bounds: Some(selection_world()),
        predicate: Some(predicate),
      })
      assert_eq(result.features.map(f => f.properties[0]), expected)
    }
  }
}

///|
test "unsigned integer ranges preserve UInt64 maximum without conversion" {
  let values : Array[Property] = [
    Unsigned(0UL),
    Unsigned(9007199254740992UL),
    Unsigned(9007199254740993UL),
    Unsigned(18446744073709551614UL),
    Unsigned(18446744073709551615UL),
    Null,
  ]
  for indexed in [false, true] {
    let reader = integer_range_reader(8, values, indexed)
    let cases : Array[(Predicate, Array[Property])] = [
      (
        UInt64Range("value", Some(9007199254740993UL), Some(9007199254740993UL)),
        [values[2]],
      ),
      (UInt64Range("value", Some(18446744073709551615UL), None), [values[4]]),
      (UInt64Range("value", None, Some(0UL)), [values[0]]),
      (UInt64Range("value", None, None), values.filter(v => v != Null)),
    ]
    for (predicate, expected) in cases {
      let result = reader.select({
        ..Selection::all(),
        predicate: Some(predicate),
      })
      assert_eq(result.features.map(f => f.properties[0]), expected)
    }
  }
}

///|
test "integer range validation rejects wrong column families and reversed bounds" {
  let reader = integer_range_reader(7, [Integer(1L)], false)
  for
    predicate in [
      UInt64Range("value", None, None),
      Int64Range("value", Some(2L), Some(1L)),
      Int64Range("missing", None, None),
    ] {
    assert_true(
      try {
        reader.select({
          ..Selection::all(),
          predicate: Some(predicate),
          limit: 0,
        })
        |> ignore
        false
      } catch {
        InvalidArgument(_) => true
        _ => false
      },
    )
  }
  assert_true(
    try {
      reader.select({
        ..Selection::all(),
        predicate: Some(NumericRange("value", None, None)),
      })
      |> ignore
      false
    } catch {
      Unsupported(_) => true
      _ => false
    },
  )
  let reader = integer_range_reader(8, [Unsigned(1UL)], false)
  for
    predicate in [
      Int64Range("value", None, None),
      UInt64Range("value", Some(2UL), Some(1UL)),
    ] {
    assert_true(
      try {
        reader.select({ ..Selection::all(), predicate: Some(predicate), })
        |> ignore
        false
      } catch {
        InvalidArgument(_) => true
        _ => false
      },
    )
  }
}

///|
test "exact integer predicates compose with projection and filtered pagination" {
  let reader = integer_range_reader(
    7,
    [
      Integer(9007199254740992L),
      Integer(9007199254740993L),
      Integer(9007199254740994L),
    ],
    true,
  )
  let selected = reader.select({
    bounds: Some(selection_world()),
    predicate: Some(
      All([
        Int64Range("value", Some(9007199254740993L), None),
        IsNotNull("value"),
      ]),
    ),
    offset: 1,
    limit: 1,
    fields: Some(["value"]),
  })
  assert_eq(selected.features[0].properties, [Integer(9007199254740994L)])
  for code in [0, 3, 5] {
    assert_eq(
      integer_range_reader(code, [Integer(-1L), Integer(1L)], false).select({
        ..Selection::all(),
        predicate: Some(Int64Range("value", Some(0L), None)),
      }).features[0].properties,
      [Integer(1L)],
    )
  }
  for code in [1, 4, 6] {
    assert_eq(
      integer_range_reader(code, [Unsigned(0UL), Unsigned(1UL)], false).select({
        ..Selection::all(),
        predicate: Some(UInt64Range("value", Some(1UL), None)),
      }).features[0].properties,
      [Unsigned(1UL)],
    )
  }
}
