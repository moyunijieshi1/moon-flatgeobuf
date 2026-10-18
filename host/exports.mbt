///|
pub fn encode(text : String, indexed : Bool) -> Bytes raise {
  let input = @json.parse(text)
  let dataset = @fgb.import_geojson(input)
  @fgb.write_dataset(dataset, options={ index_node_size: if indexed { 16 } else { 0 }, hilbert_sort: indexed })
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
  let dataset : @fgb.Dataset = { header: reader.header(), features: records.map(r => r.feature) }
  dataset.to_geojson().stringify()
}

///|
pub fn audit(data : Bytes) -> String raise {
  let reader = @fgb.Reader::open(data)
  reader.validate()
  "ok"
}
