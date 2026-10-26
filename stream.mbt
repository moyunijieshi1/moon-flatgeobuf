///|
enum DecodeStage {
  MagicPrefix
  HeaderPayload(Int32)
  SkipIndex(Int32)
  RecordPrefix
  RecordPayload(Int32)
}

///|
pub struct StreamDecoder {
  limits : Limits
  mut stage : DecodeStage
  mut buffer : ByteWriter
  mut header_ : Header?
  mut total_received : Int32
  mut ordinal : Int32
  mut feature_offset : Int32
  mut closed : Bool
  mut failed : Bool
}

///|
pub fn StreamDecoder::new(
  limits~ : Limits = Limits::default(),
) -> StreamDecoder raise FgbError {
  limits.validate()
  {
    limits,
    stage: MagicPrefix,
    buffer: ByteWriter::new(),
    header_: None,
    total_received: 0,
    ordinal: 0,
    feature_offset: 0,
    closed: false,
    failed: false,
  }
}

///|
pub fn StreamDecoder::header(self : StreamDecoder) -> Header? {
  self.header_
}

///|
pub fn StreamDecoder::buffered_bytes(self : StreamDecoder) -> Int32 {
  self.buffer.position()
}

///|
pub fn StreamDecoder::features_decoded(self : StreamDecoder) -> Int32 {
  self.ordinal
}

///|
pub fn StreamDecoder::is_failed(self : StreamDecoder) -> Bool {
  self.failed
}

///|
fn StreamDecoder::target(self : StreamDecoder) -> Int32 {
  match self.stage {
    MagicPrefix => 12
    HeaderPayload(size) => size + 4
    SkipIndex(_) => 0
    RecordPrefix => 4
    RecordPayload(size) => size + 4
  }
}

///|
fn StreamDecoder::process_buffer(
  self : StreamDecoder,
  records : Array[FeatureRecord],
) -> Unit raise FgbError {
  let data = self.buffer.finish()
  match self.stage {
    MagicPrefix => {
      validate_magic(data)
      let size = size32(data, 8)
      enforce(size, self.limits.max_header_bytes, "stream header bytes")
      if size < 4 {
        raise InvalidData(8, "invalid streamed header size")
      }
      self.buffer = ByteWriter::new()
      self.buffer.bytes(slice_bytes(data, 8, 4))
      self.stage = HeaderPayload(size)
    }
    HeaderPayload(_) => {
      let header = decode_header(data, limits=self.limits)
      let index_size = index_byte_length(
        header.features_count,
        header.index_node_size,
        limits=self.limits,
      )
      self.header_ = Some(header)
      self.buffer = ByteWriter::new()
      self.stage = if index_size > 0 {
        SkipIndex(index_size)
      } else {
        RecordPrefix
      }
    }
    RecordPrefix => {
      let size = size32(data, 0)
      enforce(size, self.limits.max_feature_bytes, "stream feature bytes")
      if size < 4 {
        raise InvalidData(self.feature_offset, "invalid streamed feature size")
      }
      let header = self.header_.unwrap()
      if header.features_count > 0 && self.ordinal >= header.features_count {
        raise InvalidData(self.feature_offset, "extra streamed feature")
      }
      enforce(
        checked_add(self.ordinal, 1),
        self.limits.max_features,
        "stream feature count",
      )
      self.stage = RecordPayload(size)
    }
    RecordPayload(size) => {
      let feature = decode_feature(
        data,
        self.header_.unwrap(),
        limits=self.limits,
      )
      records.push({
        ordinal: self.ordinal,
        offset: self.feature_offset,
        byte_length: size + 4,
        feature,
      })
      self.ordinal += 1
      self.feature_offset = checked_add(self.feature_offset, size + 4)
      self.buffer = ByteWriter::new()
      self.stage = RecordPrefix
    }
    SkipIndex(_) => raise InvalidArgument("internal stream index state")
  }
}

