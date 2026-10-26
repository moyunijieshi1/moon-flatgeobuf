///|
test "range cache serves contained slices respects budgets and invalidates ETags" {
  let cache = RangeCache::new(8, max_entries=2)
  cache.put({ start: 10, length: 4, }, b"abcd", "\"1\"")
  assert_eq(cache.get({ start: 11, length: 2, }, "\"1\""), Some(b"bc"))
  cache.put({ start: 20, length: 4, }, b"efgh", "\"1\"")
  cache.put({ start: 30, length: 4, }, b"ijkl", "\"1\"")
  assert_eq(cache.get({ start: 10, length: 1, }, "\"1\""), None)
  assert_eq(cache.stats().evictions, 1)
  assert_eq(cache.stats().retained_bytes, 8)
  cache.put({ start: 10, length: 1, }, b"z", "\"2\"")
  assert_eq(cache.stats().retained_bytes, 1)
  assert_eq(cache.get({ start: 20, length: 1, }, "\"1\""), None)
}

///|
test "range coalescing merges overlap but obeys gap and maximum size" {
  assert_eq(
    coalesce_ranges(
      [
        { start: 30, length: 5, },
        { start: 0, length: 10, },
        { start: 8, length: 5, },
        { start: 15, length: 3, },
      ],
      2,
      20,
    ),
    [{ start: 0, length: 18, }, { start: 30, length: 5, }],
  )
}

///|
test "cache rejects partial enclosing and oversized inconsistent overlaps" {
  for (start, bytes) in [(12, b"Xdef"), (8, b"zzabXdzz"), (8, b"zzabXdefghij")] {
    let cache = RangeCache::new(8)
    cache.put({ start: 10, length: 4, }, b"abcd", "\"same\"")
    assert_true(
      try {
        cache.put({ start, length: bytes.length(), }, bytes, "\"same\"")
        false
      } catch {
        InvalidArgument(_) => true
        _ => false
      },
    )
    assert_eq(cache.stats().entries, 0)
    assert_eq(cache.stats().retained_bytes, 0)
    assert_eq(cache.get({ start: 10, length: 1, }, "\"same\""), None)
  }
}

///|
test "consistent covering cache insertion replaces entries before budget eviction" {
  let cache = RangeCache::new(8, max_entries=2)
  cache.put({ start: 10, length: 2, }, b"ab", "\"same\"")
  cache.put({ start: 14, length: 2, }, b"ef", "\"same\"")
  cache.put({ start: 10, length: 6, }, b"abcdef", "\"same\"")
  assert_eq(cache.stats().entries, 1)
  assert_eq(cache.stats().retained_bytes, 6)
  assert_eq(cache.stats().evictions, 0)
  assert_eq(cache.get({ start: 11, length: 4, }, "\"same\""), Some(b"bcde"))
  cache.put({ start: 12, length: 2, }, b"cd", "\"same\"")
  assert_eq(cache.stats().entries, 1)
  cache.put({ start: 14, length: 4, }, b"efgh", "\"same\"")
  assert_eq(cache.stats().retained_bytes, 4)
  assert_eq(cache.stats().evictions, 1)
  assert_eq(cache.get({ start: 14, length: 4, }, "\"same\""), Some(b"efgh"))
}

///|
test "cache overlap checks handle maximum address and touching endpoints" {
  let cache = RangeCache::new(4)
  cache.put({ start: 2147483646, length: 2, }, b"ab", "\"same\"")
  cache.put({ start: 2147483647, length: 1, }, b"b", "\"same\"")
  assert_eq(
    cache.get({ start: 2147483647, length: 1, }, "\"same\""),
    Some(b"b"),
  )
  assert_true(
    try {
      cache.put({ start: 2147483647, length: 1, }, b"X", "\"same\"")
      false
    } catch {
      InvalidArgument(_) => true
      _ => false
    },
  )
  let cache = RangeCache::new(8)
  cache.put({ start: 10, length: 2, }, b"ab", "\"same\"")
  cache.put({ start: 12, length: 2, }, b"cd", "\"same\"")
  assert_eq(cache.stats().entries, 2)
  cache.put({ start: 11, length: 2, }, b"bc", "\"same\"")
  assert_eq(cache.stats().entries, 3)
}

///|
test "range coalescing accepts valid maximum offsets without exclusive-end overflow" {
  assert_eq(
    coalesce_ranges(
      [
        { start: 2147483647, length: 1, },
        { start: 2147483646, length: 1, },
        { start: 2147483647, length: 1, },
      ],
      0,
      2,
    ),
    [{ start: 2147483646, length: 2, }],
  )
  assert_eq(
    coalesce_ranges(
      [{ start: 0, length: 2147483647, }, { start: 2147483647, length: 1, }],
      0,
      2147483647,
    ),
    [{ start: 0, length: 2147483647, }, { start: 2147483647, length: 1, }],
  )
}
