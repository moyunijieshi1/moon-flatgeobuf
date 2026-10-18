///|
priv struct TableView {
  data : Bytes
  position : Int
  vtable : Int
  fields : Int
  size : Int
}

///|
fn TableView::open(data : Bytes, position : Int) -> TableView raise FgbError {
  require_range(data, position, 4)
  let distance = i32(data, position)
  let wide = position.to_int64() - distance.to_int64()
  if wide < 0L || wide > 2147483647L {
    raise InvalidData(position, "vtable offset overflow")
  }
  let vtable = wide.to_int()
  let length = u16(data, vtable)
  let size = u16(data, vtable + 2)
  if length < 4 || length % 2 != 0 || size < 4 {
    raise InvalidData(vtable, "invalid vtable or object length")
  }
  require_range(data, vtable, length)
  require_range(data, position, size)
  { data, position, vtable, fields: (length - 4) / 2, size, }
}

///|
fn TableView::root(data : Bytes) -> TableView raise FgbError {
  let offset = size32(data, 0)
  if offset < 4 {
    raise InvalidData(0, "invalid root offset")
  }
  TableView::open(data, offset)
}

///|
fn TableView::field(
  self : TableView,
  id : Int,
  width : Int,
) -> Int raise FgbError {
  if id >= self.fields {
    return 0
  }
  let offset = u16(self.data, self.vtable + 4 + id * 2)
  if offset == 0 {
    return 0
  }
  if offset < 4 || offset > self.size || width > self.size - offset {
    raise InvalidData(self.position, "field exceeds object boundary")
  }
  self.position + offset
}

///|
fn TableView::byte(
  self : TableView,
  id : Int,
  fallback? : Int = 0,
) -> Int raise FgbError {
  let at = self.field(id, 1)
  if at == 0 {
    fallback
  } else {
    u8(self.data, at)
  }
}

///|
fn TableView::short(
  self : TableView,
  id : Int,
  fallback? : Int = 0,
) -> Int raise FgbError {
  let at = self.field(id, 2)
  if at == 0 {
    fallback
  } else {
    u16(self.data, at)
  }
}

///|
fn TableView::int(
  self : TableView,
  id : Int,
  fallback? : Int = 0,
) -> Int raise FgbError {
  let at = self.field(id, 4)
  if at == 0 {
    fallback
  } else {
    i32(self.data, at)
  }
}

///|
fn TableView::count(self : TableView, id : Int) -> Int raise FgbError {
  let at = self.field(id, 8)
  if at == 0 {
    0
  } else {
    size64(self.data, at)
  }
}

///|
fn indirect(data : Bytes, at : Int) -> Int raise FgbError {
  let delta = size32(data, at)
  if delta < 4 {
    raise InvalidData(at, "invalid forward reference")
  }
  let target = checked_add(at, delta)
  require_range(data, target, 4)
  target
}

///|
fn TableView::reference(self : TableView, id : Int) -> Int raise FgbError {
  let at = self.field(id, 4)
  if at == 0 {
    0
  } else {
    indirect(self.data, at)
  }
}

///|
fn text_at(data : Bytes, at : Int, limits : Limits) -> String raise FgbError {
  let size = size32(data, at)
  let start = checked_add(at, 4)
  require_range(data, start, checked_add(size, 1))
  if u8(data, start + size) != 0 {
    raise InvalidData(start + size, "missing FlatBuffers string terminator")
  }
  decode_text(data, start, size, limits)
}

///|
fn TableView::text(
  self : TableView,
  id : Int,
  limits : Limits,
) -> String raise FgbError {
  let at = self.reference(id)
  if at == 0 {
    ""
  } else {
    text_at(self.data, at, limits)
  }
}

///|
fn TableView::vector(
  self : TableView,
  id : Int,
  width : Int,
  limit : Int,
) -> (Int, Int) raise FgbError {
  let at = self.reference(id)
  if at == 0 {
    return (0, 0)
  }
  let count = size32(self.data, at)
  enforce(count, limit, "vector elements")
  let bytes = checked_mul(count, width)
  let start = checked_add(at, 4)
  require_range(self.data, start, bytes)
  (start, count)
}

///|
priv struct FbBuilder {
  writer : ByteWriter
}

///|
fn FbBuilder::new() -> FbBuilder {
  let writer = ByteWriter::new()
  writer.zeros(8)
  { writer, }
}

///|
fn FbBuilder::table(self : FbBuilder, fields : Int) -> Int {
  self.writer.align(2)
  let vt = self.writer.position()
  self.writer.short(4 + 2 * fields)
  self.writer.short(8 + 8 * fields)
  self.writer.zeros(fields * 2)
  self.writer.align(8)
  let table = self.writer.position()
  self.writer.word((table - vt).reinterpret_as_uint())
  self.writer.zeros(4 + fields * 8)
  table
}

///|
fn FbBuilder::slot(self : FbBuilder, table : Int, field : Int) -> Int {
  let at = table + 8 + field * 8
  let distance = self.writer.data[table].to_int() |
    (self.writer.data[table + 1].to_int() << 8) |
    (self.writer.data[table + 2].to_int() << 16) |
    (self.writer.data[table + 3].to_int() << 24)
  self.writer.patch_short(table - distance + 4 + field * 2, 8 + field * 8)
  at
}

///|
fn FbBuilder::scalar(
  self : FbBuilder,
  table : Int,
  field : Int,
  value : Int,
) -> Unit {
  let at = self.slot(table, field)
  self.writer.patch_word(at, value)
}

///|
fn FbBuilder::long(
  self : FbBuilder,
  table : Int,
  field : Int,
  value : Int,
) -> Unit {
  let at = self.slot(table, field)
  self.writer.patch_long(at, value.to_uint64())
}

///|
fn FbBuilder::reference(
  self : FbBuilder,
  table : Int,
  field : Int,
  target : Int,
) -> Unit {
  let at = self.slot(table, field)
  self.writer.patch_word(at, target - at)
}

///|
fn FbBuilder::text(
  self : FbBuilder,
  table : Int,
  field : Int,
  text : String,
) -> Unit {
  self.writer.align(4)
  let at = self.writer.position()
  let bytes = @utf8.encode(text)
  self.writer.word(bytes.length().reinterpret_as_uint())
  self.writer.bytes(bytes)
  self.writer.byte(0)
  self.reference(table, field, at)
}

///|
fn FbBuilder::vector(self : FbBuilder, count : Int, width : Int) -> Int {
  self.writer.align(if width == 8 { 8 } else { 4 }, bias=4)
  let at = self.writer.position()
  self.writer.word(count.reinterpret_as_uint())
  at
}

///|
fn FbBuilder::finish(self : FbBuilder, root : Int) -> Bytes {
  self.writer.align(8)
  self.writer.patch_word(4, root - 4)
  self.writer.patch_word(0, self.writer.position() - 4)
  self.writer.finish()
}
