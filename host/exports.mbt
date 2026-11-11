///|
pub fn encode(text : String, indexed : Bool) -> Bytes raise {
  let input = @json.parse(text)
  let dataset = @fgb.import_geojson(input)
  @fgb.write_dataset(dataset, options={
    index_node_size: if indexed {
      16
    } else {
      0
    },
    hilbert_sort: indexed,
  })
}

///|
pub fn decode(data : Bytes) -> String raise {
  @fgb.read_dataset(data).to_geojson().stringify()
}

///|
pub fn inspect(data : Bytes) -> String raise {
  @fgb.Reader::open(data).header().to_json().stringify()
}

///|
pub fn query(data : Bytes, bounds : String) -> String raise {
  let bounds : @fgb.Bounds = @json.from_json(@json.parse(bounds))
  let reader = @fgb.Reader::open(data)
  let records = reader.query(bounds)
  let dataset : @fgb.Dataset = {
    header: reader.header(),
    features: records.map(r => r.feature),
  }
  dataset.to_geojson().stringify()
}

///|
pub fn audit(data : Bytes) -> String raise {
  let reader = @fgb.Reader::open(data)
  reader.validate()
  "ok"
}

///|
pub fn start_remote(bounds : String) -> @fgb.RangeQuery raise {
  let bounds : @fgb.Bounds = @json.from_json(@json.parse(bounds))
  @fgb.RangeQuery::new(bounds)
}

///|
pub fn next_remote(session : @fgb.RangeQuery) -> String raise {
  let request = session.request()
  match request {
    None => "null"
    Some(range) => range.to_json().stringify()
  }
}

///|
pub fn accept_remote(
  session : @fgb.RangeQuery,
  status : Int32,
  content_range : String,
  etag : String,
  bytes : Bytes,
) -> Unit raise {
  session.accept({ status, content_range, etag, body: bytes, })
}

///|
pub fn result_remote(session : @fgb.RangeQuery) -> String raise {
  session.result().to_geojson().stringify()
}

///|
pub fn stats_remote(session : @fgb.RangeQuery) -> String {
  session.stats().to_json().stringify()
}

///|
pub fn summary(data : Bytes) -> String raise {
  @fgb.inspect_archive(data).to_json().stringify()
}

///|
pub fn report(data : Bytes) -> String {
  @fgb.audit_archive(data).to_json().stringify()
}

///|
pub fn native_transcode(data : Bytes) -> Bytes raise {
  let reader = @fgb.NativeReader::open(data)
  reader.validate()
  @fgb.write_native_dataset(reader.read_all())
}

///|
pub fn native_query_count(data : Bytes, bounds : String) -> Int32 raise {
  let reader = @fgb.NativeReader::open(data)
  reader.validate()
  let bounds : @fgb.Bounds = @json.from_json(@json.parse(bounds))
  reader.query(bounds).length()
}

///|
pub fn native_query(data : Bytes, bounds : String) -> Bytes raise {
  let reader = @fgb.NativeReader::open(data)
  let bounds : @fgb.Bounds = @json.from_json(@json.parse(bounds))
  let features = reader.query(bounds).map(record => record.feature)
  let header = {
    ..reader.header(),
    features_count: features.length(),
    index_node_size: 0,
  }
  @fgb.write_native_dataset({ header, features, })
}

///|
pub fn native_inspect(data : Bytes) -> String raise {
  @fgb.NativeReader::open(data).header().to_json().stringify()
}

///|
pub fn native_validate(data : Bytes) -> String raise {
  @fgb.NativeReader::open(data).validate()
  "ok"
}

///|
priv suberror HostError {
  InvalidChunkSize
}

///|
pub fn native_stream_transcode(data : Bytes, chunk_size : Int32) -> Bytes raise {
  if chunk_size < 1 {
    raise InvalidChunkSize
  }
  let decoder = @fgb.NativeStreamDecoder::new()
  let features : Array[@fgb.NativeFeature] = []
  let mut at = 0
  while at < data.length() {
    let n = if chunk_size < data.length() - at {
      chunk_size
    } else {
      data.length() - at
    }
    let chunk = Bytes::makei(n, i => data[at + i])
    for record in decoder.push(chunk) {
      features.push(record.feature)
    }
    at += n
  }
  decoder.finish()
  @fgb.write_native_dataset({ header: decoder.header().unwrap(), features, })
}

///|
pub fn start_native_remote(bounds : String) -> @fgb.NativeRangeQuery raise {
  let bounds : @fgb.Bounds = @json.from_json(@json.parse(bounds))
  @fgb.NativeRangeQuery::new(bounds)
}

///|
pub fn next_native_remote(session : @fgb.NativeRangeQuery) -> String raise {
  match session.request() {
    None => "null"
    Some(range) => range.to_json().stringify()
  }
}

///|
pub fn accept_native_remote(
  session : @fgb.NativeRangeQuery,
  status : Int32,
  content_range : String,
  etag : String,
  bytes : Bytes,
) -> Unit raise {
  session.accept({ status, content_range, etag, body: bytes, })
}

///|
pub fn result_native_remote(session : @fgb.NativeRangeQuery) -> Bytes raise {
  @fgb.write_native_dataset(session.result())
}

///|
pub fn stats_native_remote(session : @fgb.NativeRangeQuery) -> String {
  session.stats().to_json().stringify()
}
