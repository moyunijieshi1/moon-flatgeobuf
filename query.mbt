///|
pub(all) enum Predicate {
  Equal(String, Property)
  NotEqual(String, Property)
  IsNull(String)
  IsNotNull(String)
  NumericRange(String, Double?, Double?)
  /// Inclusive signed-integer bounds without floating-point conversion.
  Int64Range(String, Int64?, Int64?)
  /// Inclusive unsigned-integer bounds without floating-point conversion.
  UInt64Range(String, UInt64?, UInt64?)
  TextContains(String, String)
  All(Array[Predicate])
  Any(Array[Predicate])
  Not(Predicate)
} derive(Eq, Debug)

///|
fn column_index(header : Header, name : String) -> Int32 raise FgbError {
  for i in 0..<header.columns.length() {
    if header.columns[i].name == name {
      return i
    }
  }
  raise InvalidArgument("unknown column \{name}")
}

///|
priv enum BoundPredicate {
  BoundEqual(Int32, Property)
  BoundNotEqual(Int32, Property)
  BoundIsNull(Int32)
  BoundIsNotNull(Int32)
  BoundNumericRange(Int32, Double?, Double?)
  BoundInt64Range(Int32, Int64?, Int64?)
  BoundUInt64Range(Int32, UInt64?, UInt64?)
  BoundTextContains(Int32, String)
  BoundAll(Array[BoundPredicate])
  BoundAny(Array[BoundPredicate])
  BoundNot(BoundPredicate)
}

///|
fn bind_predicate(
  predicate : Predicate,
  header : Header,
  depth : Int32,
  limits : Limits,
) -> BoundPredicate raise FgbError {
  enforce(depth, limits.max_depth, "predicate depth")
  match predicate {
    Equal(name, value) => BoundEqual(column_index(header, name), value)
    NotEqual(name, value) => BoundNotEqual(column_index(header, name), value)
    IsNull(name) => BoundIsNull(column_index(header, name))
    IsNotNull(name) => BoundIsNotNull(column_index(header, name))
    TextContains(name, text) => {
      let index = column_index(header, name)
      let column = header.columns[index]
      if column.type_code < 11 || column.type_code > 13 {
        raise InvalidArgument("TextContains requires a text column")
      }
      BoundTextContains(index, text)
    }
    NumericRange(name, low, high) => {
      let index = column_index(header, name)
      let column = header.columns[index]
      if column.type_code > 10 || column.type_code == 2 {
        raise InvalidArgument("NumericRange requires a numeric column")
      }
      match low {
        Some(n) if !finite(n) => raise InvalidArgument("non-finite minimum")
        _ => ()
      }
      match high {
        Some(n) if !finite(n) => raise InvalidArgument("non-finite maximum")
        _ => ()
      }
      match (low, high) {
        (Some(a), Some(b)) if a > b =>
          raise InvalidArgument("range minimum exceeds maximum")
        _ => ()
      }
      if column.type_code == 7 || column.type_code == 8 {
        raise Unsupported(
          "NumericRange on 64-bit integers; use Int64Range or UInt64Range",
        )
      }
      BoundNumericRange(index, low, high)
    }
    Int64Range(name, low, high) => {
      let index = column_index(header, name)
      match header.columns[index].type_code {
        0 | 3 | 5 | 7 => ()
        _ =>
          raise InvalidArgument("Int64Range requires a signed integer column")
      }
      match (low, high) {
        (Some(a), Some(b)) if a > b =>
          raise InvalidArgument("range minimum exceeds maximum")
        _ => ()
      }
      BoundInt64Range(index, low, high)
    }
    UInt64Range(name, low, high) => {
      let index = column_index(header, name)
      match header.columns[index].type_code {
        1 | 4 | 6 | 8 => ()
        _ =>
          raise InvalidArgument(
            "UInt64Range requires an unsigned integer column",
          )
      }
      match (low, high) {
        (Some(a), Some(b)) if a > b =>
          raise InvalidArgument("range minimum exceeds maximum")
        _ => ()
      }
      BoundUInt64Range(index, low, high)
    }
    All(items) | Any(items) => {
      enforce(items.length(), limits.max_columns, "predicate count")
      let bound = items.map(item => {
        bind_predicate(item, header, depth + 1, limits)
      })
      match predicate {
        All(_) => BoundAll(bound)
        _ => BoundAny(bound)
      }
    }
    Not(item) => BoundNot(bind_predicate(item, header, depth + 1, limits))
  }
}

