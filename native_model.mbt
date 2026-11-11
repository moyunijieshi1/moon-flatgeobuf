///|
/// Lossless format-level model. Unlike the RFC 7946 adapter, this retains
/// optional vectors, curved geometry types and all four extra dimensions.
#derive(Eq, Debug, ToJson, @json.FromJson)
pub(all) struct NativeGeometry {
  kind : Int32
  declared_type : Int32
  xy : Array[Coordinate]?
  z : Array[Double]?
  m : Array[Double]?
  t : Array[Double]?
  tm : Array[UInt64]?
  ends : Array[Int32]?
  parts : Array[NativeGeometry]?
}

///|
pub fn NativeGeometry::new(kind : Int32) -> NativeGeometry {
  {
    kind,
    declared_type: kind,
    xy: None,
    z: None,
    m: None,
    t: None,
    tm: None,
    ends: None,
    parts: None,
  }
}

///|
pub fn NativeGeometry::point(x : Double, y : Double) -> NativeGeometry {
  { ..NativeGeometry::new(1), xy: Some([{ x, y, }]), }
}

///|
#derive(Eq, Debug, ToJson, @json.FromJson)
pub(all) struct NativeColumn {
  name : String
  type_code : Int32
  title : String?
  description : String?
  width : Int32
  precision : Int32
  scale : Int32
  nullable : Bool
  unique : Bool
  primary_key : Bool
  metadata : String?
}

///|
pub fn NativeColumn::new(name : String, type_code : Int32) -> NativeColumn {
  {
    name,
    type_code,
    title: None,
    description: None,
    width: -1,
    precision: -1,
    scale: -1,
    nullable: true,
    unique: false,
    primary_key: false,
    metadata: None,
  }
}

///|
fn NativeColumn::property_column(self : NativeColumn) -> Column {
  {
    name: self.name,
    type_code: self.type_code,
    title: self.title.unwrap_or(""),
    description: self.description.unwrap_or(""),
    width: self.width,
    precision: self.precision,
    scale: self.scale,
    nullable: self.nullable,
    unique: self.unique,
    primary_key: self.primary_key,
    metadata: self.metadata.unwrap_or(""),
  }
}

///|
#derive(Eq, Debug, ToJson, @json.FromJson)
pub(all) struct NativeCrs {
  org : String?
  code : Int32
  name : String?
  description : String?
  wkt : String?
  code_string : String?
}

///|
pub fn NativeCrs::epsg(code : Int32) -> NativeCrs {
  {
    org: Some("EPSG"),
    code,
    name: None,
    description: None,
    wkt: None,
    code_string: None,
  }
}

///|
#derive(Eq, Debug, ToJson, @json.FromJson)
pub(all) struct NativeHeader {
  name : String?
  envelope : Array[Double]?
  geometry_type : Int32
  has_z : Bool
  has_m : Bool
  has_t : Bool
  has_tm : Bool
  columns : Array[NativeColumn]?
  features_count : Int32
  index_node_size : Int32
  crs : NativeCrs?
  title : String?
  description : String?
  metadata : String?
}

///|
pub fn NativeHeader::new(geometry_type : Int32) -> NativeHeader {
  {
    name: None,
    envelope: None,
    geometry_type,
    has_z: false,
    has_m: false,
    has_t: false,
    has_tm: false,
    columns: None,
    features_count: 0,
    index_node_size: 0,
    crs: None,
    title: None,
    description: None,
    metadata: None,
  }
}

///|
fn NativeHeader::plan_header(self : NativeHeader) -> Header {
  {
    ..Header::new(Unknown, []),
    features_count: self.features_count,
    index_node_size: self.index_node_size,
    envelope: native_envelope_xy(self),
  }
}

///|
fn NativeFeature::bounds_proxy(self : NativeFeature) -> Feature {
  match self.bounds() {
    Some(bounds) => native_bounds_feature(bounds)
    None => { geometry: None, properties: [], }
  }
}

///|
#derive(Eq, Debug)
pub(all) struct NativeFeature {
  geometry : NativeGeometry?
  properties : Array[Property]
  /// None inherits the header; Some([]) explicitly supplies an empty schema.
  columns : Array[NativeColumn]?
}

///|
pub fn NativeFeature::effective_columns(
  self : NativeFeature,
  header : NativeHeader,
) -> Array[NativeColumn] {
  self.columns.unwrap_or(header.columns.unwrap_or([]))
}

///|
#derive(Eq, Debug)
pub(all) struct NativeDataset {
  header : NativeHeader
  features : Array[NativeFeature]
}

///|
#derive(Eq, Debug)
pub(all) struct NativeFeatureRecord {
  ordinal : Int32
  offset : Int32
  byte_length : Int32
  feature : NativeFeature
}
