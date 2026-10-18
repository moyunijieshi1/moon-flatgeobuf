///|
struct CachedRange {
  start : Int32
  bytes : Bytes
}

///|
pub(all) struct CacheStats {
  hits : Int32
  misses : Int32
  evictions : Int32
  retained_bytes : Int32
  entries : Int32
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// A cache belongs to one resource. Switching URL requires clear(), even if ETags match.
pub struct RangeCache {
  capacity : Int32
  max_entries : Int32
  mut validator : String
  entries_ : Array[CachedRange]
  mut retained : Int32
  mut hits : Int32
  mut misses : Int32
  mut evictions : Int32
}

///|
pub fn RangeCache::new(
  capacity : Int32,
  max_entries~ : Int32 = 256,
) -> RangeCache raise FgbError {
  if capacity < 1 || max_entries < 1 {
    raise InvalidArgument("cache capacity and entry count must be positive")
  }
  {
    capacity,
    max_entries,
    validator: "",
    entries_: [],
    retained: 0,
    hits: 0,
    misses: 0,
    evictions: 0,
  }
}

///|
pub fn RangeCache::clear(self : RangeCache) -> Unit {
  self.entries_.clear()
  self.retained = 0
  self.validator = ""
}

///|
pub fn RangeCache::stats(self : RangeCache) -> CacheStats {
  {
    hits: self.hits,
    misses: self.misses,
    evictions: self.evictions,
    retained_bytes: self.retained,
    entries: self.entries_.length(),
  }
}

///|
pub fn RangeCache::get(
  self : RangeCache,
  range : ByteRange,
  etag : String,
) -> Bytes? raise FgbError {
  range.end_inclusive() |> ignore
  if etag.is_empty() || self.validator != etag {
    self.misses += 1
    return None
  }
  for entry in self.entries_ {
    if range.start >= entry.start {
      let relative = range.start - entry.start
      if relative <= entry.bytes.length() &&
        range.length <= entry.bytes.length() - relative {
        self.hits += 1
        return Some(slice_bytes(entry.bytes, relative, range.length))
      }
    }
  }
  self.misses += 1
  None
}

///|
pub fn RangeCache::put(
  self : RangeCache,
  range : ByteRange,
  bytes : Bytes,
  etag : String,
) -> Unit raise FgbError {
  range.end_inclusive() |> ignore
  if range.length != bytes.length() {
    raise InvalidArgument("cache range length differs from bytes")
  }
  if etag.is_empty() || etag.has_prefix("W/") {
    raise InvalidArgument("cache requires a strong ETag")
  }
  if self.validator != etag {
    self.clear()
    self.validator = etag
  }
  if bytes.length() > self.capacity {
    return
  }
  // Do not retain duplicate subranges or arrays owned by callers.
  for entry in self.entries_ {
    let relative = range.start - entry.start
    if relative >= 0 &&
      relative <= entry.bytes.length() &&
      range.length <= entry.bytes.length() - relative {
      let previous = slice_bytes(entry.bytes, relative, range.length)
      if previous != bytes {
        self.clear()
        raise InvalidArgument("same ETag returned inconsistent range bytes")
      }
      return
    }
  }
  while self.entries_.length() >= self.max_entries ||
        self.retained > self.capacity - bytes.length() {
    let oldest = self.entries_.remove(0)
    self.retained -= oldest.bytes.length()
    self.evictions += 1
  }
  self.entries_.push({
    start: range.start,
    bytes: slice_bytes(bytes, 0, bytes.length()),
  })
  self.retained += bytes.length()
}

///|
/// Coalesce requested intervals without exceeding a caller-chosen transfer size.
pub fn coalesce_ranges(
  ranges : Array[ByteRange],
  max_gap : Int32,
  max_length : Int32,
) -> Array[ByteRange] raise FgbError {
  if max_gap < 0 || max_length < 1 {
    raise InvalidArgument("invalid range coalescing policy")
  }
  let sorted = ranges.copy()
  for range in sorted {
    range.end_inclusive() |> ignore
    if range.length > max_length {
      raise InvalidArgument("input range exceeds maximum coalesced length")
    }
  }
  sorted.sort_by((a, b) => {
    let order = a.start.compare(b.start)
    if order == 0 {
      a.length.compare(b.length)
    } else {
      order
    }
  })
  let result : Array[ByteRange] = []
  for range in sorted {
    if result.is_empty() {
      result.push(range)
      continue
    }
    let last = result[result.length() - 1]
    let last_end = checked_add(last.start, last.length)
    let end = checked_add(range.start, range.length)
    let union_end = if end > last_end { end } else { last_end }
    let gap = if range.start > last_end { range.start - last_end } else { 0 }
    if gap <= max_gap && union_end - last.start <= max_length {
      result[result.length() - 1] = {
        start: last.start,
        length: union_end - last.start,
      }
    } else {
      result.push(range)
    }
  }
  result
}
