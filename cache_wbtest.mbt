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
