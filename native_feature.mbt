///|
pub fn decode_native_feature(
  data : Bytes,
  header : NativeHeader,
  limits~ : Limits = Limits::default(),
) -> NativeFeature raise FgbError {
  header.validate(limits~)
  let payload = sized_payload(data, 0, limits.max_feature_bytes)
  if payload.length() + 4 != data.length() {
    raise InvalidData(0, "trailing feature data")
  }
  let table = TableView::root(payload)
  let columns = native_read_columns(table, 2, limits)
  let geometry_at = table.reference(0)
  let geometry = if geometry_at == 0 {
    None
  } else {
    let geometry = native_read_geometry(
      payload,
      geometry_at,
      header.geometry_type,
      limits,
      1,
      Ref(0),
      Ref(0),
    )
    geometry.validate(header, limits~)
    Some(geometry)
  }
  let schema = columns
    .unwrap_or(header.columns.unwrap_or([]))
    .map(c => c.property_column())
  let (at, length) = table.vector(1, 1, limits.max_feature_bytes)
  let properties = decode_properties_impl(
    slice_bytes(payload, at, length),
    schema,
    limits,
    true,
  )
  { geometry, properties, columns, }
}

///|
pub fn encode_native_feature(
  feature : NativeFeature,
  header : NativeHeader,
  limits~ : Limits = Limits::default(),
) -> Bytes raise FgbError {
  header.validate(limits~)
  let columns = feature.effective_columns(header)
  native_check_columns(columns, limits)
  let properties = encode_properties_impl(
    feature.properties,
    columns.map(c => c.property_column()),
    limits,
    true,
  )
  let b = FbBuilder::new()
  let table = b.table(3)
  match feature.geometry {
    None => ()
    Some(geometry) => {
      geometry.validate(header, limits~)
      b.reference(table, 0, native_write_geometry(b, geometry))
    }
  }
  if !properties.is_empty() {
    let at = b.vector(properties.length(), 1)
    b.writer.bytes(properties)
    b.reference(table, 1, at)
  }
  native_write_columns(b, table, 2, feature.columns)
  let result = b.finish(table)
  enforce(result.length() - 4, limits.max_feature_bytes, "feature bytes")
  result
}