///|
fn StreamDecoder::push_inner(
  self : StreamDecoder,
  chunk : Bytes,
) -> Array[FeatureRecord] raise FgbError {
  if self.closed || self.failed {
    raise InvalidArgument("stream is closed or failed")
  }
  self.total_received = checked_add(self.total_received, chunk.length())
  enforce(self.total_received, self.limits.max_file_bytes, "stream file bytes")
  let records : Array[FeatureRecord] = []
  let mut cursor = 0
  while cursor < chunk.length() {
    match self.stage {
      SkipIndex(remaining) => {
        let take = if remaining < chunk.length() - cursor {
          remaining
        } else {
          chunk.length() - cursor
        }
        cursor += take
        self.stage = if take == remaining {
          RecordPrefix
        } else {
          SkipIndex(remaining - take)
        }
      }
      _ => {
        let needed = self.target() - self.buffer.position()
        let take = if needed < chunk.length() - cursor {
          needed
        } else {
          chunk.length() - cursor
        }
        self.buffer.bytes_from(chunk, cursor, take)
        cursor += take
        if self.buffer.position() == self.target() {
          self.process_buffer(records)
        }
      }
    }
  }
  records
}

///|
pub fn StreamDecoder::push(
  self : StreamDecoder,
  chunk : Bytes,
) -> Array[FeatureRecord] raise FgbError {
  errdefer {
    self.failed = true
  }
  self.push_inner(chunk)
}

///|
pub fn StreamDecoder::finish(self : StreamDecoder) -> Unit raise FgbError {
  if self.closed || self.failed {
    raise InvalidArgument("stream is closed or failed")
  }
  self.closed = true
  if !(self.stage is RecordPrefix) || self.buffer.position() != 0 {
    self.failed = true
    raise InvalidData(self.total_received, "truncated stream at end of input")
  }
  let header = self.header_.unwrap()
  if header.features_count > 0 && header.features_count != self.ordinal {
    self.failed = true
    raise InvalidData(self.total_received, "stream count differs from header")
  }
}

///|
pub struct StreamWriter {
  header_ : Header
  limits : Limits
  mut started : Bool
  mut closed : Bool
  mut feature_count : Int32
  mut total_bytes : Int32
}

///|
pub fn StreamWriter::new(
  header : Header,
  limits~ : Limits = Limits::default(),
) -> StreamWriter raise FgbError {
  limits.validate()
  let header = {
    ..header,
    features_count: 0,
    index_node_size: 0,
    envelope: None,
  }
  validate_header(header, limits~)
  {
    header_: header,
    limits,
    started: false,
    closed: false,
    feature_count: 0,
    total_bytes: 0,
  }
}

///|
pub fn StreamWriter::begin(self : StreamWriter) -> Bytes raise FgbError {
  if self.started || self.closed {
    raise InvalidArgument("stream writer already started or closed")
  }
  let writer = ByteWriter::new()
  writer.bytes(b"\x66\x67\x62\x03\x66\x67\x62\x01")
  writer.bytes(encode_header(self.header_, limits=self.limits))
  self.total_bytes = writer.position()
  enforce(self.total_bytes, self.limits.max_file_bytes, "stream file bytes")
  self.started = true
  writer.finish()
}

///|
pub fn StreamWriter::append(
  self : StreamWriter,
  feature : Feature,
) -> Bytes raise FgbError {
  if !self.started || self.closed {
    raise InvalidArgument("stream writer must be started and open")
  }
  enforce(
    self.feature_count + 1,
    self.limits.max_features,
    "stream feature count",
  )
  let bytes = encode_feature(feature, self.header_, limits=self.limits)
  let total = checked_add(self.total_bytes, bytes.length())
  enforce(total, self.limits.max_file_bytes, "stream file bytes")
  self.total_bytes = total
  self.feature_count += 1
  bytes
}

///|
pub fn StreamWriter::finish(self : StreamWriter) -> Unit raise FgbError {
  if !self.started || self.closed {
    raise InvalidArgument("stream writer must be started and open")
  }
  self.closed = true
}

///|
pub fn StreamWriter::features_written(self : StreamWriter) -> Int32 {
  self.feature_count
}

///|
pub fn StreamWriter::bytes_written(self : StreamWriter) -> Int32 {
  self.total_bytes
}
