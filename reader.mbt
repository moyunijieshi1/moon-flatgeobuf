///|
pub struct Reader {
  data : Bytes
  header_ : Header
  limits : Limits
  index_start : Int
  index_size : Int
  features_start : Int
  mut cursor : Int
  mut ordinal : Int
}

///|
pub fn Reader::open(data : Bytes, limits? : Limits = Limits::default()) -> Reader raise FgbError {
  limits.validate()
  enforce(data.length(), limits.max_file_bytes, "file bytes")
  validate_magic(data)
  let header_size = size32(data, 8)
  enforce(header_size, limits.max_header_bytes, "header bytes")
  let index_start = checked_add(12, header_size)
  let header = decode_header(slice_bytes(data, 8, checked_add(header_size, 4)), limits=limits)
  let index_size = index_byte_length(header.features_count, header.index_node_size, limits=limits)
  let features_start = checked_add(index_start, index_size)
  require_range(data, index_start, index_size)
  {
    data, header_: header, limits, index_start, index_size, features_start,
    cursor: features_start, ordinal: 0,
  }
}

///|
pub fn Reader::header(self : Reader) -> Header {
  self.header_
}

///|
pub fn Reader::feature_section_offset(self : Reader) -> Int {
  self.features_start
}

///|
pub fn Reader::has_index(self : Reader) -> Bool {
  self.header_.index_node_size > 0
}

///|
pub fn Reader::rewind(self : Reader) -> Unit {
  self.cursor = self.features_start
  self.ordinal = 0
}

///|
fn Reader::record(self : Reader, offset : Int, ordinal : Int) -> FeatureRecord raise FgbError {
  let at = checked_add(self.features_start, offset)
  let size = size32(self.data, at)
  enforce(size, self.limits.max_feature_bytes, "feature bytes")
  let byte_length = checked_add(size, 4)
  let feature = decode_feature(slice_bytes(self.data, at, byte_length), self.header_, limits=self.limits)
  { ordinal, offset, byte_length, feature }
}

///|
pub fn Reader::next(self : Reader) -> FeatureRecord? raise FgbError {
  if self.cursor == self.data.length() {
    if self.header_.features_count > 0 && self.ordinal != self.header_.features_count {
      raise InvalidData(self.cursor, "fewer features than header declares")
    }
    return None
  }
  if self.header_.features_count > 0 && self.ordinal >= self.header_.features_count {
    raise InvalidData(self.cursor, "more features than header declares")
  }
  enforce(checked_add(self.ordinal, 1), self.limits.max_features, "feature count")
  let record = self.record(self.cursor - self.features_start, self.ordinal)
  self.cursor = checked_add(self.cursor, record.byte_length)
  self.ordinal += 1
  Some(record)
}

///|
pub fn Reader::read_all(self : Reader) -> Dataset raise FgbError {
  self.rewind()
  let features : Array[Feature] = []
  while self.next() is Some(record) {
    features.push(record.feature)
  }
  { header: self.header_, features }
}

///|
pub fn read_dataset(data : Bytes, limits? : Limits = Limits::default()) -> Dataset raise FgbError {
  Reader::open(data, limits=limits).read_all()
}

///|
pub fn Reader::at(self : Reader, ordinal : Int) -> FeatureRecord raise FgbError {
  if ordinal < 0 {
    raise InvalidArgument("negative feature ordinal")
  }
  if self.has_index() {
    if ordinal >= self.header_.features_count {
      raise InvalidArgument("feature ordinal exceeds count")
    }
    let levels = index_levels(self.header_.features_count, self.header_.index_node_size, limits=self.limits)
    let index = slice_bytes(self.data, self.index_start, self.index_size)
    let node = decode_index_node(index, levels[0].start + ordinal)
    return self.record(node.offset, ordinal)
  }
  let mut cursor = self.features_start
  let mut current = 0
  while cursor < self.data.length() {
    let size = size32(self.data, cursor)
    enforce(size, self.limits.max_feature_bytes, "feature bytes")
    if current == ordinal {
      return self.record(cursor - self.features_start, current)
    }
    cursor = checked_add(cursor, checked_add(size, 4))
    current += 1
    enforce(current, self.limits.max_features, "feature count")
  }
  raise InvalidArgument("feature ordinal exceeds count")
}

///|
pub fn Reader::query(self : Reader, bounds : Bounds) -> Array[FeatureRecord] raise FgbError {
  bounds.validate()
  let result : Array[FeatureRecord] = []
  if self.has_index() {
    let index = slice_bytes(self.data, self.index_start, self.index_size)
    let hits = query_index(index, self.header_.features_count, self.header_.index_node_size, bounds, limits=self.limits)
    for hit in hits {
      let record = self.record(hit.offset, hit.ordinal)
      match record.feature.bounds() {
        Some(actual) if actual.intersects(bounds) => result.push(record)
        _ => ()
      }
    }
  } else {
    self.rewind()
    while self.next() is Some(record) {
      match record.feature.bounds() {
        Some(actual) if actual.intersects(bounds) => result.push(record)
        _ => ()
      }
    }
  }
  result
}

///|
pub fn Reader::validate(self : Reader) -> Unit raise FgbError {
  let dataset = self.read_all()
  if self.has_index() {
    let index = slice_bytes(self.data, self.index_start, self.index_size)
    validate_index(index, self.header_.features_count, self.header_.index_node_size, self.data.length() - self.features_start, limits=self.limits)
    let levels = index_levels(self.header_.features_count, self.header_.index_node_size, limits=self.limits)
    let mut offset = 0
    self.rewind()
    for i in 0..<dataset.features.length() {
      let node = decode_index_node(index, levels[0].start + i)
      if node.offset != offset {
        raise InvalidData(self.index_start + (levels[0].start + i) * 40, "leaf does not point to feature boundary")
      }
      match dataset.features[i].bounds() {
        Some(bounds) if node.bounds.contains(bounds) => ()
        _ => raise InvalidData(offset, "indexed feature missing geometry or outside leaf bounds")
      }
      let record = self.record(offset, i)
      offset += record.byte_length
    }
  }
  match self.header_.envelope {
    None => ()
    Some(envelope) => {
      for feature in dataset.features {
        match feature.bounds() {
          Some(bounds) if !envelope.contains(bounds) =>
            raise InvalidData(8, "feature outside header envelope")
          _ => ()
        }
      }
    }
  }
}
