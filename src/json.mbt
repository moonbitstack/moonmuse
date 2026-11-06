///|
/// Reading a value out of a JSON object, and writing the small shapes every dialect
/// needs. Vendors omit fields freely, so every reader here returns `Option` rather than
/// inventing a value. They are free functions rather than methods because `Json` belongs
/// to core.

///|
/// The member at `key`, when this is an object that has it.
pub fn json_field(json : Json, key : String) -> Json? {
  match json {
    Object(map) => map.get(key)
    _ => None
  }
}

///|
/// The string at `key`, when it is a string.
pub fn json_string(json : Json, key : String) -> String? {
  match json {
    Object(map) =>
      match map.get(key) {
        Some(value) => json_as_string(value)
        None => None
      }
    _ => None
  }
}

///|
/// The number at `key`, when it is a number.
pub fn json_number(json : Json, key : String) -> Double? {
  match json {
    Object(map) =>
      match map.get(key) {
        Some(value) => json_as_number(value)
        None => None
      }
    _ => None
  }
}

///|
/// The integer at `key`, when it is a number.
pub fn json_int(json : Json, key : String) -> Int32? {
  match json_number(json, key) {
    Some(value) => Some(value.to_int())
    None => None
  }
}

///|
/// The boolean at `key`, when it is a boolean.
pub fn json_bool(json : Json, key : String) -> Bool? {
  match json {
    Object(map) =>
      match map.get(key) {
        Some(value) => json_as_bool(value)
        None => None
      }
    _ => None
  }
}

///|
/// The array at `key`, or an empty one.
pub fn json_array(json : Json, key : String) -> Array[Json] {
  match json {
    Object(map) =>
      match map.get(key) {
        Some(Array(items)) => items
        _ => []
      }
    _ => []
  }
}

///|
/// The object at `key`, or `None`.
pub fn json_object(json : Json, key : String) -> Map[String, Json]? {
  match json {
    Object(map) =>
      match map.get(key) {
        Some(Object(inner)) => Some(inner)
        _ => None
      }
    _ => None
  }
}

///|
/// The string at `key`, or `fallback`.
pub fn json_string_or(json : Json, key : String, fallback : String) -> String {
  json_string(json, key).unwrap_or(fallback)
}

///|
/// A JSON array of the strings in `items`.
pub fn strings_json(items : Array[String]) -> Json {
  Json::array(items.map(item => Json::string(item)))
}

///|
/// The strings in an array value, skipping anything that is not a string.
pub fn json_strings(value : Json) -> Array[String] {
  match value {
    Array(items) => items.filter_map(item => json_as_string(item))
    _ => []
  }
}

///|
/// A JSON array of the numbers in `values`.
pub fn numbers_json(values : Array[Double]) -> Json {
  Json::array(values.map(value => Json::number(value)))
}

///|
/// The numbers in an array value.
pub fn json_numbers(value : Json) -> Array[Double] {
  match value {
    Array(items) => items.filter_map(item => json_as_number(item))
    _ => []
  }
}

///|
/// `base` with `overrides` merged over it, key by key. `extra` reaches the wire this
/// way: a caller's field wins over the one this library wrote.
pub fn merge_json(
  base : Map[String, Json],
  overrides : Map[String, Json],
) -> Map[String, Json] {
  let merged = Map([])
  for key, value in base {
    merged[key] = value
  }
  for key, value in overrides {
    merged[key] = value
  }
  merged
}

///|
/// A JSON object from key/value pairs, in order.
pub fn object_json(fields : Array[(String, Json)]) -> Json {
  let map = Map([])
  for pair in fields {
    map[pair.0] = pair.1
  }
  Json::object(map)
}

///|
/// The text of a JSON string.
pub fn json_as_string(json : Json) -> String? {
  match json {
    String(text) => Some(text)
    _ => None
  }
}

///|
/// The value of a JSON number.
pub fn json_as_number(json : Json) -> Double? {
  match json {
    Number(value, ..) => Some(value)
    _ => None
  }
}

///|
/// The value of a JSON boolean.
pub fn json_as_bool(json : Json) -> Bool? {
  match json {
    True => Some(true)
    False => Some(false)
    _ => None
  }
}

///|
/// An integer from a decimal string, or zero. Used where a stream carries an index in a
/// text field; a vendor that sends something else should not crash the reader.
pub fn parse_int_lossy(text : String) -> Int32 {
  let mut sign = 1
  let mut value = 0
  let mut seen = false
  for char in text {
    if char == '-' && !seen {
      sign = -1
    } else if char >= '0' && char <= '9' {
      value = value * 10 + (char.to_int() - '0'.to_int())
      seen = true
    }
  }
  value * sign
}
