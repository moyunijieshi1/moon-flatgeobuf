///|
fn run() -> Unit raise Error {
  let geometry = {
    ..@fgb.NativeGeometry::new(8),
    xy: Some([{ x: 0.0, y: 0.0, }, { x: 1.0, y: 2.0, }, { x: 2.0, y: 0.0, }]),
    z: Some([10.0, 20.0, 30.0]),
    m: Some([0.0, 5.0, 10.0]),
    t: Some([2026.5, 2026.6, 2026.7]),
    tm: Some([0UL, 9007199254740993UL, 18446744073709551615UL]),
  }
  let header = {
    ..@fgb.NativeHeader::new(8),
    has_z: true,
    has_m: true,
    has_t: true,
    has_tm: true,
    features_count: 1,
    index_node_size: 16,
  }
  let feature : @fgb.NativeFeature = {
    geometry: Some(geometry),
    properties: [@fgb.Text("arc")],
    columns: Some([@fgb.NativeColumn::new("name", 11)]),
  }
  let bytes = @fgb.write_native_dataset({ header, features: [feature], })
  let reader = @fgb.NativeReader::open(bytes)
  reader.validate()
  let hits = reader.query({ min_x: 2.1, min_y: 0.0, max_x: 2.2, max_y: 2.0, })
  if hits.length() != 1 || hits[0].feature != feature {
    abort("native example did not preserve geometry and schema")
  }
  println(
    "CircularString with Z/M/T/TM and local schema: one preserved feature",
  )
}

///|
fn main {
  run() catch {
    error => abort(@debug.to_string(error))
  }
}
