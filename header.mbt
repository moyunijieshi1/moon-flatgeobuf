///|
pub fn validate_magic(data : Bytes) -> Unit raise FgbError {
  require_range(data, 0, 8)
  let expected = b"\x66\x67\x62\x03\x66\x67\x62"
  for i in 0..<7 {
    if data[i] != expected[i] {
      raise InvalidData(i, "invalid FlatGeobuf magic or major version")
    }
  }
}

///|
fn sized_payload(
  data : Bytes,
  at : Int32,
  limit : Int32,
) -> Bytes raise FgbError {
  let size = size32(data, at)
  enforce(size, limit, "size-prefixed buffer")
  if size < 4 {
    raise InvalidData(at, "size-prefixed buffer is too small")
  }
  slice_bytes(data, checked_add(at, 4), size)
}

///|
fn read_column(
  data : Bytes,
  at : Int32,
  limits : Limits,
) -> Column raise FgbError {
  let t = TableView::open(data, at)
  let name = t.text(0, limits)
  if name.is_empty() {
    raise InvalidData(at, "column name is required")
  }
  let code = t.byte(1)
  if code > 14 {
    raise Unsupported("column type \{code}")
  }
  {
    name,
    type_code: code,
    title: t.text(2, limits),
    description: t.text(3, limits),
    width: t.int(4, fallback=-1),
    precision: t.int(5, fallback=-1),
    scale: t.int(6, fallback=-1),
    nullable: t.byte(7, fallback=1) != 0,
    unique: t.byte(8) != 0,
    primary_key: t.byte(9) != 0,
    metadata: t.text(10, limits),
  }
}

///|
fn read_crs(data : Bytes, at : Int32, limits : Limits) -> Crs raise FgbError {
  let t = TableView::open(data, at)
  {
    org: t.text(0, limits),
    code: t.int(1),
    name: t.text(2, limits),
    description: t.text(3, limits),
    wkt: t.text(4, limits),
    code_string: t.text(5, limits),
  }
}

///|
pub fn decode_header(
  data : Bytes,
  limits~ : Limits = Limits::default(),
) -> Header raise FgbError {
  limits.validate()
  let payload = sized_payload(data, 0, limits.max_header_bytes)
  if payload.length() + 4 != data.length() {
    raise InvalidData(0, "trailing data after header")
  }
  let t = TableView::root(payload)
  for field in 3..<7 {
    if t.byte(field) != 0 {
      raise Unsupported("Z/M/T/TM coordinates")
    }
  }
  let columns : Array[Column] = []
  let (start, count) = t.vector(7, 4, limits.max_columns)
  let names : Map[String, Bool] = Map([])
  for i in 0..<count {
    let column = read_column(payload, indirect(payload, start + i * 4), limits)
    if names.contains(column.name) {
      raise InvalidData(start, "duplicate column name")
    }
    names[column.name] = true
    columns.push(column)
  }
  let features_count = t.count(8)
  enforce(features_count, limits.max_features, "feature count")
  let node_size = t.short(9, fallback=16)
  if node_size == 1 || (node_size > 0 && features_count == 0) {
    raise InvalidData(t.position, "index needs count > 0 and node size >= 2")
  }
  let (envelope_at, envelope_count) = t.vector(1, 8, 8)
  let envelope = if envelope_count == 0 {
    None
  } else if envelope_count == 4 {
    let bounds : Bounds = {
      min_x: f64(payload, envelope_at),
      min_y: f64(payload, envelope_at + 8),
      max_x: f64(payload, envelope_at + 16),
      max_y: f64(payload, envelope_at + 24),
    }
    bounds.validate()
    Some(bounds)
  } else {
    raise Unsupported("only 2D envelopes are supported")
  }
  let crs_at = t.reference(10)
  {
    name: t.text(0, limits),
    geometry_kind: kind_from_code(t.byte(2)),
    columns,
    features_count,
    index_node_size: node_size,
    envelope,
    crs: if crs_at == 0 {
      None
    } else {
      Some(read_crs(payload, crs_at, limits))
    },
    title: t.text(11, limits),
    description: t.text(12, limits),
    metadata: t.text(13, limits),
  }
}

