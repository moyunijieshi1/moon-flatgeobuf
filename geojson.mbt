///|
fn json_field(value : Json, name : String) -> Json raise FgbError {
  guard value is Object(fields) else {
    raise InvalidArgument("expected JSON object")
  }
  match fields.get(name) {
    Some(result) => result
    None => raise InvalidArgument("missing JSON field \{name}")
  }
}

///|
fn json_array(value : Json) -> Array[Json] raise FgbError {
  guard value is Array(items) else {
    raise InvalidArgument("expected JSON array")
  }
  items
}

///|
fn json_text(value : Json) -> String raise FgbError {
  guard value is String(text) else {
    raise InvalidArgument("expected JSON string")
  }
  text
}

///|
fn json_number(value : Json) -> Double raise FgbError {
  guard value is Number(number, ..) else {
    raise InvalidArgument("expected JSON number")
  }
  if !finite(number) {
    raise InvalidArgument("non-finite JSON number")
  }
  number
}

///|
fn coordinate_json(coordinate : Coordinate) -> Json {
  Json::array([Json::number(coordinate.x), Json::number(coordinate.y)])
}

///|
fn coordinates_json(
  coordinates : Array[Coordinate],
  start : Int,
  end : Int,
) -> Json {
  let items : Array[Json] = []
  for i in start..<end {
    items.push(coordinate_json(coordinates[i]))
  }
  Json::array(items)
}

///|
fn parts_json(geometry : Geometry) -> Json {
  let items : Array[Json] = []
  let mut start = 0
  for end in part_ends(geometry) {
    items.push(coordinates_json(geometry.xy, start, end))
    start = end
  }
  Json::array(items)
}

///|
pub fn Geometry::to_geojson(self : Geometry) -> Json raise FgbError {
  self.validate()
  let coordinates = match self.kind {
    Point => coordinate_json(self.xy[0])
    LineString | MultiPoint => coordinates_json(self.xy, 0, self.xy.length())
    Polygon | MultiLineString => parts_json(self)
    MultiPolygon => Json::array(self.parts.map(part => parts_json(part)))
    Unknown => raise InvalidArgument("cannot export Unknown geometry")
  }
  Json::object(
    Map([("type", Json::string(self.kind.name())), ("coordinates", coordinates)]),
  )
}

///|
fn parse_coordinate(value : Json) -> Coordinate raise FgbError {
  let pair = json_array(value)
  if pair.length() != 2 {
    raise Unsupported("only 2D GeoJSON coordinate pairs are supported")
  }
  { x: json_number(pair[0]), y: json_number(pair[1]), }
}

///|
fn parse_coordinates(
  value : Json,
  limits : Limits,
  budget : Ref[Int],
) -> Array[Coordinate] raise FgbError {
  let values = json_array(value)
  budget.val = checked_add(budget.val, values.length())
  enforce(budget.val, limits.max_coordinates, "GeoJSON coordinates")
  let result : Array[Coordinate] = []
  for value in values {
    result.push(parse_coordinate(value))
  }
  result
}

///|
fn parse_parts(
  value : Json,
  kind : GeometryKind,
  limits : Limits,
  budget : Ref[Int],
) -> Geometry raise FgbError {
  let parts = json_array(value)
  enforce(parts.length(), limits.max_coordinates, "GeoJSON part count")
  let xy : Array[Coordinate] = []
  let ends : Array[Int] = []
  for part in parts {
    let coordinates = parse_coordinates(part, limits, budget)
    for coordinate in coordinates {
      xy.push(coordinate)
    }
    ends.push(xy.length())
  }
  { kind, xy, ends, parts: [], }
}

///|
pub fn geometry_from_geojson(
  value : Json,
  limits? : Limits = Limits::default(),
) -> Geometry raise FgbError {
  limits.validate()
  let kind = json_text(json_field(value, "type"))
  let coordinates = json_field(value, "coordinates")
  let budget = Ref(0)
  let geometry : Geometry = match kind {
    "Point" =>
      { kind: Point, xy: [parse_coordinate(coordinates)], ends: [], parts: [], }
    "LineString" =>
      {
        kind: LineString,
        xy: parse_coordinates(coordinates, limits, budget),
        ends: [],
        parts: [],
      }
    "MultiPoint" =>
      {
        kind: MultiPoint,
        xy: parse_coordinates(coordinates, limits, budget),
        ends: [],
        parts: [],
      }
    "Polygon" => parse_parts(coordinates, Polygon, limits, budget)
    "MultiLineString" =>
      parse_parts(coordinates, MultiLineString, limits, budget)
    "MultiPolygon" => {
      let values = json_array(coordinates)
      enforce(values.length(), limits.max_coordinates, "GeoJSON polygon count")
      let parts : Array[Geometry] = []
      for polygon in values {
        parts.push(parse_parts(polygon, Polygon, limits, budget))
      }
      { kind: MultiPolygon, xy: [], ends: [], parts, }
    }
    _ => raise Unsupported("GeoJSON geometry \{kind}")
  }
  geometry.validate(limits~)
  geometry
}

///|
pub fn Property::to_json_value(self : Property) -> Json {
  match self {
    Null => Json::null()
    Boolean(b) => Json::boolean(b)
    Integer(n) => Json::number(n.to_double(), repr=n.to_string())
    Unsigned(n) => Json::number(n.to_double(), repr=n.to_string())
    Real(n) => Json::number(n)
    Text(text) => Json::string(text)
    Binary(data) =>
      Json::array(
        Array::makei(data.length(), i => {
          Json::number(data[i].to_int().to_double())
        }),
      )
  }
}

