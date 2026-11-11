///|
pub struct NativeStreamDecoder {
  inner : StreamDecoder
}

///|
pub fn NativeStreamDecoder::new(
  limits~ : Limits = Limits::default(),
) -> NativeStreamDecoder raise FgbError {
  let inner = StreamDecoder::new(limits~)
  inner.native_mode = true
  { inner, }
}

///|
pub fn NativeStreamDecoder::header(self : NativeStreamDecoder) -> NativeHeader? {
  self.inner.native_header_
}

///|
pub fn NativeStreamDecoder::push(
  self : NativeStreamDecoder,
  bytes : Bytes,
) -> Array[NativeFeatureRecord] raise FgbError {
  errdefer self.inner.native_records.clear()
  self.inner.push(bytes) |> ignore
  let records = self.inner.native_records.copy()
  self.inner.native_records.clear()
  records
}

///|
pub fn NativeStreamDecoder::finish(
  self : NativeStreamDecoder,
) -> Unit raise FgbError {
  self.inner.finish()
}

///|
pub fn NativeStreamDecoder::buffered_bytes(self : NativeStreamDecoder) -> Int32 {
  self.inner.buffered_bytes()
}

///|
pub fn NativeStreamDecoder::is_failed(self : NativeStreamDecoder) -> Bool {
  self.inner.is_failed()
}

///|
pub struct NativeStreamWriter {
  header_ : NativeHeader
  limits : Limits
  mut started : Bool
  mut closed : Bool
  mut count : Int32
  mut bytes : Int32
}

///|
pub fn NativeStreamWriter::new(
  header : NativeHeader,
  limits~ : Limits = Limits::default(),
) -> NativeStreamWriter raise FgbError {
  let header = {
    ..header,
    features_count: 0,
    index_node_size: 0,
    envelope: None,
  }
  header.validate(limits~)
  {
    header_: header,
    limits,
    started: false,
    closed: false,
    count: 0,
    bytes: 0,
  }
}

///|
pub fn NativeStreamWriter::begin(
  self : NativeStreamWriter,
) -> Bytes raise FgbError {
  if self.started || self.closed {
    raise InvalidArgument("stream writer already started or closed")
  }
  let writer = ByteWriter::new()
  writer.bytes(b"\x66\x67\x62\x03\x66\x67\x62\x01")
  writer.bytes(encode_native_header(self.header_, limits=self.limits))
  enforce(writer.position(), self.limits.max_file_bytes, "stream file bytes")
  self.bytes = writer.position()
  self.started = true
  writer.finish()
}

///|
pub fn NativeStreamWriter::append(
  self : NativeStreamWriter,
  feature : NativeFeature,
) -> Bytes raise FgbError {
  if !self.started || self.closed {
    raise InvalidArgument("stream writer must be started and open")
  }
  enforce(
    checked_add(self.count, 1),
    self.limits.max_features,
    "stream feature count",
  )
  let bytes = encode_native_feature(feature, self.header_, limits=self.limits)
  let total = checked_add(self.bytes, bytes.length())
  enforce(total, self.limits.max_file_bytes, "stream file bytes")
  self.bytes = total
  self.count += 1
  bytes
}

///|
pub fn NativeStreamWriter::finish(
  self : NativeStreamWriter,
) -> Unit raise FgbError {
  if !self.started || self.closed {
    raise InvalidArgument("stream writer must be started and open")
  }
  self.closed = true
}

///|
pub fn NativeStreamWriter::features_written(self : NativeStreamWriter) -> Int32 {
  self.count
}

///|
pub fn NativeStreamWriter::bytes_written(self : NativeStreamWriter) -> Int32 {
  self.bytes
}