///|
fn write_column(b : FbBuilder, column : Column) -> Int32 {
  let table = b.table(11)
  b.text(table, 0, column.name)
  b.scalar(table, 1, column.type_code)
  if !column.title.is_empty() {
    b.text(table, 2, column.title)
  }
  if !column.description.is_empty() {
    b.text(table, 3, column.description)
  }
  b.scalar(table, 4, column.width)
  b.scalar(table, 5, column.precision)
  b.scalar(table, 6, column.scale)
  b.scalar(table, 7, if column.nullable { 1 } else { 0 })
  b.scalar(table, 8, if column.unique { 1 } else { 0 })
  b.scalar(table, 9, if column.primary_key { 1 } else { 0 })
  if !column.metadata.is_empty() {
    b.text(table, 10, column.metadata)
  }
  table
}

///|
fn write_crs(b : FbBuilder, crs : Crs) -> Int32 {
  let table = b.table(6)
  b.text(table, 0, crs.org)
  b.scalar(table, 1, crs.code)
  b.text(table, 2, crs.name)
  b.text(table, 3, crs.description)
  b.text(table, 4, crs.wkt)
  b.text(table, 5, crs.code_string)
  table
}

///|
pub fn encode_header(
  header : Header,
  limits~ : Limits = Limits::default(),
) -> Bytes raise FgbError {
  limits.validate()
  validate_header(header, limits~)
  let b = FbBuilder::new()
  let table = b.table(14)
  b.text(table, 0, header.name)
  match header.envelope {
    Some(bounds) => {
      let at = b.vector(4, 8)
      b.writer.double(bounds.min_x)
      b.writer.double(bounds.min_y)
      b.writer.double(bounds.max_x)
      b.writer.double(bounds.max_y)
      b.reference(table, 1, at)
    }
    None => ()
  }
  b.scalar(table, 2, header.geometry_kind.code())
  if !header.columns.is_empty() {
    let vector = b.vector(header.columns.length(), 4)
    b.writer.zeros(header.columns.length() * 4)
    for i in 0..<header.columns.length() {
      let child = write_column(b, header.columns[i])
      let slot = vector + 4 + i * 4
      b.writer.patch_word(slot, child - slot)
    }
    b.reference(table, 7, vector)
  }
  b.long(table, 8, header.features_count)
  b.scalar(table, 9, header.index_node_size)
  match header.crs {
    Some(crs) => b.reference(table, 10, write_crs(b, crs))
    None => ()
  }
  b.text(table, 11, header.title)
  b.text(table, 12, header.description)
  b.text(table, 13, header.metadata)
  let bytes = b.finish(table)
  enforce(bytes.length() - 4, limits.max_header_bytes, "header bytes")
  bytes
}

///|
pub fn validate_header(
  header : Header,
  limits~ : Limits = Limits::default(),
) -> Unit raise FgbError {
  if header.features_count < 0 ||
    header.index_node_size < 0 ||
    header.index_node_size > 65535 ||
    header.index_node_size == 1 {
    raise InvalidArgument("invalid feature count or index node size")
  }
  enforce(header.features_count, limits.max_features, "feature count")
  enforce(header.columns.length(), limits.max_columns, "column count")
  let seen : Map[String, Bool] = Map([])
  for column in header.columns {
    if column.name.is_empty() || seen.contains(column.name) {
      raise InvalidArgument("empty or duplicate column name")
    }
    if column.type_code < 0 || column.type_code > 14 {
      raise Unsupported("column type \{column.type_code}")
    }
    seen[column.name] = true
    enforce(
      @utf8.encode(column.name).length(),
      limits.max_string_bytes,
      "column name",
    )
  }
  match header.envelope {
    Some(bounds) => bounds.validate()
    None => ()
  }
  if header.index_node_size > 0 && header.features_count == 0 {
    raise InvalidArgument("indexed files require a known non-zero count")
  }
}
