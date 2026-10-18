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
