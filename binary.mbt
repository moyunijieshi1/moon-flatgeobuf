///|
fn u8(data : Bytes, at : Int32) -> Int32 raise FgbError {
  require_range(data, at, 1)
  data[at].to_int()
}

///|
fn u16(data : Bytes, at : Int32) -> Int32 raise FgbError {
  require_range(data, at, 2)
  data[at].to_int() | (data[at + 1].to_int() << 8)
}

///|
fn i16(data : Bytes, at : Int32) -> Int32 raise FgbError {
  let value = u16(data, at)
  if value >= 32768 {
    value - 65536
  } else {
    value
  }
}

///|
fn u32(data : Bytes, at : Int32) -> UInt32 raise FgbError {
  require_range(data, at, 4)
  let mut value = 0U
  for i in 0..<4 {
    value = value | (data[at + i].to_uint() << (i * 8))
  }
  value
}

///|
fn i32(data : Bytes, at : Int32) -> Int32 raise FgbError {
  u32(data, at).reinterpret_as_int()
}

///|
fn size32(data : Bytes, at : Int32) -> Int32 raise FgbError {
  let value = u32(data, at)
  if value > 2147483647U {
    raise InvalidData(at, "32-bit size exceeds addressable range")
  }
  value.reinterpret_as_int()
}

///|
fn u64(data : Bytes, at : Int32) -> UInt64 raise FgbError {
  require_range(data, at, 8)
  let mut value = 0UL
  for i in 0..<8 {
    value = value | (data[at + i].to_int().to_uint64() << (i * 8))
  }
  value
}

///|
fn size64(data : Bytes, at : Int32) -> Int32 raise FgbError {
  let value = u64(data, at)
  if value > 2147483647UL {
    raise InvalidData(at, "64-bit size exceeds supported 2 GiB address space")
  }
  value.to_int()
}

///|
fn f64(data : Bytes, at : Int32) -> Double raise FgbError {
  let result = u64(data, at).reinterpret_as_double()
  if !finite(result) {
    raise InvalidData(at, "non-finite number")
  }
  result
}

///|
fn f32(data : Bytes, at : Int32) -> Double raise FgbError {
  let result = Float::reinterpret_from_uint(u32(data, at)).to_double()
  if !finite(result) {
    raise InvalidData(at, "non-finite number")
  }
  result
}

///|
fn slice_bytes(data : Bytes, at : Int32, size : Int32) -> Bytes raise FgbError {
  require_range(data, at, size)
  Bytes::makei(size, i => data[at + i])
}

///|
fn decode_text(
  data : Bytes,
  at : Int32,
  size : Int32,
  limits : Limits,
) -> String raise FgbError {
  enforce(size, limits.max_string_bytes, "string bytes")
  let value = slice_bytes(data, at, size)
  @utf8.decode(value) catch {
    _ => raise InvalidData(at, "invalid UTF-8")
  }
}

///|
struct ByteWriter {
  data : Array[Byte]
}

///|
fn ByteWriter::new() -> ByteWriter {
  { data: [], }
}

///|
fn ByteWriter::position(self : ByteWriter) -> Int32 {
  self.data.length()
}

///|
fn ByteWriter::zeros(self : ByteWriter, count : Int32) -> Unit {
  for _ in 0..<count {
    self.data.push(0)
  }
}

///|
fn ByteWriter::align(
  self : ByteWriter,
  alignment : Int32,
  bias~ : Int32 = 0,
) -> Unit {
  while (self.position() + bias) % alignment != 0 {
    self.data.push(0)
  }
}

///|
fn ByteWriter::byte(self : ByteWriter, value : Int32) -> Unit {
  self.data.push((value & 255).to_byte())
}

///|
fn ByteWriter::short(self : ByteWriter, value : Int32) -> Unit {
  self.byte(value)
  self.byte(value >> 8)
}

///|
fn ByteWriter::word(self : ByteWriter, value : UInt32) -> Unit {
  for i in 0..<4 {
    self.byte((value >> (i * 8)).reinterpret_as_int())
  }
}

///|
fn ByteWriter::long(self : ByteWriter, value : UInt64) -> Unit {
  for i in 0..<8 {
    self.byte((value >> (i * 8)).to_int())
  }
}

///|
fn ByteWriter::double(self : ByteWriter, value : Double) -> Unit {
  self.long(value.reinterpret_as_uint64())
}

///|
fn ByteWriter::float(self : ByteWriter, value : Double) -> Unit {
  self.word(Float::from_double(value).reinterpret_as_uint())
}

///|
fn ByteWriter::bytes(self : ByteWriter, bytes : Bytes) -> Unit {
  for byte in bytes {
    self.data.push(byte)
  }
}

///|
fn ByteWriter::bytes_from(
  self : ByteWriter,
  bytes : Bytes,
  start : Int32,
  length : Int32,
) -> Unit raise FgbError {
  require_range(bytes, start, length)
  for i in 0..<length {
    self.data.push(bytes[start + i])
  }
}

///|
fn ByteWriter::patch_word(self : ByteWriter, at : Int32, value : Int32) -> Unit {
  for i in 0..<4 {
    self.data[at + i] = ((value >> (i * 8)) & 255).to_byte()
  }
}

///|
fn ByteWriter::patch_short(
  self : ByteWriter,
  at : Int32,
  value : Int32,
) -> Unit {
  self.data[at] = (value & 255).to_byte()
  self.data[at + 1] = ((value >> 8) & 255).to_byte()
}

///|
fn ByteWriter::patch_long(
  self : ByteWriter,
  at : Int32,
  value : UInt64,
) -> Unit {
  for i in 0..<8 {
    self.data[at + i] = ((value >> (i * 8)).to_int() & 255).to_byte()
  }
}

///|
fn ByteWriter::finish(self : ByteWriter) -> Bytes {
  Bytes::makei(self.data.length(), i => self.data[i])
}
