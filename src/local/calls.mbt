///|
/// Reading tool calls out of text. A local model has no `tool_calls` field to fill: its whole
/// answer is one string, and a call is a JSON object inside it, wrapped in whichever tags the
/// model was trained on. Which tags is a property of the model, so it is a value here.

///|
/// How a model writes a tool call.
#derive(Eq, Debug)
pub(all) enum Calls {
  /// `<tool_call>{"name": "add", "arguments": {"a": 2}}</tool_call>` — Qwen, Hermes and the
  /// models trained on their format.
  Tagged
  /// A fenced code block holding the call object.
  Fenced
  /// A bare JSON object in the answer, recognised by its `name`.
  Bare
}

///|
/// An answer split into what is text and what is a call.
pub struct Parsed {
  /// The answer with the call regions removed, trimmed.
  text : String
  /// The calls, in the order they appeared.
  calls : Array[@moonmuse.Part]
}

///|
/// The text and calls of an answer written in `calls` style. Call ids are `call_0`, `call_1`,
/// by position: a local model does not invent ids, and a caller needs something to match the
/// results it sends back.
pub fn parse(text : String, calls~ : Calls = Tagged) -> Parsed {
  let regions = match calls {
    Tagged => tagged_regions(text)
    Fenced => fenced_regions(text)
    Bare => bare_regions(text)
  }
  let parts = []
  let kept = StringBuilder()
  let mut last = 0
  for region in regions {
    let (start, end) = region
    if start > last {
      kept.write_string(text.exact_view(start=last, end=start).to_owned())
    }
    for found in calls_in(text.exact_view(start~, end~).to_owned()) {
      parts.push(
        @moonmuse.Part::call(
          "call_" + parts.length().to_string(),
          found.0,
          found.1,
        ),
      )
    }
    last = end
  }
  if last < text.length() {
    kept.write_string(text.exact_view(start=last).to_owned())
  }
  { text: kept.to_string().trim().to_owned(), calls: parts, }
}

///|
/// `needle` at or after `from`, as a byte offset into `text`.
fn find_from(text : String, needle : StringView, from : Int32) -> Int32? {
  if from >= text.length() {
    return None
  }
  match text.exact_view(start=from).to_owned().find(needle) {
    Some(index) => Some(index + from)
    None => None
  }
}

///|
/// The `(start, end)` byte ranges of every `<tool_call>` element.
fn tagged_regions(text : String) -> Array[(Int32, Int32)] {
  let out = []
  let open = "<tool_call>"
  let close = "</tool_call>"
  let mut at = 0
  while at < text.length() {
    let start = match find_from(text, open, at) {
      Some(index) => index
      None => break
    }
    let body_start = start + open.length()
    let end = match find_from(text, close, body_start) {
      Some(index) => index + close.length()
      None => break
    }
    out.push((start, end))
    at = end
  }
  out
}

///|
/// The ranges of every fenced block that holds a JSON object.
fn fenced_regions(text : String) -> Array[(Int32, Int32)] {
  let out = []
  let mut at = 0
  while at < text.length() {
    let start = match find_from(text, "```", at) {
      Some(index) => index
      None => break
    }
    let end = match find_from(text, "```", start + 3) {
      Some(index) => index + 3
      None => break
    }
    let body = text.exact_view(start~, end~).to_owned()
    if body.contains("{") {
      out.push((start, end))
    }
    at = end
  }
  out
}

///|
/// The ranges of every balanced JSON object that carries a call.
fn bare_regions(text : String) -> Array[(Int32, Int32)] {
  let out = []
  for region in object_regions(text) {
    let body = text.exact_view(start=region.0, end=region.1).to_owned()
    if !calls_in(body).is_empty() {
      out.push(region)
    }
  }
  out
}

///|
/// Every balanced `{...}` range in `text`, respecting string literals and escapes.
fn object_regions(text : String) -> Array[(Int32, Int32)] {
  let out = []
  let length = text.length()
  let mut i = 0
  while i < length {
    if text.get_char(i) == Some('{') {
      let mut depth = 0
      let mut quoted = false
      let mut escaped = false
      let mut end = -1
      for j = i; j < length; j = j + 1 {
        let char = text.get_char(j).unwrap_or('\u{0}')
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
            end = j + 1
            break
          }
        }
      }
      if end > 0 {
        out.push((i, end))
        i = end
        continue
      }
    }
    i = i + 1
  }
  out
}

///|
/// The calls inside one region, as name and arguments. The JSON may be one object or an array
/// of them, and may be wrapped in a code fence.
fn calls_in(body : String) -> Array[(String, Json)] {
  let text = strip_fence(body)
  let json = @moonmuse.parse_json_lossy(text)
  let items = match json {
    Array(items) => items
    Object(_) => [json]
    _ => []
  }
  let out = []
  for item in items {
    match call_of(item) {
      Some(found) => out.push(found)
      None => ()
    }
  }
  out
}

///|
/// One call object as name and arguments. The name is `name` or `tool`; the arguments are
/// `arguments`, `args` or `parameters`, either an object or a JSON string holding one. A model
/// that writes something else produces no call rather than a call with invented arguments.
fn call_of(item : Json) -> (String, Json)? {
  let name = match @moonmuse.json_string(item, "name") {
    Some(name) => name
    None =>
      match @moonmuse.json_string(item, "tool") {
        Some(name) => name
        None => return None
      }
  }
  if name == "" {
    return None
  }
  let raw = match @moonmuse.json_field(item, "arguments") {
    Some(value) => value
    None =>
      match @moonmuse.json_field(item, "args") {
        Some(value) => value
        None =>
          @moonmuse.json_field(item, "parameters").unwrap_or(
            Json::object(Map([])),
          )
      }
  }
  let args = match raw {
    String(text) => @moonmuse.parse_json_lossy(text)
    other => other
  }
  Some((name, args))
}

///|
/// The inside of a fenced block or a tagged element: the fence, its language tag and the
/// `<tool_call>` wrapper are not JSON and are not part of the call.
fn strip_fence(body : String) -> String {
  let mut text = body.trim().to_owned()
  if text.has_prefix("<tool_call>") {
    text = text.exact_view(start=11).to_owned()
  }
  if text.has_suffix("</tool_call>") {
    text = text.exact_view(start=0, end=text.length() - 12).to_owned()
  }
  let text = text.trim().to_owned()
  if !text.has_prefix("```") {
    return text
  }
  let after = text.exact_view(start=3).to_owned()
  let mut index = 0
  while index < after.length() && after.get_char(index) != Some('\n') {
    index = index + 1
  }
  if index >= after.length() {
    return ""
  }
  let inner = after.exact_view(start=index + 1).to_owned()
  if inner.has_suffix("```") {
    inner
    .exact_view(start=0, end=inner.length() - 3)
    .to_owned()
    .trim()
    .to_owned()
  } else {
    inner.trim().to_owned()
  }
}

///|
pub extend Calls with Eq::{not_equal, equal}

///|
pub extend Calls with Debug::{to_repr}
