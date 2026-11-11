///|
/// Format-level reader. Preserves dimensions, curves and effective schemas.
pub struct NativeReader {
  data : Bytes
  header_ : NativeHeader
  limits : Limits
  index_start : Int32
  index_size : Int32
  features_start : Int32
  mut cursor : Int32
  mut ordinal : Int32
}

///|
pub fn NativeReader::open(
  data : Bytes,
  limits~ : Limits = Limits::default(),
) -> NativeReader raise FgbError {
  limits.validate()
  enforce(data.length(), limits.max_file_bytes, "file bytes")
  validate_magic(data)
  let size = size32(data, 8)
  enforce(size, limits.max_header_bytes, "header bytes")
  let header = decode_native_header(
    slice_bytes(data, 8, checked_add(size, 4)),
    limits~,
  )
  let index_start = checked_add(12, size)
  let index_size = index_byte_length(
    header.features_count,
    header.index_node_size,
    limits~,
  )
  require_range(data, index_start, index_size)
  let features_start = checked_add(index_start, index_size)
  {
    data,
    header_: header,
    limits,
    index_start,
    index_size,
    features_start,
    cursor: features_start,
    ordinal: 0,
  }
}

///|
pub fn NativeReader::header(self : NativeReader) -> NativeHeader {
  self.header_
}

///|
pub fn NativeReader::rewind(self : NativeReader) -> Unit {
  self.cursor = self.features_start
  self.ordinal = 0
}

///|
fn NativeReader::record(
  self : NativeReader,
  offset : Int32,
  ordinal : Int32,
) -> NativeFeatureRecord raise FgbError {
  let at = checked_add(self.features_start, offset)
  let size = size32(self.data, at)
  enforce(size, self.limits.max_feature_bytes, "feature bytes")
  let byte_length = checked_add(size, 4)
  let feature = decode_native_feature(
    slice_bytes(self.data, at, byte_length),
    self.header_,
    limits=self.limits,
  )
  { ordinal, offset, byte_length, feature, }
}

///|
pub fn NativeReader::next(
  self : NativeReader,
) -> NativeFeatureRecord? raise FgbError {
  if self.cursor == self.data.length() {
    if self.header_.features_count > 0 &&
      self.ordinal != self.header_.features_count {
      raise InvalidData(self.cursor, "feature count differs from header")
    }
    return None
  }
  if self.header_.features_count > 0 &&
    self.ordinal >= self.header_.features_count {
    raise InvalidData(self.cursor, "extra features after declared count")
  }
  enforce(
    checked_add(self.ordinal, 1),
    self.limits.max_features,
    "feature count",
  )
  let record = self.record(self.cursor - self.features_start, self.ordinal)
  self.cursor = checked_add(self.cursor, record.byte_length)
  self.ordinal += 1
  Some(record)
}

///|
pub fn NativeReader::read_all(
  self : NativeReader,
) -> NativeDataset raise FgbError {
  self.rewind()
  let features : Array[NativeFeature] = []
  while self.next() is Some(record) {
    features.push(record.feature)
  }
  { header: self.header_, features, }
}

///|
pub fn read_native_dataset(
  data : Bytes,
  limits~ : Limits = Limits::default(),
) -> NativeDataset raise FgbError {
  NativeReader::open(data, limits~).read_all()
}

///|
pub fn NativeReader::at(
  self : NativeReader,
  ordinal : Int32,
) -> NativeFeatureRecord raise FgbError {
  if ordinal < 0 {
    raise InvalidArgument("negative feature ordinal")
  }
  if self.header_.index_node_size > 0 {
    if ordinal >= self.header_.features_count {
      raise InvalidArgument("feature ordinal exceeds count")
    }
    let levels = index_levels(
      self.header_.features_count,
      self.header_.index_node_size,
      limits=self.limits,
    )
    let index = slice_bytes(self.data, self.index_start, self.index_size)
    return self.record(
      decode_index_node(index, levels[0].start + ordinal).offset,
      ordinal,
    )
  }
  let scan : NativeReader = { ..self, cursor: self.features_start, ordinal: 0, }
  while scan.next() is Some(record) {
    if record.ordinal == ordinal {
      return record
    }
  }
  raise InvalidArgument("feature ordinal exceeds count")
}

///|
pub fn NativeReader::query(
  self : NativeReader,
  bounds : Bounds,
) -> Array[NativeFeatureRecord] raise FgbError {
  bounds.validate()
  let records : Array[NativeFeatureRecord] = []
  if self.header_.index_node_size > 0 {
    let index = slice_bytes(self.data, self.index_start, self.index_size)
    let cursor = IndexCursor::new(
      index,
      self.header_.features_count,
      self.header_.index_node_size,
      bounds,
      self.limits,
    )
    while cursor.next() is Some(hit) {
      let record = self.record(hit.offset, hit.ordinal)
      match record.feature.bounds() {
        Some(actual) if actual.intersects(bounds) => records.push(record)
        _ => ()
      }
    }
  } else {
    let scan : NativeReader = {
      ..self,
      cursor: self.features_start,
      ordinal: 0,
    }
    while scan.next() is Some(record) {
      match record.feature.bounds() {
        Some(actual) if actual.intersects(bounds) => records.push(record)
        _ => ()
      }
    }
  }
  records
}

///|
pub fn NativeReader::validate(self : NativeReader) -> Unit raise FgbError {
  let scan : NativeReader = { ..self, cursor: self.features_start, ordinal: 0, }
  let index = slice_bytes(self.data, self.index_start, self.index_size)
  let leaf_start = if self.header_.index_node_size > 0 {
    validate_index(
      index,
      self.header_.features_count,
      self.header_.index_node_size,
      self.data.length() - self.features_start,
      limits=self.limits,
    )
    index_levels(
      self.header_.features_count,
      self.header_.index_node_size,
      limits=self.limits,
    )[0].start
  } else {
    0
  }
  while scan.next() is Some(record) {
    let bounds = record.feature.bounds()
    if self.header_.index_node_size > 0 {
      let leaf = decode_index_node(index, leaf_start + record.ordinal)
      if leaf.offset != record.offset {
        raise InvalidData(
          record.offset,
          "index does not point to feature boundary",
        )
      }
      match bounds {
        Some(bounds) if native_contains(leaf.bounds, bounds) => ()
        _ => raise InvalidData(record.offset, "feature outside index leaf")
      }
    }
    match (native_envelope_xy(self.header_), bounds) {
      (Some(envelope), Some(bounds)) if !native_contains(envelope, bounds) =>
        raise InvalidData(record.offset, "feature outside header envelope")
      _ => ()
    }
  }
}
