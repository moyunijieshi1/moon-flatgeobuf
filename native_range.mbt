///|
/// Shares the checked transport/index state machine with the XY adapter;
/// native feature decoding retains curves, dimensions and local schemas.
pub struct NativeRangeQuery {
  inner : RangeQuery
}

///|
pub fn NativeRangeQuery::new(
  bounds : Bounds,
  limits~ : Limits = Limits::default(),
) -> NativeRangeQuery raise FgbError {
  let inner = RangeQuery::new(bounds, limits~)
  inner.native_mode = true
  { inner, }
}

///|
pub fn NativeRangeQuery::request(
  self : NativeRangeQuery,
) -> ByteRange? raise FgbError {
  self.inner.request()
}

///|
pub fn NativeRangeQuery::accept(
  self : NativeRangeQuery,
  response : RangeResponse,
) -> Unit raise FgbError {
  self.inner.accept(response)
}

///|
pub fn NativeRangeQuery::stats(self : NativeRangeQuery) -> TransferStats {
  self.inner.stats()
}

///|
pub fn NativeRangeQuery::header(self : NativeRangeQuery) -> NativeHeader? {
  self.inner.native_header_
}

///|
pub fn NativeRangeQuery::expected_etag(self : NativeRangeQuery) -> String {
  self.inner.expected_etag()
}

///|
pub fn NativeRangeQuery::is_complete(self : NativeRangeQuery) -> Bool {
  self.inner.is_complete()
}

///|
pub fn NativeRangeQuery::is_failed(self : NativeRangeQuery) -> Bool {
  self.inner.is_failed()
}

///|
pub fn NativeRangeQuery::result(
  self : NativeRangeQuery,
) -> NativeDataset raise FgbError {
  if !self.is_complete() {
    raise InvalidArgument("query result requires completion")
  }
  guard self.inner.native_header_ is Some(header) else {
    raise InvalidArgument("query has no header")
  }
  {
    header: {
      ..header,
      features_count: self.inner.native_features.length(),
      index_node_size: 0,
    },
    features: self.inner.native_features.copy(),
  }
}
