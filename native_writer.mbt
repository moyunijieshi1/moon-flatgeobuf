///|
fn native_bounds_feature(bounds : Bounds) -> Feature {
  {
    geometry: Some({
      kind: LineString,
      xy: [
        { x: bounds.min_x, y: bounds.min_y, },
        { x: bounds.max_x, y: bounds.max_y, },
      ],
      ends: [],
      parts: [],
    }),
    properties: [],
  }
}

///|
/// Write the supplied header and record order, preserving unknown count and
/// per-feature schema overrides. Indexed files require finite, nonempty bounds.
pub fn write_native_dataset(
  dataset : NativeDataset,
  limits~ : Limits = Limits::default(),
) -> Bytes raise FgbError {
  dataset.header.validate(limits~)
  enforce(dataset.features.length(), limits.max_features, "feature count")
  if dataset.header.features_count > 0 &&
    dataset.header.features_count != dataset.features.length() {
    raise InvalidArgument("declared count differs from feature count")
  }
  let records : Array[Bytes] = []
  let offsets : Array[Int32] = []
  let proxies : Array[Feature] = []
  let mut offset = 0
  let envelope = native_envelope_xy(dataset.header)
  for feature in dataset.features {
    let bytes = encode_native_feature(feature, dataset.header, limits~)
    offsets.push(offset)
    offset = checked_add(offset, bytes.length())
    enforce(offset, limits.max_file_bytes, "feature section bytes")
    records.push(bytes)
    let bounds = if envelope is Some(_) || dataset.header.index_node_size > 0 {
      feature.bounds()
    } else {
      None
    }
    if envelope is Some(envelope) &&
      bounds is Some(bounds) &&
      !native_contains(envelope, bounds) {
      raise InvalidArgument("feature outside header envelope")
    }
    if dataset.header.index_node_size > 0 {
      guard bounds is Some(bounds) else {
        raise InvalidArgument(
          "indexed file cannot contain null or empty geometry",
        )
      }
      proxies.push(native_bounds_feature(bounds))
    }
  }
  let header = encode_native_header(dataset.header, limits~)
  let index = if dataset.header.index_node_size == 0 {
    b""
  } else {
    build_index(proxies, offsets, dataset.header.index_node_size, limits)
  }
  let total = checked_add(
    checked_add(8, header.length()),
    checked_add(index.length(), offset),
  )
  enforce(total, limits.max_file_bytes, "file bytes")
  let result = ByteWriter::new()
  result.bytes(b"\x66\x67\x62\x03\x66\x67\x62\x01")
  result.bytes(header)
  result.bytes(index)
  for record in records {
    result.bytes(record)
  }
  result.finish()
}
