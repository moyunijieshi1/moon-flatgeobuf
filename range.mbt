///|
pub(all) struct ByteRange {
  start : Int
  length : Int
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub fn ByteRange::end_inclusive(self : ByteRange) -> Int raise FgbError {
  if self.length < 1 {
    raise InvalidArgument("range length must be positive")
  }
  checked_add(self.start, self.length - 1)
}

///|
pub fn ByteRange::http_header(self : ByteRange) -> String raise FgbError {
  "bytes=\{self.start}-\{self.end_inclusive()}"
}

///|
pub(all) struct ContentRange {
  start : Int
  end_inclusive : Int
  total : Int
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
fn decimal_size(text : String) -> Int raise FgbError {
  if text.is_empty() { raise InvalidArgument("empty decimal size") }
  let mut result = 0
  for ch in text {
    if ch < '0' || ch > '9' {
      raise InvalidArgument("invalid decimal size")
    }
    result = checked_add(checked_mul(result, 10), ch.to_int() - '0'.to_int())
  }
  result
}

///|
pub fn parse_content_range(text : String) -> ContentRange raise FgbError {
  let pieces = text.split(" ").to_array()
  if pieces.length() != 2 || pieces[0] != "bytes" {
    raise InvalidArgument("expected Content-Range bytes start-end/total")
  }
  let parts = pieces[1].split("/").to_array()
  if parts.length() != 2 {
    raise InvalidArgument("missing Content-Range total")
  }
  let bounds = parts[0].split("-").to_array()
  if bounds.length() != 2 {
    raise InvalidArgument("invalid Content-Range interval")
  }
  let start = decimal_size(bounds[0].to_string())
  let end = decimal_size(bounds[1].to_string())
  let total = decimal_size(parts[1].to_string())
  if end < start || total <= end {
    raise InvalidArgument("invalid Content-Range bounds")
  }
  { start, end_inclusive: end, total }
}

///|
pub(all) struct RangeResponse {
  status : Int
  content_range : String
  etag : String
  body : Bytes
} derive(Eq, Debug)

///|
pub(all) struct TransferStats {
  requests : Int
  received_bytes : Int
  index_nodes : Int
  features_decoded : Int
  candidates : Int
  matched : Int
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
enum QueryStep {
  Prefix
  HeaderBlock(Int)
  IndexBlock(Int, Int, Int)
  FeatureSize(IndexHit)
  FeatureBlock(IndexHit, Int)
  Complete
  Failed
}

///|
pub struct RangeQuery {
  bounds : Bounds
  limits : Limits
  mut header_ : Header?
  mut total : Int
  mut etag : String
  mut step : QueryStep
  mut index_start : Int
  mut features_start : Int
  mut levels : Array[IndexLevel]
  pending : Array[(Int, Int, Int)]
  mut pending_cursor : Int
  hits : Array[IndexHit]
  mut hit_cursor : Int
  features : Array[Feature]
  mut stats_ : TransferStats
}

///|
pub fn RangeQuery::new(bounds : Bounds, limits? : Limits = Limits::default()) -> RangeQuery raise FgbError {
  bounds.validate()
  limits.validate()
  {
    bounds, limits, header_: None, total: 0, etag: "", step: Prefix,
    index_start: 0, features_start: 0, levels: [], pending: [],
    pending_cursor: 0, hits: [], hit_cursor: 0, features: [],
    stats_: { requests: 0, received_bytes: 0, index_nodes: 0,
      features_decoded: 0, candidates: 0, matched: 0 },
  }
}

///|
pub fn RangeQuery::stats(self : RangeQuery) -> TransferStats {
  self.stats_
}

///|
pub fn RangeQuery::expected_etag(self : RangeQuery) -> String {
  self.etag
}

///|
pub fn RangeQuery::header(self : RangeQuery) -> Header? {
  self.header_
}

///|
pub fn RangeQuery::is_complete(self : RangeQuery) -> Bool {
  self.step is Complete
}

///|
pub fn RangeQuery::is_failed(self : RangeQuery) -> Bool {
  self.step is Failed
}

///|
pub fn RangeQuery::request(self : RangeQuery) -> ByteRange? raise FgbError {
  let range : ByteRange = match self.step {
    Prefix => { start: 0, length: 12 }
    HeaderBlock(size) => { start: 8, length: size + 4 }
    IndexBlock(first, count, _) => {
      start: checked_add(self.index_start, checked_mul(first, 40)),
      length: checked_mul(count, 40),
    }
    FeatureSize(hit) => { start: checked_add(self.features_start, hit.offset), length: 4 }
    FeatureBlock(hit, size) => {
      start: checked_add(self.features_start, hit.offset), length: size + 4,
    }
    Complete => return None
    Failed => raise InvalidArgument("query has failed; start a new session")
  }
  range.end_inclusive() |> ignore
  if self.total > 0 && range.length > self.total - range.start {
    raise InvalidData(range.start, "planned read exceeds file size")
  }
  Some(range)
}

///|
fn RangeQuery::advance(self : RangeQuery) -> Unit {
  if self.pending_cursor < self.pending.length() {
    let (first, count, level) = self.pending[self.pending_cursor]
    self.pending_cursor += 1
    self.step = IndexBlock(first, count, level)
  } else if self.hit_cursor < self.hits.length() {
    let hit = self.hits[self.hit_cursor]
    self.hit_cursor += 1
    self.step = FeatureSize(hit)
  } else {
    self.step = Complete
  }
}

///|
fn RangeQuery::process(self : RangeQuery, data : Bytes) -> Unit raise FgbError {
  match self.step {
    Prefix => {
      validate_magic(data)
      let size = size32(data, 8)
      enforce(size, self.limits.max_header_bytes, "remote header bytes")
      if size < 4 { raise InvalidData(8, "invalid header size") }
      self.step = HeaderBlock(size)
    }
    HeaderBlock(_) => {
      let header = decode_header(data, limits=self.limits)
      self.header_ = Some(header)
      self.index_start = 8 + data.length()
      let index_bytes = index_byte_length(header.features_count, header.index_node_size, limits=self.limits)
      self.features_start = checked_add(self.index_start, index_bytes)
      if self.features_start > self.total {
        raise InvalidData(self.features_start, "index extends beyond object")
      }
      if header.index_node_size == 0 {
        if self.features_start == self.total {
          if header.features_count > 0 { raise InvalidData(self.total, "missing declared features") }
          self.step = Complete
        } else {
          self.step = FeatureSize({ ordinal: 0, offset: 0 })
        }
      } else {
        self.levels = index_levels(header.features_count, header.index_node_size, limits=self.limits)
        self.step = IndexBlock(0, 1, self.levels.length() - 1)
      }
    }
    IndexBlock(first, count, level_number) => {
      let header = self.header_.unwrap()
      let level = self.levels[level_number]
      if first < level.start || count > level.end - first {
        raise InvalidData(first * 40, "remote index block outside level")
      }
      for i in 0..<count {
        let node = decode_index_node(data, i)
        self.stats_ = { ..self.stats_, index_nodes: self.stats_.index_nodes + 1 }
        if !node.bounds.intersects(self.bounds) { continue }
        if level_number == 0 {
          if node.offset >= self.total - self.features_start {
            raise InvalidData(node.offset, "remote feature offset outside file")
          }
          self.hits.push({ ordinal: first + i - level.start, offset: node.offset })
          self.stats_ = { ..self.stats_, candidates: self.stats_.candidates + 1 }
        } else {
          let children = self.levels[level_number - 1]
          let expected = children.start + (first + i - level.start) * header.index_node_size
          if node.offset != expected {
            raise InvalidData((first + i) * 40, "invalid remote child pointer")
          }
          let remaining = children.end - expected
          let length = if remaining < header.index_node_size { remaining } else { header.index_node_size }
          self.pending.push((expected, length, level_number - 1))
        }
      }
      enforce(self.pending.length(), self.limits.max_index_nodes, "pending index reads")
      self.advance()
    }
    FeatureSize(hit) => {
      let size = size32(data, 0)
      enforce(size, self.limits.max_feature_bytes, "remote feature bytes")
      if size < 4 { raise InvalidData(hit.offset, "invalid remote feature size") }
      self.step = FeatureBlock(hit, size)
    }
    FeatureBlock(hit, size) => {
      let header = self.header_.unwrap()
      let feature = decode_feature(data, header, limits=self.limits)
      self.stats_ = { ..self.stats_, features_decoded: self.stats_.features_decoded + 1 }
      match feature.bounds() {
        Some(bounds) if bounds.intersects(self.bounds) => {
          self.features.push(feature)
          self.stats_ = { ..self.stats_, matched: self.stats_.matched + 1 }
        }
        _ => ()
      }
      if header.index_node_size == 0 {
        let next_offset = checked_add(hit.offset, size + 4)
        let ordinal = hit.ordinal + 1
        enforce(ordinal, self.limits.max_features, "remote feature count")
        let position = checked_add(self.features_start, next_offset)
        if position == self.total {
          if header.features_count > 0 && ordinal != header.features_count {
            raise InvalidData(position, "remote feature count mismatch")
          }
          self.step = Complete
        } else {
          if header.features_count > 0 && ordinal >= header.features_count {
            raise InvalidData(position, "extra remote features")
          }
          self.step = FeatureSize({ ordinal, offset: next_offset })
        }
      } else {
        self.advance()
      }
    }
    Complete | Failed => raise InvalidArgument("query does not accept another response")
  }
}

///|
fn RangeQuery::accept_inner(self : RangeQuery, response : RangeResponse) -> Unit raise FgbError {
  guard self.request() is Some(request) else {
    raise InvalidArgument("no pending range request")
  }
  if response.status != 206 {
    raise InvalidArgument("server must honor Range with HTTP 206")
  }
  let content_range = parse_content_range(response.content_range)
  if content_range.start != request.start || content_range.end_inclusive != request.end_inclusive() {
    raise InvalidArgument("Content-Range does not match requested interval")
  }
  if response.body.length() != request.length {
    raise InvalidData(request.start, "response body length mismatch")
  }
  enforce(content_range.total, self.limits.max_file_bytes, "remote file bytes")
  if self.total == 0 {
    self.total = content_range.total
    // Strong ETags prevent silently mixing versions between requests.
    if response.etag.is_empty() || response.etag.has_prefix("W/") {
      raise InvalidArgument("remote query requires a strong ETag")
    }
    self.etag = response.etag
  } else if self.total != content_range.total || self.etag != response.etag {
    raise InvalidArgument("remote object changed during query")
  }
  self.stats_ = {
    ..self.stats_, requests: self.stats_.requests + 1,
    received_bytes: checked_add(self.stats_.received_bytes, response.body.length()),
  }
  enforce(self.stats_.received_bytes, self.limits.max_file_bytes, "remote transfer budget")
  self.process(response.body)
}

///|
pub fn RangeQuery::accept(self : RangeQuery, response : RangeResponse) -> Unit raise FgbError {
  try self.accept_inner(response) catch {
    error => {
      self.step = Failed
      raise error
    }
  }
}

///|
pub fn RangeQuery::result(self : RangeQuery) -> Dataset raise FgbError {
  if !self.is_complete() {
    raise InvalidArgument("query result is only available after completion")
  }
  guard self.header_ is Some(header) else {
    raise InvalidArgument("query has no decoded header")
  }
  {
    header: {
      ..header, features_count: self.features.length(), index_node_size: 0,
      envelope: dataset_bounds(self.features),
    },
    features: self.features.copy(),
  }
}
