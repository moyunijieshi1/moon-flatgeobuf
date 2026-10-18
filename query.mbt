///|
pub(all) enum Predicate {
  Equal(String, Property)
  NotEqual(String, Property)
  IsNull(String)
  IsNotNull(String)
  NumericRange(String, Double?, Double?)
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
fn validate_predicate(
  predicate : Predicate,
  header : Header,
  depth : Int32,
  limits : Limits,
) -> Unit raise FgbError {
  enforce(depth, limits.max_depth, "predicate depth")
  match predicate {
    Equal(name, _) | NotEqual(name, _) | IsNull(name) | IsNotNull(name) =>
      column_index(header, name) |> ignore
    TextContains(name, _) => {
      let column = header.columns[column_index(header, name)]
      if column.type_code < 11 || column.type_code > 13 {
        raise InvalidArgument("TextContains requires a text column")
      }
    }
    NumericRange(name, low, high) => {
      let column = header.columns[column_index(header, name)]
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
          "NumericRange on 64-bit integers; use exact equality or an application predicate",
        )
      }
    }
    All(items) | Any(items) => {
      enforce(items.length(), limits.max_columns, "predicate count")
      for item in items {
        validate_predicate(item, header, depth + 1, limits)
      }
    }
    Not(item) => validate_predicate(item, header, depth + 1, limits)
  }
}

///|
fn matches_predicate(
  feature : Feature,
  header : Header,
  predicate : Predicate,
) -> Bool raise FgbError {
  match predicate {
    Equal(name, expected) =>
      feature.properties[column_index(header, name)] == expected
    NotEqual(name, expected) =>
      feature.properties[column_index(header, name)] != expected
    IsNull(name) => feature.properties[column_index(header, name)] == Null
    IsNotNull(name) => feature.properties[column_index(header, name)] != Null
    TextContains(name, text) =>
      match feature.properties[column_index(header, name)] {
        Text(value) => value.contains(text)
        _ => false
      }
    NumericRange(name, minimum, maximum) => {
      let value = feature.properties[column_index(header, name)]
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
    All(items) => {
      for item in items {
        if !matches_predicate(feature, header, item) {
          return false
        }
      }
      true
    }
    Any(items) => {
      for item in items {
        if matches_predicate(feature, header, item) {
          return true
        }
      }
      false
    }
    Not(item) => !matches_predicate(feature, header, item)
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
pub fn Dataset::project(
  self : Dataset,
  fields : Array[String],
) -> Dataset raise FgbError {
  let seen : Map[String, Bool] = Map([])
  let indexes : Array[Int32] = []
  let columns : Array[Column] = []
  for name in fields {
    if seen.contains(name) {
      raise InvalidArgument("duplicate projected field")
    }
    seen[name] = true
    let i = column_index(self.header, name)
    indexes.push(i)
    columns.push(self.header.columns[i])
  }
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
pub fn Reader::select(
  self : Reader,
  selection : Selection,
) -> Dataset raise FgbError {
  if selection.offset < 0 || selection.limit < 0 {
    raise InvalidArgument("pagination values must not be negative")
  }
  match selection.predicate {
    None => ()
    Some(predicate) =>
      validate_predicate(predicate, self.header_, 1, self.limits)
  }
  let records = match selection.bounds {
    Some(bounds) => self.query(bounds)
    None => {
      self.rewind()
      let records : Array[FeatureRecord] = []
      while self.next() is Some(record) {
        records.push(record)
      }
      records
    }
  }
  let features : Array[Feature] = []
  let mut skipped = 0
  for record in records {
    if features.length() >= selection.limit {
      break
    }
    let accepted = match selection.predicate {
      None => true
      Some(predicate) =>
        matches_predicate(record.feature, self.header_, predicate)
    }
    if !accepted {
      continue
    }
    if skipped < selection.offset {
      skipped += 1
      continue
    }
    features.push(record.feature)
  }
  let dataset : Dataset = {
    header: {
      ..self.header_,
      index_node_size: 0,
      features_count: features.length(),
      envelope: dataset_bounds(features),
    },
    features,
  }
  match selection.fields {
    Some(fields) => dataset.project(fields)
    None => dataset
  }
}
