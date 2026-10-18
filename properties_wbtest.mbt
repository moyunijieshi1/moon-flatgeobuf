///|
test "property codec handles every column type and null omission" {
  let codes = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 11]
  let columns = codes.mapi((i, c) => Column::new("c\{i}", c))
  let values : Array[Property] = [
    Integer(-128L), Unsigned(255UL), Boolean(true), Integer(-32768L),
    Unsigned(65535UL), Integer(-2147483648L), Unsigned(4294967295UL),
    Integer(-9223372036854775808L), Unsigned(18446744073709551615UL),
    Real(1.5), Real(3.5), Text("你好"), Text("{\"a\":1}"),
    Text("2026-10-18T12:00:00Z"), Binary(b"\x00\xff"), Null,
  ]
  assert_eq(decode_properties(encode_properties(values, columns), columns), values)
}

///|
test "properties reject duplicate keys missing required fields and overflow" {
  let columns = [Column::new("id", 0, nullable=false)]
  assert_true(try { decode_properties(b"", columns) |> ignore; false } catch { _ => true })
  assert_true(try { decode_properties(b"\x00\x00\x01\x00\x00\x02", columns) |> ignore; false } catch { _ => true })
  assert_true(try { encode_properties([Integer(128L)], columns) |> ignore; false } catch { _ => true })
}
