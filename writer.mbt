///|
pub(all) struct WriteOptions {
  index_node_size : Int
  hilbert_sort : Bool
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub fn WriteOptions::default() -> WriteOptions {
  { index_node_size: 16, hilbert_sort: true }
}

///|
fn hilbert_key(x_ : Int, y_ : Int) -> Int64 {
  let mut x = x_
  let mut y = y_
  let mut distance = 0L
  let mut scale = 32768
  while scale > 0 {
    let rx = if (x & scale) != 0 { 1 } else { 0 }
    let ry = if (y & scale) != 0 { 1 } else { 0 }
    distance += scale.to_int64() * scale.to_int64() * ((3 * rx) ^ ry).to_int64()
    if ry == 0 {
      if rx == 1 {
        x = 65535 - x
        y = 65535 - y
      }
      let old_x = x
      x = y
      y = old_x
    }
    scale = scale >> 1
  }
  distance
}

///|
fn normalized_center(minimum : Double, maximum : Double, extent_min : Double, extent_max : Double) -> Int {
  // Half-scaled differences avoid overflowing on large finite coordinates.
  let width = extent_max / 2.0 - extent_min / 2.0
  if width <= 0.0 { return 0 }
  let center = minimum / 4.0 + maximum / 4.0
  let value = (center - extent_min / 2.0) / width * 65535.0
  if value <= 0.0 { 0 } else if value >= 65535.0 { 65535 } else { value.to_int() }
}

///|
fn sorted_features(features : Array[Feature], extent : Bounds) -> Array[Feature] raise FgbError {
  let keys : Array[(Int64, Int, Feature)] = []
  for i in 0..<features.length() {
    guard features[i].bounds() is Some(b) else {
      raise InvalidArgument("indexed files cannot contain null geometries")
    }
    let x = normalized_center(b.min_x, b.max_x, extent.min_x, extent.max_x)
    let y = normalized_center(b.min_y, b.max_y, extent.min_y, extent.max_y)
    keys.push((hilbert_key(x, y), i, features[i]))
  }
  keys.sort_by((a, b) => {
    let order = a.0.compare(b.0)
    if order == 0 { a.1.compare(b.1) } else { order }
  })
  keys.map(item => item.2)
}

///|
fn build_index(features : Array[Feature], offsets : Array[Int], node_size : Int, limits : Limits) -> Bytes raise FgbError {
  let levels = index_levels(features.length(), node_size, limits=limits)
  let total = levels[0].end
  let empty : IndexNode = {
    bounds: { min_x: 0.0, min_y: 0.0, max_x: 0.0, max_y: 0.0 }, offset: 0,
  }
  let nodes = Array::make(total, empty)
  for i in 0..<features.length() {
    guard features[i].bounds() is Some(bounds) else {
      raise InvalidArgument("cannot index a null geometry")
    }
    nodes[levels[0].start + i] = { bounds, offset: offsets[i] }
  }
  for level_number in 1..<levels.length() {
    let level = levels[level_number]
    let children = levels[level_number - 1]
    for parent in level.start..<level.end {
      let first = children.start + (parent - level.start) * node_size
      let end = if node_size > children.end - first { children.end } else { first + node_size }
      let mut bounds = nodes[first].bounds
      for child in (first + 1)..<end {
        bounds = bounds.union(nodes[child].bounds)
      }
      nodes[parent] = { bounds, offset: first }
    }
  }
  let writer = ByteWriter::new()
  for node in nodes {
    writer.double(node.bounds.min_x)
    writer.double(node.bounds.min_y)
    writer.double(node.bounds.max_x)
    writer.double(node.bounds.max_y)
    writer.long(node.offset.to_uint64())
  }
  writer.finish()
}

///|
pub fn dataset_bounds(features : Array[Feature]) -> Bounds? {
  let mut bounds : Bounds? = None
  for feature in features {
    match feature.bounds() {
      None => ()
      Some(b) => bounds = Some(match bounds { None => b; Some(previous) => previous.union(b) })
    }
  }
  bounds
}

///|
pub fn write_dataset(dataset : Dataset, options? : WriteOptions = WriteOptions::default(), limits? : Limits = Limits::default()) -> Bytes raise FgbError {
  limits.validate()
  if options.index_node_size < 0 || options.index_node_size == 1 || options.index_node_size > 65535 {
    raise InvalidArgument("invalid index node size")
  }
  enforce(dataset.features.length(), limits.max_features, "feature count")
  // Validate before computing bounds and Hilbert keys.
  for feature in dataset.features {
    match feature.geometry {
      None => ()
      Some(g) => g.validate(limits=limits)
    }
  }
  let envelope = dataset_bounds(dataset.features)
  let node_size = if dataset.features.is_empty() { 0 } else { options.index_node_size }
  let features = if node_size > 0 && options.hilbert_sort {
    match envelope {
      None => raise InvalidArgument("indexed file needs geometry bounds")
      Some(bounds) => sorted_features(dataset.features, bounds)
    }
  } else {
    dataset.features
  }
  let header = {
    ..dataset.header, features_count: features.length(), index_node_size: node_size, envelope,
  }
  let header_bytes = encode_header(header, limits=limits)
  let records : Array[Bytes] = []
  let offsets : Array[Int] = []
  let mut feature_bytes = 0
  for feature in features {
    let record = encode_feature(feature, header, limits=limits)
    offsets.push(feature_bytes)
    feature_bytes = checked_add(feature_bytes, record.length())
    enforce(feature_bytes, limits.max_file_bytes, "feature section bytes")
    records.push(record)
  }
  let index = if node_size == 0 { b"" } else { build_index(features, offsets, node_size, limits) }
  let total = checked_add(checked_add(8 + header_bytes.length(), index.length()), feature_bytes)
  enforce(total, limits.max_file_bytes, "file bytes")
  let output = ByteWriter::new()
  output.bytes(b"\x66\x67\x62\x03\x66\x67\x62\x01")
  output.bytes(header_bytes)
  output.bytes(index)
  for record in records {
    output.bytes(record)
  }
  output.finish()
}
