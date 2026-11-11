///|
fn native_optional_text(
  t : TableView,
  field : Int32,
  limits : Limits,
) -> String? raise FgbError {
  if t.reference(field) == 0 {
    None
  } else {
    Some(t.text(field, limits))
  }
}

///|
fn native_put_text(
  b : FbBuilder,
  table : Int32,
  field : Int32,
  text : String?,
) -> Unit {
  match text {
    None => ()
    Some(text) => b.text(table, field, text)
  }
}

///|
fn native_check_text(text : String?, limits : Limits) -> Unit raise FgbError {
  match text {
    None => ()
    Some(text) =>
      enforce(
        @utf8.encode(text).length(),
        limits.max_string_bytes,
        "metadata string",
      )
  }
}

///|
fn native_check_columns(
  columns : Array[NativeColumn],
  limits : Limits,
) -> Unit raise FgbError {
  enforce(columns.length(), limits.max_columns, "column count")
  for column in columns {
    // Binary properties are keyed by column ordinal, not by name. Repeated
    // names can be retained here even though a JSON object cannot represent them.
    if column.type_code < 0 || column.type_code > 14 {
      raise Unsupported("column type \{column.type_code}")
    }
    native_check_text(Some(column.name), limits)
    for text in [column.title, column.description, column.metadata] {
      native_check_text(text, limits)
    }
  }
}

///|
fn native_read_column(
  data : Bytes,
  at : Int32,
  limits : Limits,
) -> NativeColumn raise FgbError {
  let t = TableView::open(data, at)
  if t.reference(0) == 0 {
    raise InvalidData(at, "missing required column name")
  }
  {
    name: t.text(0, limits),
    type_code: t.byte(1),
    title: native_optional_text(t, 2, limits),
    description: native_optional_text(t, 3, limits),
    width: t.int(4, fallback=-1),
    precision: t.int(5, fallback=-1),
    scale: t.int(6, fallback=-1),
    nullable: t.byte(7, fallback=1) != 0,
    unique: t.byte(8) != 0,
    primary_key: t.byte(9) != 0,
    metadata: native_optional_text(t, 10, limits),
  }
}

///|
fn native_read_columns(
  table : TableView,
  field : Int32,
  limits : Limits,
) -> Array[NativeColumn]? raise FgbError {
  if table.reference(field) == 0 {
    return None
  }
  let (at, count) = table.vector(field, 4, limits.max_columns)
  let columns : Array[NativeColumn] = []
  for i in 0..<count {
    columns.push(
      native_read_column(table.data, indirect(table.data, at + i * 4), limits),
    )
  }
  native_check_columns(columns, limits)
  Some(columns)
}

///|
fn native_write_columns(
  b : FbBuilder,
  parent : Int32,
  field : Int32,
  columns : Array[NativeColumn]?,
) -> Unit {
  match columns {
    None => ()
    Some(columns) => {
      let vector = b.vector(columns.length(), 4)
      b.writer.zeros(columns.length() * 4)
      for i in 0..<columns.length() {
        let column = columns[i]
        let table = b.table(11)
        b.text(table, 0, column.name)
        b.scalar(table, 1, column.type_code)
        native_put_text(b, table, 2, column.title)
        native_put_text(b, table, 3, column.description)
        b.scalar(table, 4, column.width)
        b.scalar(table, 5, column.precision)
        b.scalar(table, 6, column.scale)
        b.scalar(table, 7, if column.nullable { 1 } else { 0 })
        b.scalar(table, 8, if column.unique { 1 } else { 0 })
        b.scalar(table, 9, if column.primary_key { 1 } else { 0 })
        native_put_text(b, table, 10, column.metadata)
        let slot = vector + 4 + i * 4
        b.writer.patch_word(slot, table - slot)
      }
      b.reference(parent, field, vector)
    }
  }
}

///|
fn native_read_doubles(
  t : TableView,
  field : Int32,
  limit : Int32,
) -> Array[Double]? raise FgbError {
  if t.reference(field) == 0 {
    return None
  }
  let (at, count) = t.vector(field, 8, limit)
  Some(
    Array::makei(count, i => u64(t.data, at + i * 8).reinterpret_as_double()),
  )
}

///|
fn native_write_doubles(
  b : FbBuilder,
  table : Int32,
  field : Int32,
  values : Array[Double]?,
) -> Unit {
  match values {
    None => ()
    Some(values) => {
      let at = b.vector(values.length(), 8)
      for value in values {
        b.writer.double(value)
      }
      b.reference(table, field, at)
    }
  }
}

