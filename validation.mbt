///|
pub(all) struct Diagnostic {
  severity : String
  code : String
  message : String
  feature : Int32?
  column : String?
  byte_offset : Int32?
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub(all) struct ValidationReport {
  valid : Bool
  checked_features : Int32
  diagnostics : Array[Diagnostic]
  truncated : Bool
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
fn diagnostic_from_error(error : FgbError, feature : Int32?) -> Diagnostic {
  match error {
    InvalidData(offset, message) =>
      {
        severity: "error",
        code: "invalid_data",
        message,
        feature,
        column: None,
        byte_offset: Some(offset),
      }
    Unsupported(message) =>
      {
        severity: "error",
        code: "unsupported",
        message,
        feature,
        column: None,
        byte_offset: None,
      }
    LimitExceeded(message) =>
      {
        severity: "error",
        code: "limit_exceeded",
        message,
        feature,
        column: None,
        byte_offset: None,
      }
    InvalidArgument(message) =>
      {
        severity: "error",
        code: "invalid_argument",
        message,
        feature,
        column: None,
        byte_offset: None,
      }
  }
}

///|
pub fn Dataset::validate(
  self : Dataset,
  limits~ : Limits = Limits::default(),
  max_diagnostics~ : Int32 = 100,
) -> ValidationReport raise FgbError {
  limits.validate()
  if max_diagnostics < 1 || max_diagnostics > 10000 {
    raise InvalidArgument("diagnostic limit must be between 1 and 10000")
  }
  let diagnostics : Array[Diagnostic] = []
  validate_header(self.header, limits~) catch {
    error => diagnostics.push(diagnostic_from_error(error, None))
  }
  if self.header.features_count > 0 &&
    self.header.features_count != self.features.length() {
    diagnostics.push({
      severity: "error",
      code: "count_mismatch",
      message: "header count differs from dataset length",
      feature: None,
      column: None,
      byte_offset: None,
    })
  }
  enforce(self.features.length(), limits.max_features, "validation features")
  let unique_values : Array[Map[String, Bool]] = Array::makei(
    self.header.columns.length(),
    _ => Map([]),
  )
  let mut checked_features = 0
  let mut truncated = false
  for ordinal in 0..<self.features.length() {
    if diagnostics.length() >= max_diagnostics {
      truncated = true
      break
    }
    let feature = self.features[ordinal]
    checked_features += 1
    try {
      match feature.geometry {
        None =>
          if self.header.index_node_size > 0 {
            raise InvalidArgument(
              "indexed dataset cannot contain a null geometry",
            )
          }
        Some(geometry) => {
          geometry.validate(limits~)
          if self.header.geometry_kind != Unknown &&
            self.header.geometry_kind != geometry.kind {
            raise InvalidArgument(
              "geometry conflicts with declared dataset type",
            )
          }
          match (self.header.envelope, geometry.bounds()) {
            (Some(envelope), Some(bounds)) if !envelope.contains(bounds) =>
              raise InvalidArgument("geometry lies outside declared envelope")
            _ => ()
          }
        }
      }
      encode_properties(feature.properties, self.header.columns, limits~)
      |> ignore
    } catch {
      error => {
        diagnostics.push(diagnostic_from_error(error, Some(ordinal)))
        continue
      }
    }
    for column_index in 0..<self.header.columns.length() {
      if diagnostics.length() >= max_diagnostics {
        truncated = true
        break
      }
      let column = self.header.columns[column_index]
      let value = feature.properties[column_index]
      if column.primary_key && value == Null {
        diagnostics.push({
          severity: "error",
          code: "null_primary_key",
          message: "primary key is null",
          feature: Some(ordinal),
          column: Some(column.name),
          byte_offset: None,
        })
      }
      if (column.unique || column.primary_key) && value != Null {
        let writer = ByteWriter::new()
        write_property(writer, value, column.type_code, limits)
        let bytes = writer.finish()
        let key = bytes.to_string()
        if unique_values[column_index].contains(key) {
          diagnostics.push({
            severity: "error",
            code: "duplicate_unique_value",
            message: "duplicate value in unique column",
            feature: Some(ordinal),
            column: Some(column.name),
            byte_offset: None,
          })
        } else {
          unique_values[column_index][key] = true
        }
      }
    }
  }
  {
    valid: diagnostics.is_empty() && !truncated,
    checked_features,
    diagnostics,
    truncated,
  }
}

///|
pub fn audit_archive(
  data : Bytes,
  limits~ : Limits = Limits::default(),
) -> ValidationReport {
  try {
    let reader = Reader::open(data, limits~)
    reader.validate()
    reader.read_all().validate(limits~)
  } catch {
    error =>
      {
        valid: false,
        checked_features: 0,
        diagnostics: [diagnostic_from_error(error, None)],
        truncated: false,
      }
  }
}

///|
pub fn Header::column(self : Header, name : String) -> Column? {
  for column in self.columns {
    if column.name == name {
      return Some(column)
    }
  }
  None
}

///|
pub fn Header::is_wgs84(self : Header) -> Bool {
  match self.crs {
    None => false
    Some(crs) =>
      crs.code == 4326 &&
      (crs.org == "" || crs.org == "EPSG" || crs.org == "epsg")
  }
}

///|
pub fn Header::validate_geojson_crs(
  self : Header,
  assume_wgs84~ : Bool = false,
) -> Unit raise FgbError {
  if self.is_wgs84() {
    return
  }
  if self.crs is None && assume_wgs84 {
    return
  }
  raise InvalidArgument(
    "GeoJSON needs WGS84 coordinates; missing or projected CRS requires explicit handling",
  )
}

///|
pub fn Geometry::validate_wgs84(
  self : Geometry,
  limits~ : Limits = Limits::default(),
) -> Unit raise FgbError {
  self.validate(limits~)
  fn check(geometry : Geometry) -> Unit raise FgbError {
    for coordinate in geometry.xy {
      if coordinate.x < -180.0 ||
        coordinate.x > 180.0 ||
        coordinate.y < -90.0 ||
        coordinate.y > 90.0 {
        raise InvalidArgument(
          "coordinate outside WGS84 longitude/latitude range",
        )
      }
    }
    for part in geometry.parts {
      check(part)
    }
  }
  check(self)
}
