///|
fn feed_range_session(
  session : RangeQuery,
  bytes : Bytes,
) -> Dataset raise FgbError {
  let mut iterations = 0
  while session.request() is Some(request) {
    iterations += 1
    if iterations > 10000 {
      raise InvalidArgument("test session did not terminate")
    }
    let body = slice_bytes(bytes, request.start, request.length)
    session.accept({
      status: 206,
      body,
      etag: "\"fixed-v1\"",
      content_range: "bytes \{request.start}-\{request.end_inclusive()}/\{bytes.length()}",
    })
  }
  session.result()
}

///|
test "remote indexed query reads only candidate subtrees and feature bytes" {
  let bytes = write_dataset(sample_dataset(1000))
  let bounds : Bounds = { min_x: 100.0, min_y: 0.0, max_x: 110.0, max_y: 6.0, }
  let session = RangeQuery::new(bounds)
  let d = feed_range_session(session, bytes)
  assert_eq(d.features.length(), 11)
  assert_true(session.is_complete())
  assert_true(session.stats().received_bytes < bytes.length() / 4)
  assert_eq(session.stats().features_decoded, 11)
  assert_eq(session.stats().matched, 11)
  assert_true(session.stats().index_nodes < 200)
}

///|
test "remote sequential fallback empty file and singleton match full read" {
  for count in [0, 1, 40] {
    for node_size in [0, 16] {
      let bytes = write_dataset(sample_dataset(count), options={
        index_node_size: node_size,
        hilbert_sort: true,
      })
      let bounds : Bounds = {
        min_x: -1.0,
        min_y: -1.0,
        max_x: 100.0,
        max_y: 100.0,
      }
      let session = RangeQuery::new(bounds)
      assert_eq(feed_range_session(session, bytes).features.length(), count)
    }
  }
}

///|
test "range response checks reject 200 short bodies stale objects and weak validators" {
  let bounds : Bounds = { min_x: 0.0, min_y: 0.0, max_x: 1.0, max_y: 1.0, }
  let bytes = write_dataset(sample_dataset(1))
  let prefix = slice_bytes(bytes, 0, 12)
  for
    (status, content_range, etag, body) in [
      (200, "bytes 0-11/1000", "\"v1\"", prefix),
      (206, "bytes 1-12/1000", "\"v1\"", prefix),
      (206, "bytes 0-11/1000", "W/\"v1\"", prefix),
      (206, "bytes 0-11/1000", "\"v1\"", b"short"),
    ] {
    let session = RangeQuery::new(bounds)
    assert_true(
      try {
        session.accept({ status, content_range, etag, body, })
        false
      } catch {
        _ => true
      },
    )
    assert_true(session.is_failed())
  }
  let session = RangeQuery::new(bounds)
  session.accept({
    status: 206,
    content_range: "bytes 0-11/\{bytes.length()}",
    etag: "\"v1\"",
    body: prefix,
  })
  let request = session.request().unwrap()
  assert_true(
    try {
      session.accept({
        status: 206,
        content_range: "bytes \{request.start}-\{request.end_inclusive()}/\{bytes.length()}",
        etag: "\"v2\"",
        body: slice_bytes(bytes, request.start, request.length),
      })
      false
    } catch {
      _ => true
    },
  )
}

///|
test "Content-Range parser rejects wildcards negative and overflowing lengths" {
  for
    text in [
      "bytes */100", "bytes -1-2/10", "items 0-2/3", "bytes 0-3/3", "bytes 0-2/999999999999999999999",
    ] {
    assert_true(
      try {
        parse_content_range(text) |> ignore
        false
      } catch {
        _ => true
      },
    )
  }
  assert_eq(parse_content_range("bytes 2-4/100"), {
    start: 2,
    end_inclusive: 4,
    total: 100,
  })
}
