///|
test "stream decoder survives every one-byte boundary across indexed files" {
  let data = sample_dataset(17)
  let bytes = write_dataset(data)
  for chunk_size in [1, 2, 3, 7, 31, 128, 4096] {
    let decoder = StreamDecoder::new()
    let features : Array[Feature] = []
    let mut at = 0
    while at < bytes.length() {
      let take = if bytes.length() - at < chunk_size {
        bytes.length() - at
      } else {
        chunk_size
      }
      for record in decoder.push(slice_bytes(bytes, at, take)) {
        features.push(record.feature)
      }
      at += take
      assert_true(
        decoder.buffered_bytes() <= Limits::default().max_feature_bytes + 4,
      )
    }
    decoder.finish()
    assert_eq(features, read_dataset(bytes).features)
    assert_eq(decoder.features_decoded(), 17)
  }
}

///|
test "unknown-count streaming writer interoperates with sequential and incremental readers" {
  let dataset = sample_dataset(20)
  let writer = StreamWriter::new(dataset.header)
  let all = ByteWriter::new()
  all.bytes(writer.begin())
  for feature in dataset.features {
    all.bytes(writer.append(feature))
  }
  writer.finish()
  assert_eq(writer.features_written(), 20)
  assert_eq(writer.bytes_written(), all.position())
  assert_eq(read_dataset(all.finish()).features, dataset.features)
  let decoder = StreamDecoder::new()
  assert_eq(decoder.push(all.finish()).length(), 20)
  decoder.finish()
  assert_true(
    try {
      writer.append(dataset.features[0]) |> ignore
      false
    } catch {
      _ => true
    },
  )
}

///|
test "stream finish detects truncated magic header index and records" {
  let bytes = write_dataset(sample_dataset(3))
  for cut in [0, 1, 7, 11, 20, bytes.length() - 1] {
    let decoder = StreamDecoder::new()
    decoder.push(slice_bytes(bytes, 0, cut)) |> ignore
    assert_true(
      try {
        decoder.finish()
        false
      } catch {
        _ => true
      },
    )
    assert_true(decoder.is_failed())
  }
}

///|
test "summary preserves exact integer minima and audit reports unique violations" {
  let dataset = sample_dataset(20)
  let summary = dataset.summarize()
  assert_eq(summary.features, 20)
  assert_eq(summary.columns[0].minimum, Some("0"))
  assert_eq(summary.columns[0].maximum, Some("19"))
  let column = { ..dataset.header.columns[0], unique: true, }
  let bad : Dataset = {
    header: { ..dataset.header, columns: [column], },
    features: [dataset.features[0], dataset.features[0]],
  }
  let report = bad.validate()
  assert_false(report.valid)
  assert_eq(report.diagnostics[0].code, "duplicate_unique_value")
  assert_false(audit_archive(b"not an archive").valid)
}
