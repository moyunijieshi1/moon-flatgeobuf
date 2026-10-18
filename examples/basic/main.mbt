///|
fn main {
  try {
    let input = @json.parse(
      (
        #|{"type":"FeatureCollection","features":[{"type":"Feature","geometry":{"type":"Point","coordinates":[116.4,39.9]},"properties":{"name":"Beijing"}}]}
      ),
    )
    let bytes = @fgb.write_dataset(@fgb.import_geojson(input))
    let reader = @fgb.Reader::open(bytes)
    reader.validate()
    let matches = reader.query({
      min_x: 116.0,
      min_y: 39.0,
      max_x: 117.0,
      max_y: 40.0,
    })
    println("Matched features: \{matches.length()}")
  } catch {
    error => println("Example failed: \{error}")
  }
}