///|
fn matches_predicate(
  feature : Feature,
  predicate : BoundPredicate,
) -> Bool raise FgbError {
  match predicate {
    BoundEqual(index, expected) => feature.properties[index] == expected
    BoundNotEqual(index, expected) => feature.properties[index] != expected
    BoundIsNull(index) => feature.properties[index] == Null
    BoundIsNotNull(index) => feature.properties[index] != Null
    BoundTextContains(index, text) =>
      match feature.properties[index] {
        Text(value) => value.contains(text)
        _ => false
      }
    BoundNumericRange(index, minimum, maximum) => {
      let value = feature.properties[index]
      if value == Null {
        return false
      }
      let number = real_value(value)
      let low = match minimum {
        None => true
        Some(n) => number >= n
      }
      let high = match maximum {
        None => true
        Some(n) => number <= n
      }
      low && high
    }
    BoundInt64Range(index, minimum, maximum) => {
      guard feature.properties[index] is Integer(value) else { return false }
      let low = match minimum {
        None => true
        Some(n) => value >= n
      }
      let high = match maximum {
        None => true
        Some(n) => value <= n
      }
      low && high
    }
    BoundUInt64Range(index, minimum, maximum) => {
      guard feature.properties[index] is Unsigned(value) else { return false }
      let low = match minimum {
        None => true
        Some(n) => value >= n
      }
      let high = match maximum {
        None => true
        Some(n) => value <= n
      }
      low && high
    }
    BoundAll(items) => {
      for item in items {
        if !matches_predicate(feature, item) {
          return false
        }
      }
      true
    }
    BoundAny(items) => {
      for item in items {
        if matches_predicate(feature, item) {
          return true
        }
      }
      false
    }
    BoundNot(item) => !matches_predicate(feature, item)
  }
}

///|
pub(all) struct Selection {
  bounds : Bounds?
  predicate : Predicate?
  fields : Array[String]?
  offset : Int32
  limit : Int32
} derive(Eq, Debug)

///|
pub fn Selection::all() -> Selection {
  { bounds: None, predicate: None, fields: None, offset: 0, limit: 1000000, }
}

///|
fn resolve_projection(
  header : Header,
  fields : Array[String],
) -> (Array[Int32], Array[Column]) raise FgbError {
  let seen : Map[String, Bool] = Map([])
  let indexes : Array[Int32] = []
  let columns : Array[Column] = []
  for name in fields {
    if seen.contains(name) {
      raise InvalidArgument("duplicate projected field")
    }
    seen[name] = true
    let i = column_index(header, name)
    indexes.push(i)
    columns.push(header.columns[i])
  }
  (indexes, columns)
}

///|
pub fn Dataset::project(
  self : Dataset,
  fields : Array[String],
) -> Dataset raise FgbError {
  let (indexes, columns) = resolve_projection(self.header, fields)
  let features : Array[Feature] = []
  for feature in self.features {
    if feature.properties.length() != self.header.columns.length() {
      raise InvalidArgument("feature property count differs from header")
    }
    features.push({
      geometry: feature.geometry,
      properties: indexes.map(i => feature.properties[i]),
    })
  }
  { header: { ..self.header, columns, }, features, }
}

///|
/// Select a page in file order without decoding later records once the page
/// is full. This preserves the caller's cursor and is not a full-file audit.
pub fn Reader::select(
  self : Reader,
  selection : Selection,
) -> Dataset raise FgbError {
  if selection.offset < 0 || selection.limit < 0 {
    raise InvalidArgument("pagination values must not be negative")
  }
  let predicate = match selection.predicate {
    None => None
    Some(predicate) =>
      Some(bind_predicate(predicate, self.header_, 1, self.limits))
  }
  match selection.bounds {
    Some(bounds) => bounds.validate()
    None => ()
  }
  // Resolve fields even for a zero-length page, before touching feature data.
  let projection = match selection.fields {
    None => None
    Some(fields) => Some(resolve_projection(self.header_, fields))
  }
  let indexed = match selection.bounds {
    Some(bounds) if self.has_index() && selection.limit > 0 =>
      Some(
        IndexCursor::new(
          slice_bytes(self.data, self.index_start, self.index_size),
          self.header_.features_count,
          self.header_.index_node_size,
          bounds,
          self.limits,
        ),
      )
    _ => None
  }
  let scan : Reader = { ..self, cursor: self.features_start, ordinal: 0, }
  let features : Array[Feature] = []
  let mut skipped = 0
  while features.length() < selection.limit {
    let record = match indexed {
      Some(cursor) =>
        match cursor.next() {
          None => break
          Some(hit) => self.record(hit.offset, hit.ordinal)
        }
      None =>
        match scan.next() {
          None => break
          Some(record) => record
        }
    }
    match selection.bounds {
      Some(bounds) =>
        match record.feature.bounds() {
          Some(actual) if actual.intersects(bounds) => ()
          _ => continue
        }
      None => ()
    }
    let accepted = match predicate {
      None => true
      Some(predicate) => matches_predicate(record.feature, predicate)
    }
    if !accepted {
      continue
    }
    if skipped < selection.offset {
      skipped += 1
      continue
    }
    features.push(
      match projection {
        None => record.feature
        Some((indexes, _)) =>
          {
            geometry: record.feature.geometry,
            properties: indexes.map(i => record.feature.properties[i]),
          }
      },
    )
  }
  {
    header: {
      ..self.header_,
      columns: match projection {
        None => self.header_.columns
        Some((_, columns)) => columns
      },
      index_node_size: 0,
      features_count: features.length(),
      envelope: dataset_bounds(features),
    },
    features,
  }
}
