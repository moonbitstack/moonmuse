///|
/// Asking for an answer that fits a schema. The schema is stated to the model in the prompt
/// and checked against the reply; a reply that does not fit is sent back with the failure,
/// up to a budget, which is the repair loop a typed language gets from its deserializer.

///|
/// The first balanced JSON object in `text`. Models wrap answers in prose or a code fence
/// often enough that requiring a bare object would fail more calls than it catches; string
/// literals and escapes are respected, so a brace inside a string does not end the object.
pub fn extract_object(text : String) -> String? {
  let length = text.length()
  let mut start = -1
  for i = 0; i < length; i = i + 1 {
    if text.get_char(i) == Some('{') {
      start = i
      break
    }
  }
  if start < 0 {
    return None
  }
  let mut depth = 0
  let mut quoted = false
  let mut escaped = false
  for i = start; i < length; i = i + 1 {
    let char = text.get_char(i).unwrap_or('\u{0}')
    if quoted {
      if escaped {
        escaped = false
      } else if char == '\\' {
        escaped = true
      } else if char == '"' {
        quoted = false
      }
    } else if char == '"' {
      quoted = true
    } else if char == '{' {
      depth = depth + 1
    } else if char == '}' {
      depth = depth - 1
      if depth == 0 {
        return Some(text.exact_view(start~, end=i + 1).to_owned())
      }
    }
  }
  None
}

///|
/// The instruction that pins a reply to a schema.
pub fn instruction(name : String, schema : Json) -> String {
  "Reply with one JSON object and nothing else, matching this schema named \"" +
  name +
  "\": " +
  @json.dumps(schema)
}

///|
/// The follow-up when a reply did not fit: the failure, then the same request.
pub fn repair(failure : String) -> String {
  "That reply was rejected: " +
  failure +
  " Reply again with only the JSON object."
}

///|
/// Ask until the reply fits `schema` and `decode` accepts it, at most `fixes` repairs.
/// Raises `Decode` with the last failure when the budget runs out, so a caller sees why the
/// answer was refused instead of a silent `None`.
pub async fn[T] ask(
  provider : &@moonmuse.Provider,
  request : @moonmuse.Request,
  name~ : String,
  schema~ : Json,
  decode~ : (Json) -> T?,
  fixes~ : Int32 = 2,
) -> T raise @moonmuse.LlmError {
  let checker = @moonschema.Schema::new(schema) catch {
    error =>
      raise @moonmuse.Decode(
        "the schema itself is invalid: " + error.to_string(),
      )
  }
  let mut current = request.push(
    @moonmuse.Message::system(instruction(name, schema)),
  )
  let mut failure = "no reply yet"
  for attempt = 0; attempt <= fixes; attempt = attempt + 1 {
    let reply = provider.chat(current)
    let text = reply.text()
    let candidate = match extract_object(text) {
      Some(json) => @moonmuse.parse_json_lossy(json)
      None => Json::null()
    }
    let faults = checker.faults(candidate)
    if faults.is_empty() {
      match decode(candidate) {
        Some(value) => return value
        None => failure = "the object did not decode"
      }
    } else {
      let messages = []
      for fault in faults {
        messages.push(fault.to_string())
      }
      failure = messages.join("; ")
    }
    current = current.push(reply.message)
    current = current.push(@moonmuse.Message::user(repair(failure)))
  }
  raise @moonmuse.Decode(
    "no reply fitted the schema after " +
    (fixes + 1).to_string() +
    " attempts: " +
    failure,
  )
}
