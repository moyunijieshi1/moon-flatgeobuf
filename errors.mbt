///|
pub suberror FgbError {
  InvalidData(Int32, String)
  Unsupported(String)
  LimitExceeded(String)
  InvalidArgument(String)
} derive(Debug)

///|
pub(all) struct Limits {
  max_header_bytes : Int32
  max_feature_bytes : Int32
  max_features : Int32
  max_columns : Int32
  max_coordinates : Int32
  max_string_bytes : Int32
  max_depth : Int32
  max_index_nodes : Int32
  max_file_bytes : Int32
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub fn Limits::default() -> Limits {
  {
    max_header_bytes: 1048576,
    max_feature_bytes: 16777216,
    max_features: 1000000,
    max_columns: 1024,
    max_coordinates: 1000000,
    max_string_bytes: 1048576,
    max_depth: 32,
    max_index_nodes: 2000000,
    max_file_bytes: 1073741824,
  }
}

///|
pub fn Limits::validate(self : Limits) -> Unit raise FgbError {
  if self.max_header_bytes < 8 || self.max_feature_bytes < 8 {
    raise InvalidArgument("buffer limits must be at least 8")
  }
  if self.max_features < 1 || self.max_columns < 1 {
    raise InvalidArgument("feature and column limits must be positive")
  }
  if self.max_columns > 65536 {
    raise InvalidArgument("column limit exceeds unsigned 16-bit keys")
  }
  if self.max_coordinates < 1 || self.max_string_bytes < 1 {
    raise InvalidArgument("coordinate and string limits must be positive")
  }
  if self.max_depth < 1 || self.max_depth > 256 {
    raise InvalidArgument("depth limit must be between 1 and 256")
  }
  if self.max_index_nodes < 1 || self.max_file_bytes < 12 {
    raise InvalidArgument("index and file limits must be positive")
  }
}

///|
fn require_range(
  data : Bytes,
  offset : Int32,
  size : Int32,
) -> Unit raise FgbError {
  if offset < 0 ||
    size < 0 ||
    offset > data.length() ||
    size > data.length() - offset {
    raise InvalidData(offset, "truncated or out-of-range buffer")
  }
}

///|
fn checked_add(a : Int32, b : Int32) -> Int32 raise FgbError {
  if a < 0 || b < 0 || a > 2147483647 - b {
    raise InvalidData(a, "offset addition overflow")
  }
  a + b
}

///|
fn checked_mul(a : Int32, b : Int32) -> Int32 raise FgbError {
  if a < 0 || b < 0 || (b != 0 && a > 2147483647 / b) {
    raise InvalidData(a, "size multiplication overflow")
  }
  a * b
}

///|
fn enforce(value : Int32, limit : Int32, name : String) -> Unit raise FgbError {
  if value > limit {
    raise LimitExceeded(name)
  }
}

///|
fn finite(value : Double) -> Bool {
  value == value && value != 1.0 / 0.0 && value != -1.0 / 0.0
}