///|
pub fn Feature::to_geojson(
  self : Feature,
  header : Header,
) -> Json raise FgbError {
  if self.properties.length() != header.columns.length() {
    raise InvalidArgument("feature property count differs from schema")
  }
  let properties : Map[String, Json] = Map([])
  for i in 0..<header.columns.length() {
    let column = header.columns[i]
    let value = if column.type_code == 12 {
      match self.properties[i] {
        Text(text) =>
          @json.parse(text) catch {
            _ => raise InvalidArgument("invalid JSON property")
          }
        Null => Json::null()
        _ => raise InvalidArgument("JSON column must contain text or null")
      }
    } else {
      self.properties[i].to_json_value()
    }
    properties[column.name] = value
  }
  Json::object(
    Map([
      ("type", Json::string("Feature")),
      (
        "geometry",
        match self.geometry {
          None => Json::null()
          Some(g) => g.to_geojson()
        },
      ),
      ("properties", Json::object(properties)),
    ]),
  )
}

///|
pub fn Dataset::to_geojson(
  self : Dataset,
  allow_projected? : Bool = false,
) -> Json raise FgbError {
  match self.header.crs {
    Some(crs) =>
      if !allow_projected &&
        (
          crs.code != 4326 ||
          (crs.org != "" && crs.org != "EPSG" && crs.org != "epsg")
        ) {
        raise InvalidArgument(
          "GeoJSON export requires EPSG:4326 or explicit allow_projected",
        )
      }
    None => ()
  }
  let features : Array[Json] = []
  for feature in self.features {
    features.push(feature.to_geojson(self.header))
  }
  Json::object(
    Map([
      ("type", Json::string("FeatureCollection")),
      ("features", Json::array(features)),
    ]),
  )
}

///|
fn property_from_json(
  value : Json,
  column : Column,
  limits : Limits,
) -> Property raise FgbError {
  if value == Json::null() {
    if !column.nullable {
      raise InvalidArgument("null non-nullable GeoJSON property \{column.name}")
    }
    return Null
  }
  let result : Property = match column.type_code {
    0 | 3 | 5 | 7 => {
      json_number(value) |> ignore
      let n : Int64 = @json.from_json(Json::string(value.stringify())) catch {
        _ =>
          raise InvalidArgument(
            "expected exact signed integer for \{column.name}",
          )
      }
      Integer(n)
    }
    1 | 4 | 6 | 8 => {
      json_number(value) |> ignore
      let n : UInt64 = @json.from_json(Json::string(value.stringify())) catch {
        _ =>
          raise InvalidArgument(
            "expected exact unsigned integer for \{column.name}",
          )
      }
      Unsigned(n)
    }
    2 => {
      guard value is True || value is False else {
        raise InvalidArgument("expected boolean for \{column.name}")
      }
      Boolean(value == Json::boolean(true))
    }
    9 | 10 => Real(json_number(value))
    11 | 13 => Text(json_text(value))
    12 => Text(value.stringify())
    14 => {
      let array = json_array(value)
      enforce(array.length(), limits.max_string_bytes, "GeoJSON binary bytes")
      let bytes : Array[Byte] = []
      for item in array {
        let number = json_number(item)
        if number < 0.0 ||
          number > 255.0 ||
          number != number.to_int().to_double() {
          raise InvalidArgument("binary JSON array needs unsigned bytes")
        }
        bytes.push(number.to_int().to_byte())
      }
      Binary(Bytes::makei(bytes.length(), i => bytes[i]))
    }
    _ => raise Unsupported("GeoJSON property type \{column.type_code}")
  }
  let writer = ByteWriter::new()
  write_property(writer, result, column.type_code, limits)
  result
}

///|
pub fn feature_from_geojson(
  value : Json,
  header : Header,
  limits? : Limits = Limits::default(),
) -> Feature raise FgbError {
  if json_text(json_field(value, "type")) != "Feature" {
    raise InvalidArgument("GeoJSON item must be Feature")
  }
  let geometry_json = json_field(value, "geometry")
  let geometry = if geometry_json == Json::null() {
    None
  } else {
    Some(geometry_from_geojson(geometry_json, limits~))
  }
  match geometry {
    Some(g) if header.geometry_kind != Unknown && header.geometry_kind != g.kind =>
      raise InvalidArgument("GeoJSON geometry differs from schema")
    _ => ()
  }
  let fields = match json_field(value, "properties") {
    Object(fields) => fields
    Null => Map([])
    _ => raise InvalidArgument("GeoJSON properties must be an object or null")
  }
  let properties : Array[Property] = []
  let names : Map[String, Bool] = Map([])
  for column in header.columns {
    names[column.name] = true
    let value = fields.get(column.name).unwrap_or(Json::null())
    properties.push(property_from_json(value, column, limits))
  }
  for name, _ in fields {
    if !names.contains(name) {
      raise InvalidArgument("GeoJSON property absent from schema: \{name}")
    }
  }
  { geometry, properties, }
}

///|
pub fn dataset_from_geojson(
  value : Json,
  header : Header,
  limits? : Limits = Limits::default(),
) -> Dataset raise FgbError {
  limits.validate()
  validate_header(header, limits~)
  if json_text(json_field(value, "type")) != "FeatureCollection" {
    raise InvalidArgument("expected GeoJSON FeatureCollection")
  }
  let values = json_array(json_field(value, "features"))
  enforce(values.length(), limits.max_features, "GeoJSON features")
  let features : Array[Feature] = []
  for item in values {
    features.push(feature_from_geojson(item, header, limits~))
  }
  { header, features, }
}
