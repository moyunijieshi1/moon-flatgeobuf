///|
pub fn decode_feature(
  data : Bytes,
  header : Header,
  limits~ : Limits = Limits::default(),
) -> Feature raise FgbError {
  limits.validate()
  let payload = sized_payload(data, 0, limits.max_feature_bytes)
  if payload.length() + 4 != data.length() {
    raise InvalidData(0, "trailing bytes after feature")
  }
  let table = TableView::root(payload)
  if table.reference(2) != 0 {
    raise Unsupported("per-feature column schemas")
  }
  let geometry_at = table.reference(0)
  let geometry = if geometry_at == 0 {
    None
  } else {
    Some(
      read_geometry(
        payload,
        geometry_at,
        header.geometry_kind,
        limits,
        1,
        Ref(0),
        Ref(0),
      ),
    )
  }
  let (properties_at, properties_size) = table.vector(
    1,
    1,
    limits.max_feature_bytes,
  )
  let properties = decode_properties(
    slice_bytes(payload, properties_at, properties_size),
    header.columns,
    limits~,
  )
  { geometry, properties, }
}

///|
pub fn encode_feature(
  feature : Feature,
  header : Header,
  limits~ : Limits = Limits::default(),
) -> Bytes raise FgbError {
  limits.validate()
  let properties = encode_properties(
    feature.properties,
    header.columns,
    limits~,
  )
  let b = FbBuilder::new()
  let table = b.table(3)
  match feature.geometry {
    None => ()
    Some(g) => {
      g.validate(limits~)
      if header.geometry_kind != Unknown && header.geometry_kind != g.kind {
        raise InvalidArgument("feature geometry conflicts with header type")
      }
      b.reference(table, 0, write_geometry(b, g))
    }
  }
  if !properties.is_empty() {
    let at = b.vector(properties.length(), 1)
    b.writer.bytes(properties)
    b.reference(table, 1, at)
  }
  let result = b.finish(table)
  enforce(result.length() - 4, limits.max_feature_bytes, "feature bytes")
  result
}

///|
pub(all) struct FeatureRecord {
  ordinal : Int32
  offset : Int32
  byte_length : Int32
  feature : Feature
} derive(Eq, Debug)

///|
pub fn Feature::property(
  self : Feature,
  header : Header,
  name : String,
) -> Property? {
  for i in 0..<header.columns.length() {
    if header.columns[i].name == name && i < self.properties.length() {
      return Some(self.properties[i])
    }
  }
  None
}
