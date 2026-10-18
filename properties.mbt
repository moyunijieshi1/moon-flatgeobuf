///|
fn property_width(code : Int) -> Int {
  match code {
    0 | 1 | 2 => 1
    3 | 4 => 2
    5 | 6 | 9 => 4
    7 | 8 | 10 => 8
    _ => 0
  }
}

///|
fn read_property(data : Bytes, at : Int, code : Int, limits : Limits) -> (Property, Int) raise FgbError {
  let width = property_width(code)
  if width > 0 {
    require_range(data, at, width)
  }
  let value : Property = match code {
    0 => {
      let n = u8(data, at)
      Integer((if n >= 128 { n - 256 } else { n }).to_int64())
    }
    1 => Unsigned(u8(data, at).to_uint64())
    2 => {
      let n = u8(data, at)
      if n > 1 {
        raise InvalidData(at, "boolean property is not 0 or 1")
      }
      Boolean(n == 1)
    }
    3 => Integer(i16(data, at).to_int64())
    4 => Unsigned(u16(data, at).to_uint64())
    5 => Integer(i32(data, at).to_int64())
    6 => Unsigned(u32(data, at).to_uint64())
    7 => Integer(u64(data, at).reinterpret_as_int64())
    8 => Unsigned(u64(data, at))
    9 => Real(f32(data, at))
    10 => Real(f64(data, at))
    11 | 12 | 13 | 14 => {
      let size = size32(data, at)
      enforce(size, limits.max_string_bytes, "property bytes")
      let start = checked_add(at, 4)
      let end = checked_add(start, size)
      require_range(data, start, size)
      let property = if code == 14 {
        Binary(slice_bytes(data, start, size))
      } else {
        let text = decode_text(data, start, size, limits)
        if code == 12 {
          try @json.parse(text) |> ignore catch {
            _ => raise InvalidData(start, "invalid JSON property")
          }
        }
        Text(text)
      }
      return (property, end)
    }
    _ => raise Unsupported("property type \{code}")
  }
  (value, at + width)
}

///|
pub fn decode_properties(data : Bytes, columns : Array[Column], limits? : Limits = Limits::default()) -> Array[Property] raise FgbError {
  limits.validate()
  enforce(columns.length(), limits.max_columns, "column count")
  let values = Array::make(columns.length(), Property::Null)
  let seen = Array::make(columns.length(), false)
  let mut cursor = 0
  while cursor < data.length() {
    let key = u16(data, cursor)
    cursor += 2
    if key >= columns.length() {
      raise InvalidData(cursor - 2, "property key exceeds schema")
    }
    if seen[key] {
      raise InvalidData(cursor - 2, "duplicate property key")
    }
    let (value, end) = read_property(data, cursor, columns[key].type_code, limits)
    values[key] = value
    seen[key] = true
    cursor = end
  }
  for i in 0..<columns.length() {
    if !seen[i] && !columns[i].nullable {
      raise InvalidData(cursor, "missing non-nullable property \{columns[i].name}")
    }
  }
  values
}

///|
fn signed_value(value : Property, minimum : Int64, maximum : Int64) -> Int64 raise FgbError {
  guard value is Integer(n) else {
    raise InvalidArgument("expected signed integer property")
  }
  if n < minimum || n > maximum {
    raise InvalidArgument("signed integer out of range")
  }
  n
}

///|
fn unsigned_value(value : Property, maximum : UInt64) -> UInt64 raise FgbError {
  let n = match value {
    Unsigned(n) => n
    Integer(n) if n >= 0L => n.reinterpret_as_uint64()
    _ => raise InvalidArgument("expected unsigned integer property")
  }
  if n > maximum {
    raise InvalidArgument("unsigned integer out of range")
  }
  n
}

///|
fn real_value(value : Property) -> Double raise FgbError {
  let n = match value {
    Real(n) => n
    Integer(n) => n.to_double()
    Unsigned(n) => n.to_double()
    _ => raise InvalidArgument("expected numeric property")
  }
  if !finite(n) {
    raise InvalidArgument("numeric property must be finite")
  }
  n
}

///|
fn write_property(writer : ByteWriter, value : Property, code : Int, limits : Limits) -> Unit raise FgbError {
  match code {
    0 => writer.byte(signed_value(value, -128L, 127L).to_int())
    1 => writer.byte(unsigned_value(value, 255UL).to_int())
    2 => {
      guard value is Boolean(flag) else {
        raise InvalidArgument("expected Bool property")
      }
      writer.byte(if flag { 1 } else { 0 })
    }
    3 => writer.short(signed_value(value, -32768L, 32767L).to_int())
    4 => writer.short(unsigned_value(value, 65535UL).to_int())
    5 => writer.word(signed_value(value, -2147483648L, 2147483647L).to_int().reinterpret_as_uint())
    6 => writer.word(unsigned_value(value, 4294967295UL).to_uint())
    7 => {
      guard value is Integer(n) else {
        raise InvalidArgument("expected Long property")
      }
      writer.long(n.reinterpret_as_uint64())
    }
    8 => writer.long(unsigned_value(value, 18446744073709551615UL))
    9 => {
      let n = real_value(value)
      if n > 3.4028234663852886e38 || n < -3.4028234663852886e38 {
        raise InvalidArgument("Float property overflow")
      }
      writer.float(n)
    }
    10 => writer.double(real_value(value))
    11 | 12 | 13 => {
      guard value is Text(text) else {
        raise InvalidArgument("expected textual property")
      }
      if code == 12 {
        try @json.parse(text) |> ignore catch {
          _ => raise InvalidArgument("invalid JSON property")
        }
      }
      let bytes = @utf8.encode(text)
      enforce(bytes.length(), limits.max_string_bytes, "property string")
      writer.word(bytes.length().reinterpret_as_uint())
      writer.bytes(bytes)
    }
    14 => {
      guard value is Binary(bytes) else {
        raise InvalidArgument("expected Binary property")
      }
      enforce(bytes.length(), limits.max_string_bytes, "binary property")
      writer.word(bytes.length().reinterpret_as_uint())
      writer.bytes(bytes)
    }
    _ => raise Unsupported("property type \{code}")
  }
}

///|
pub fn encode_properties(values : Array[Property], columns : Array[Column], limits? : Limits = Limits::default()) -> Bytes raise FgbError {
  limits.validate()
  enforce(columns.length(), limits.max_columns, "column count")
  if values.length() != columns.length() {
    raise InvalidArgument("property count differs from schema")
  }
  let writer = ByteWriter::new()
  for i in 0..<values.length() {
    if values[i] == Null {
      if !columns[i].nullable {
        raise InvalidArgument("null non-nullable property \{columns[i].name}")
      }
      continue
    }
    writer.short(i)
    write_property(writer, values[i], columns[i].type_code, limits)
    enforce(writer.position(), limits.max_feature_bytes, "properties buffer")
  }
  writer.finish()
}
