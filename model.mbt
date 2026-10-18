///|
pub(all) struct Bounds {
  min_x : Double
  min_y : Double
  max_x : Double
  max_y : Double
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub fn Bounds::validate(self : Bounds) -> Unit raise FgbError {
  if !finite(self.min_x) || !finite(self.min_y) ||
    !finite(self.max_x) || !finite(self.max_y) {
    raise InvalidArgument("bounds must be finite")
  }
  if self.min_x > self.max_x || self.min_y > self.max_y {
    raise InvalidArgument("bounds minimum exceeds maximum")
  }
}

///|
pub fn Bounds::intersects(self : Bounds, other : Bounds) -> Bool {
  self.min_x <= other.max_x && self.max_x >= other.min_x &&
  self.min_y <= other.max_y && self.max_y >= other.min_y
}

///|
pub fn Bounds::contains(self : Bounds, other : Bounds) -> Bool {
  self.min_x <= other.min_x && self.min_y <= other.min_y &&
  self.max_x >= other.max_x && self.max_y >= other.max_y
}

///|
pub fn Bounds::union(self : Bounds, other : Bounds) -> Bounds {
  {
    min_x: @math.minimum(self.min_x, other.min_x),
    min_y: @math.minimum(self.min_y, other.min_y),
    max_x: @math.maximum(self.max_x, other.max_x),
    max_y: @math.maximum(self.max_y, other.max_y),
  }
}

///|
pub(all) struct Coordinate {
  x : Double
  y : Double
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub(all) enum GeometryKind {
  Unknown
  Point
  LineString
  Polygon
  MultiPoint
  MultiLineString
  MultiPolygon
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub fn GeometryKind::code(self : GeometryKind) -> Int {
  match self {
    Unknown => 0
    Point => 1
    LineString => 2
    Polygon => 3
    MultiPoint => 4
    MultiLineString => 5
    MultiPolygon => 6
  }
}

///|
pub fn GeometryKind::name(self : GeometryKind) -> String {
  match self {
    Unknown => "Unknown"
    Point => "Point"
    LineString => "LineString"
    Polygon => "Polygon"
    MultiPoint => "MultiPoint"
    MultiLineString => "MultiLineString"
    MultiPolygon => "MultiPolygon"
  }
}

///|
fn kind_from_code(code : Int) -> GeometryKind raise FgbError {
  match code {
    0 => Unknown
    1 => Point
    2 => LineString
    3 => Polygon
    4 => MultiPoint
    5 => MultiLineString
    6 => MultiPolygon
    _ => raise Unsupported("geometry type \{code}")
  }
}

///|
pub(all) struct Geometry {
  kind : GeometryKind
  xy : Array[Coordinate]
  ends : Array[Int]
  parts : Array[Geometry]
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub fn Geometry::point(x : Double, y : Double) -> Geometry {
  { kind: Point, xy: [{ x, y }], ends: [], parts: [] }
}

///|
pub(all) struct Column {
  name : String
  type_code : Int
  nullable : Bool
  title : String
  description : String
  width : Int
  precision : Int
  scale : Int
  unique : Bool
  primary_key : Bool
  metadata : String
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub fn Column::new(name : String, type_code : Int, nullable? : Bool = true) -> Column {
  {
    name, type_code, nullable,
    title: "", description: "", width: -1, precision: -1, scale: -1,
    unique: false, primary_key: false, metadata: "",
  }
}

///|
pub fn Column::type_name(self : Column) -> String {
  match self.type_code {
    0 => "Byte"
    1 => "UByte"
    2 => "Bool"
    3 => "Short"
    4 => "UShort"
    5 => "Int"
    6 => "UInt"
    7 => "Long"
    8 => "ULong"
    9 => "Float"
    10 => "Double"
    11 => "String"
    12 => "Json"
    13 => "DateTime"
    14 => "Binary"
    _ => "Unsupported"
  }
}

///|
pub(all) enum Property {
  Null
  Integer(Int64)
  Unsigned(UInt64)
  Real(Double)
  Boolean(Bool)
  Text(String)
  Binary(Bytes)
} derive(Eq, Debug)

///|
pub(all) struct Crs {
  org : String
  code : Int
  name : String
  description : String
  wkt : String
  code_string : String
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub fn Crs::epsg(code : Int) -> Crs {
  { org: "EPSG", code, name: "", description: "", wkt: "", code_string: "" }
}

///|
pub(all) struct Header {
  name : String
  geometry_kind : GeometryKind
  columns : Array[Column]
  features_count : Int
  index_node_size : Int
  envelope : Bounds?
  crs : Crs?
  title : String
  description : String
  metadata : String
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub fn Header::new(kind : GeometryKind, columns : Array[Column]) -> Header {
  {
    name: "", geometry_kind: kind, columns, features_count: 0,
    index_node_size: 0, envelope: None, crs: None,
    title: "", description: "", metadata: "",
  }
}

///|
pub(all) struct Feature {
  geometry : Geometry?
  properties : Array[Property]
} derive(Eq, Debug)

///|
pub(all) struct Dataset {
  header : Header
  features : Array[Feature]
} derive(Eq, Debug)
