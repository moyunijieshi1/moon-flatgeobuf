///|
pub(all) struct IndexLevel {
  start : Int32
  end : Int32
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub(all) struct IndexNode {
  bounds : Bounds
  offset : Int32
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub(all) struct IndexHit {
  ordinal : Int32
  offset : Int32
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub fn index_levels(
  count : Int32,
  node_size : Int32,
  limits~ : Limits = Limits::default(),
) -> Array[IndexLevel] raise FgbError {
  if count < 1 || node_size < 2 || node_size > 65535 {
    raise InvalidArgument(
      "index requires count > 0 and node size between 2 and 65535",
    )
  }
  enforce(count, limits.max_features, "index features")
  let counts = [count]
  let mut total = count
  let mut n = count
  // The format stores a parent even for a single feature.
  while true {
    n = n / node_size + (if n % node_size == 0 { 0 } else { 1 })
    counts.push(n)
    total = checked_add(total, n)
    enforce(total, limits.max_index_nodes, "index nodes")
    if n == 1 {
      break
    }
  }
  let levels : Array[IndexLevel] = []
  let mut end = total
  for size in counts {
    levels.push({ start: end - size, end, })
    end -= size
  }
  levels
}

///|
pub fn index_byte_length(
  count : Int32,
  node_size : Int32,
  limits~ : Limits = Limits::default(),
) -> Int32 raise FgbError {
  if node_size == 0 {
    return 0
  }
  let levels = index_levels(count, node_size, limits~)
  checked_mul(levels[0].end, 40)
}

///|
pub fn decode_index_node(
  data : Bytes,
  node : Int32,
) -> IndexNode raise FgbError {
  let at = checked_mul(node, 40)
  require_range(data, at, 40)
  let bounds : Bounds = {
    min_x: f64(data, at),
    min_y: f64(data, at + 8),
    max_x: f64(data, at + 16),
    max_y: f64(data, at + 24),
  }
  bounds.validate()
  { bounds, offset: size64(data, at + 32), }
}

///|
pub fn query_index(
  data : Bytes,
  count : Int32,
  node_size : Int32,
  query : Bounds,
  limits~ : Limits = Limits::default(),
) -> Array[IndexHit] raise FgbError {
  query.validate()
  let levels = index_levels(count, node_size, limits~)
  let size = checked_mul(levels[0].end, 40)
  if data.length() != size {
    raise InvalidData(0, "index byte length differs from header")
  }
  let pending : Array[(Int32, Int32)] = [(0, levels.length() - 1)]
  let hits : Array[IndexHit] = []
  let mut cursor = 0
  while cursor < pending.length() {
    let (node_number, level_number) = pending[cursor]
    cursor += 1
    let level = levels[level_number]
    if node_number < level.start || node_number >= level.end {
      raise InvalidData(
        node_number * 40,
        "index child points outside its level",
      )
    }
    let node = decode_index_node(data, node_number)
    if !node.bounds.intersects(query) {
      continue
    }
    if level_number == 0 {
      hits.push({ ordinal: node_number - level.start, offset: node.offset, })
    } else {
      let children = levels[level_number - 1]
      let expected = children.start + (node_number - level.start) * node_size
      if node.offset != expected {
        raise InvalidData(
          node_number * 40 + 32,
          "invalid packed index child offset",
        )
      }
      let stop = if node_size > children.end - node.offset {
        children.end
      } else {
        node.offset + node_size
      }
      for child in node.offset..<stop {
        pending.push((child, level_number - 1))
      }
    }
  }
  hits
}

///|
pub fn validate_index(
  data : Bytes,
  count : Int32,
  node_size : Int32,
  feature_bytes : Int32,
  limits~ : Limits = Limits::default(),
) -> Unit raise FgbError {
  let levels = index_levels(count, node_size, limits~)
  let expected_bytes = checked_mul(levels[0].end, 40)
  if data.length() != expected_bytes {
    raise InvalidData(0, "index byte length mismatch")
  }
  let mut previous = -1
  for i in levels[0].start..<levels[0].end {
    let node = decode_index_node(data, i)
    if node.offset <= previous || node.offset >= feature_bytes {
      raise InvalidData(
        i * 40 + 32,
        "non-increasing or out-of-range feature offset",
      )
    }
    if i == levels[0].start && node.offset != 0 {
      raise InvalidData(i * 40 + 32, "first feature offset must be zero")
    }
    previous = node.offset
  }
  for level_number in 1..<levels.length() {
    let level = levels[level_number]
    let children = levels[level_number - 1]
    for i in level.start..<level.end {
      let parent = decode_index_node(data, i)
      let first = children.start + (i - level.start) * node_size
      if parent.offset != first {
        raise InvalidData(i * 40 + 32, "incorrect packed child offset")
      }
      let stop = if node_size > children.end - first {
        children.end
      } else {
        first + node_size
      }
      for child in first..<stop {
        if !parent.bounds.contains(decode_index_node(data, child).bounds) {
          raise InvalidData(i * 40, "parent bounds do not enclose child")
        }
      }
    }
  }
}
