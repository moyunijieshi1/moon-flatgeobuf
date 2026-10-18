///|
pub(all) struct DatasetSummary {
  features : Int32
  null_geometries : Int32
  coordinates : Int32
  envelope : Bounds?
  geometry_types : Array[(String, Int32)]
  columns : Array[ColumnSummary]
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub(all) struct ColumnSummary {
  name : String
  type_name : String
  nulls : Int32
  present : Int32
  minimum : String?
  maximum : String?
  total_bytes : Int32
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
fn compare_properties(
  left : Property,
  right : Property,
) -> Int32 raise FgbError {
  match (left, right) {
    (Integer(a), Integer(b)) => a.compare(b)
    (Unsigned(a), Unsigned(b)) => a.compare(b)
    (Real(a), Real(b)) => a.compare(b)
    (Text(a), Text(b)) => a.compare(b)
    (Boolean(a), Boolean(b)) =>
      (if a { 1 } else { 0 }).compare(if b { 1 } else { 0 })
    _ => raise InvalidArgument("incomparable property types")
  }
}

///|
fn property_text(value : Property) -> String? {
  match value {
    Integer(n) => Some(n.to_string())
    Unsigned(n) => Some(n.to_string())
    Real(n) => Some(n.to_string())
    Boolean(n) => Some(n.to_string())
    Text(n) => Some(n)
    Null | Binary(_) => None
  }
}

///|
pub fn Dataset::summarize(
  self : Dataset,
  limits~ : Limits = Limits::default(),
) -> DatasetSummary raise FgbError {
  limits.validate()
  validate_header(self.header, limits~)
  enforce(self.features.length(), limits.max_features, "summary feature count")
  let types : Map[String, Int32] = Map([])
  let mut null_geometries = 0
  let mut coordinates = 0
  let nulls = Array::make(self.header.columns.length(), 0)
  let present = Array::make(self.header.columns.length(), 0)
  let minimum : Array[Property?] = Array::make(
    self.header.columns.length(),
    None,
  )
  let maximum : Array[Property?] = Array::make(
    self.header.columns.length(),
    None,
  )
  let byte_counts = Array::make(self.header.columns.length(), 0)
  for feature in self.features {
    match feature.geometry {
      None => null_geometries += 1
      Some(g) => {
        g.validate(limits~)
        coordinates = checked_add(coordinates, g.coordinate_count())
        let name = g.kind.name()
        types[name] = types.get(name).unwrap_or(0) + 1
      }
    }
    if feature.properties.length() != self.header.columns.length() {
      raise InvalidArgument("summary property count differs from schema")
    }
    for i in 0..<feature.properties.length() {
      let value = feature.properties[i]
      if value == Null {
        nulls[i] += 1
        continue
      }
      present[i] += 1
      let writer = ByteWriter::new()
      write_property(writer, value, self.header.columns[i].type_code, limits)
      let (value, _) = read_property(
        writer.finish(),
        0,
        self.header.columns[i].type_code,
        limits,
      )
      byte_counts[i] = checked_add(byte_counts[i], writer.position())
      if value is Binary(_) {
        continue
      }
      match minimum[i] {
        None => minimum[i] = Some(value)
        Some(old) if compare_properties(value, old) < 0 =>
          minimum[i] = Some(value)
        _ => ()
      }
      match maximum[i] {
        None => maximum[i] = Some(value)
        Some(old) if compare_properties(value, old) > 0 =>
          maximum[i] = Some(value)
        _ => ()
      }
    }
  }
  let columns : Array[ColumnSummary] = []
  for i in 0..<self.header.columns.length() {
    let column = self.header.columns[i]
    columns.push({
      name: column.name,
      type_name: column.type_name(),
      nulls: nulls[i],
      present: present[i],
      minimum: match minimum[i] {
        None => None
        Some(value) => property_text(value)
      },
      maximum: match maximum[i] {
        None => None
        Some(value) => property_text(value)
      },
      total_bytes: byte_counts[i],
    })
  }
  let type_counts = types.to_array()
  type_counts.sort_by((a, b) => a.0.compare(b.0))
  {
    features: self.features.length(),
    null_geometries,
    coordinates,
    envelope: dataset_bounds(self.features),
    geometry_types: type_counts,
    columns,
  }
}

///|
pub(all) struct ArchiveSummary {
  file_bytes : Int32
  header_bytes : Int32
  index_bytes : Int32
  feature_bytes : Int32
  minimum_record_bytes : Int32
  maximum_record_bytes : Int32
  dataset : DatasetSummary
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub fn inspect_archive(
  data : Bytes,
  limits~ : Limits = Limits::default(),
) -> ArchiveSummary raise FgbError {
  let reader = Reader::open(data, limits~)
  let dataset = reader.read_all()
  reader.rewind()
  let mut minimum = 0
  let mut maximum = 0
  while reader.next() is Some(record) {
    if minimum == 0 || record.byte_length < minimum {
      minimum = record.byte_length
    }
    if record.byte_length > maximum {
      maximum = record.byte_length
    }
  }
  {
    file_bytes: data.length(),
    header_bytes: reader.index_start - 8,
    index_bytes: reader.index_size,
    feature_bytes: data.length() - reader.features_start,
    minimum_record_bytes: minimum,
    maximum_record_bytes: maximum,
    dataset: dataset.summarize(limits~),
  }
}
