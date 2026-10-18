///|
fn inferred_type(value : Json) -> Int raise FgbError {
  match value {
    Null => -1
    True | False => 2
    String(_) => 11
    Array(_) | Object(_) => 12
    Number(n, ..) => {
      if !finite(n) {
        raise InvalidArgument("non-finite property")
      }
      let signed : Int64? = try { Some(@json.from_json(Json::string(value.stringify()))) } catch { _ => None }
      if signed is Some(_) { return 7 }
      let unsigned : UInt64? = try { Some(@json.from_json(Json::string(value.stringify()))) } catch { _ => None }
      if unsigned is Some(_) { return 8 }
      if n >= -9007199254740991.0 && n <= 9007199254740991.0 && n == n.to_int64().to_double() {
        return 7
      }
      if n == @math.floor(n) && (n < -9007199254740991.0 || n > 9007199254740991.0) {
        raise InvalidArgument("large integer cannot be inferred without a precise 64-bit representation")
      }
      10
    }
  }
}

///|
fn unify_types(left : Int, right : Int) -> Int raise FgbError {
  if left == -1 { return right }
  if right == -1 || left == right { return left }
  if (left == 7 && right == 10) || (left == 10 && right == 7) {
    return 10
  }
  // Signed/unsigned mixtures require an explicit schema to avoid precision loss.
  raise InvalidArgument("inconsistent GeoJSON property types; provide an explicit schema")
}

///|
pub fn infer_geojson_header(value : Json, name? : String = "", limits? : Limits = Limits::default()) -> Header raise FgbError {
  limits.validate()
  if json_text(json_field(value, "type")) != "FeatureCollection" {
    raise InvalidArgument("expected FeatureCollection")
  }
  let features = json_array(json_field(value, "features"))
  enforce(features.length(), limits.max_features, "GeoJSON features")
  let types : Map[String, Int] = Map([])
  let present : Map[String, Int] = Map([])
  let nullable : Map[String, Bool] = Map([])
  let mut geometry_kind = Unknown
  let mut geometry_seen = false
  let mut mixed = false
  for feature in features {
    if json_text(json_field(feature, "type")) != "Feature" {
      raise InvalidArgument("expected Feature in collection")
    }
    let geometry = json_field(feature, "geometry")
    if geometry != Json::null() {
      let kind = match json_text(json_field(geometry, "type")) {
        "Point" => Point
        "LineString" => LineString
        "Polygon" => Polygon
        "MultiPoint" => MultiPoint
        "MultiLineString" => MultiLineString
        "MultiPolygon" => MultiPolygon
        other => raise Unsupported("GeoJSON geometry \{other}")
      }
      if geometry_seen && geometry_kind != kind { mixed = true }
      geometry_kind = kind
      geometry_seen = true
    }
    let fields = match json_field(feature, "properties") {
      Object(fields) => fields
      Null => Map([])
      _ => raise InvalidArgument("properties must be an object or null")
    }
    for key, value in fields {
      if key.is_empty() {
        raise InvalidArgument("empty property name")
      }
      let old = types.get(key).unwrap_or(-1)
      types[key] = unify_types(old, inferred_type(value))
      present[key] = present.get(key).unwrap_or(0) + 1
      if value == Json::null() { nullable[key] = true }
    }
    enforce(types.length(), limits.max_columns, "inferred columns")
  }
  let names : Array[String] = []
  for key, _ in types { names.push(key) }
  names.sort()
  let columns : Array[Column] = []
  for key in names {
    let type_code = types.get(key).unwrap_or(-1)
    columns.push(Column::new(
      key, if type_code < 0 { 11 } else { type_code },
      nullable=nullable.get(key).unwrap_or(false) || present.get(key).unwrap_or(0) != features.length(),
    ))
  }
  {
    ..Header::new(if mixed { Unknown } else { geometry_kind }, columns),
    name, crs: Some(Crs::epsg(4326)),
  }
}

///|
pub fn import_geojson(value : Json, name? : String = "", limits? : Limits = Limits::default()) -> Dataset raise FgbError {
  let header = infer_geojson_header(value, name=name, limits=limits)
  dataset_from_geojson(value, header, limits=limits)
}

///|
pub(all) struct SchemaDifference {
  column : String
  message : String
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub fn compare_schemas(left : Header, right : Header) -> Array[SchemaDifference] {
  let result : Array[SchemaDifference] = []
  if left.geometry_kind != right.geometry_kind {
    result.push({ column: "geometry", message: "geometry types differ" })
  }
  let left_columns : Map[String, Column] = Map([])
  let right_columns : Map[String, Column] = Map([])
  for column in left.columns { left_columns[column.name] = column }
  for column in right.columns { right_columns[column.name] = column }
  for column in left.columns {
    match right_columns.get(column.name) {
      None => result.push({ column: column.name, message: "missing in right schema" })
      Some(other) => {
        if column.type_code != other.type_code {
          result.push({ column: column.name, message: "column types differ" })
        }
        if column.nullable && !other.nullable {
          result.push({ column: column.name, message: "right schema forbids existing null values" })
        }
      }
    }
  }
  for column in right.columns {
    if !left_columns.contains(column.name) {
      result.push({ column: column.name, message: "new in right schema" })
    }
  }
  result
}