///|
pub fn NativeHeader::validate(
  self : NativeHeader,
  limits~ : Limits = Limits::default(),
) -> Unit raise FgbError {
  limits.validate()
  if self.features_count < 0 {
    raise InvalidArgument("negative feature count")
  }
  if self.geometry_type < 0 || self.geometry_type > 17 {
    raise Unsupported("geometry type \{self.geometry_type}")
  }
  enforce(self.features_count, limits.max_features, "feature count")
  if self.index_node_size < 0 ||
    self.index_node_size == 1 ||
    self.index_node_size > 65535 ||
    (self.index_node_size > 0 && self.features_count == 0) {
    raise InvalidArgument("invalid index node size or unknown indexed count")
  }
  for text in [self.name, self.title, self.description, self.metadata] {
    native_check_text(text, limits)
  }
  native_check_columns(self.columns.unwrap_or([]), limits)
  match self.crs {
    None => ()
    Some(crs) =>
      for text in [crs.org, crs.name, crs.description, crs.wkt, crs.code_string] {
        native_check_text(text, limits)
      }
  }
  match self.envelope {
    None => ()
    Some(values) => {
      if !values.is_empty() &&
        (
          values.length() < 4 ||
          values.length() > 12 ||
          values.length() % 2 != 0
        ) {
        raise InvalidArgument("invalid envelope dimension count")
      }
      for i in 0..<(values.length() / 2) {
        if !finite(values[i]) ||
          !finite(values[i + values.length() / 2]) ||
          values[i] > values[i + values.length() / 2] {
          raise InvalidArgument("invalid envelope bounds")
        }
      }
    }
  }
}

///|
pub fn decode_native_header(
  data : Bytes,
  limits~ : Limits = Limits::default(),
) -> NativeHeader raise FgbError {
  limits.validate()
  let payload = sized_payload(data, 0, limits.max_header_bytes)
  if payload.length() + 4 != data.length() {
    raise InvalidData(0, "trailing header data")
  }
  let t = TableView::root(payload)
  let count_at = t.field(8, 8)
  let count = if count_at == 0 { 0UL } else { u64(payload, count_at) }
  if count > limits.max_features.to_uint64() {
    raise LimitExceeded("feature count")
  }
  let crs_at = t.reference(10)
  let crs : NativeCrs? = if crs_at == 0 {
    None
  } else {
    let c = TableView::open(payload, crs_at)
    Some({
      org: native_optional_text(c, 0, limits),
      code: c.int(1),
      name: native_optional_text(c, 2, limits),
      description: native_optional_text(c, 3, limits),
      wkt: native_optional_text(c, 4, limits),
      code_string: native_optional_text(c, 5, limits),
    })
  }
  let result : NativeHeader = {
    name: native_optional_text(t, 0, limits),
    envelope: native_read_doubles(t, 1, 12),
    geometry_type: t.byte(2),
    has_z: t.byte(3) != 0,
    has_m: t.byte(4) != 0,
    has_t: t.byte(5) != 0,
    has_tm: t.byte(6) != 0,
    columns: native_read_columns(t, 7, limits),
    features_count: count.to_int(),
    index_node_size: t.short(9, fallback=16),
    crs,
    title: native_optional_text(t, 11, limits),
    description: native_optional_text(t, 12, limits),
    metadata: native_optional_text(t, 13, limits),
  }
  result.validate(limits~)
  result
}

///|
pub fn encode_native_header(
  header : NativeHeader,
  limits~ : Limits = Limits::default(),
) -> Bytes raise FgbError {
  header.validate(limits~)
  let b = FbBuilder::new()
  let table = b.table(14)
  native_put_text(b, table, 0, header.name)
  native_write_doubles(b, table, 1, header.envelope)
  b.scalar(table, 2, header.geometry_type)
  for
    (field, flag) in [
      (3, header.has_z),
      (4, header.has_m),
      (5, header.has_t),
      (6, header.has_tm),
    ] {
    b.scalar(table, field, if flag { 1 } else { 0 })
  }
  native_write_columns(b, table, 7, header.columns)
  b.long(table, 8, header.features_count)
  b.scalar(table, 9, header.index_node_size)
  match header.crs {
    None => ()
    Some(crs) => {
      let at = b.table(6)
      native_put_text(b, at, 0, crs.org)
      b.scalar(at, 1, crs.code)
      native_put_text(b, at, 2, crs.name)
      native_put_text(b, at, 3, crs.description)
      native_put_text(b, at, 4, crs.wkt)
      native_put_text(b, at, 5, crs.code_string)
      b.reference(table, 10, at)
    }
  }
  native_put_text(b, table, 11, header.title)
  native_put_text(b, table, 12, header.description)
  native_put_text(b, table, 13, header.metadata)
  let result = b.finish(table)
  enforce(result.length() - 4, limits.max_header_bytes, "header bytes")
  result
}
