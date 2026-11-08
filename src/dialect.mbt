///|
/// One HTTP request a dialect produced from a `Request` — verb, path, headers, body.
/// A client only has to send it; nothing in it is provider-specific beyond what the
/// dialect already decided.
#derive(Eq, Debug)
pub(all) struct Call {
  verb : String
  path : String
  headers : Array[(String, String)]
  body : Json
  /// The query string, in the order the endpoint expects it. A streamed Gemini call
  /// asks for events with `alt=sse`, which is a query parameter and nothing else.
  query : Array[(String, String)]
  /// A body that is not JSON: audio, a file, a multipart form. When present it is sent
  /// as it stands and `body` is ignored.
  payload : Bytes?
}

///|
/// A call with the provider's JSON content type and no extra header.
pub fn Call::new(verb : String, path : String, body : Json) -> Call {
  {
    verb,
    path,
    headers: [("content-type", "application/json")],
    body,
    query: [],
    payload: None,
  }
}

///|
/// A call whose body is bytes rather than JSON: speech, a file, a form.
pub fn Call::bytes(
  verb : String,
  path : String,
  content_type : String,
  data : Bytes,
) -> Call {
  {
    verb,
    path,
    headers: [("content-type", content_type)],
    body: Json::null(),
    query: [],
    payload: Some(data),
  }
}

///|
/// A copy with a header set, replacing any previous value of the same name.
pub fn Call::header(self : Call, name : String, value : String) -> Call {
  let headers = self.headers.filter(pair => pair.0 != name)
  { ..self, headers: [..headers, (name, value)], }
}

///|
/// A copy with a query parameter appended.
pub fn Call::query(self : Call, name : String, value : String) -> Call {
  { ..self, query: [..self.query, (name, value)], }
}

///|
/// A copy that asks the endpoint to stream: the same body with `stream` set true. Every
/// format this library speaks spells that field the same way, and a streamed request is
/// otherwise the request it would have been.
pub fn Call::streaming(self : Call) -> Call {
  let body = match self.body {
    Object(fields) => {
      let copy = Map([])
      for key, value in fields {
        copy[key] = value
      }
      copy["stream"] = Json::boolean(true)
      Json::object(copy)
    }
    other => other
  }
  { ..self, body, }
}

///|
/// A copy of the body with one field added or replaced.
pub fn Call::field(self : Call, name : String, value : Json) -> Call {
  let body = match self.body {
    Object(fields) => {
      let copy = Map([])
      for key, existing in fields {
        copy[key] = existing
      }
      copy[name] = value
      Json::object(copy)
    }
    _ => Json::object(Map([]))
  }
  { ..self, body, }
}

///|
/// One frame of a streamed response: the server-sent-events `event` name when the
/// endpoint uses named events, and the payload. JSON endpoints that stream newline
/// delimited objects leave `event` empty.
#derive(Eq, Debug)
pub(all) struct Frame {
  event : String?
  data : String
}

///|
/// A frame with no event name.
pub fn Frame::new(data : String) -> Frame {
  { event: None, data, }
}

///|
/// A named frame.
pub fn Frame::named(event : String, data : String) -> Frame {
  { event: Some(event), data, }
}

///|
/// The frame's payload as JSON, or `Decode` when it is not JSON.
pub fn Frame::json(self : Frame) -> Json raise LlmError {
  @json.parse(self.data) catch {
    _ => raise Decode("frame is not JSON: " + self.data)
  }
}

///|
/// State carried across the frames of one streamed answer. Vendors number content
/// blocks differently — OpenAI by tool-call index, Anthropic by block ordinal, Gemini
/// by part ordinal — so the dialect keeps the counters here instead of in the client,
/// and the same `Turn` serves the client reading a stream and the server writing one.
pub struct Turn {
  /// How many frames have been consumed or produced.
  mut seq : Int32
  /// The ordinal of the next content block.
  mut block : Int32
  /// Per-vendor scratch: a tool-call index to its id, a block ordinal to its kind.
  slots : Map[String, String]
  /// Numeric scratch: a running count, a tool-call index.
  nums : Map[String, Int32]
}

///|
/// A fresh stream state.
pub fn Turn::new() -> Turn {
  { seq: 0, block: 0, slots: Map([]), nums: Map([]), }
}

///|
/// Count one frame and return its ordinal.
pub fn Turn::tick(self : Turn) -> Int32 {
  let current = self.seq
  self.seq = self.seq + 1
  current
}

///|
/// Take the next content-block ordinal.
pub fn Turn::next_block(self : Turn) -> Int32 {
  let current = self.block
  self.block = self.block + 1
  current
}

///|
/// A scratch value, or the empty string.
pub fn Turn::slot(self : Turn, key : String) -> String {
  self.slots.get(key).unwrap_or("")
}

///|
/// Record a scratch value.
pub fn Turn::set_slot(self : Turn, key : String, value : String) -> Unit {
  self.slots[key] = value
}

///|
/// Append to a scratch value.
pub fn Turn::add_slot(self : Turn, key : String, chunk : String) -> Unit {
  self.slots[key] = self.slots.get(key).unwrap_or("") + chunk
}

///|
/// Whether a scratch value was recorded.
pub fn Turn::has_slot(self : Turn, key : String) -> Bool {
  self.slots.contains(key)
}

///|
/// A numeric scratch value, or zero.
pub fn Turn::num(self : Turn, key : String) -> Int32 {
  self.nums.get(key).unwrap_or(0)
}

///|
/// Set a numeric scratch value.
pub fn Turn::set_num(self : Turn, key : String, value : Int32) -> Unit {
  self.nums[key] = value
}

///|
/// Add to a numeric scratch value and return the new total.
pub fn Turn::add_num(self : Turn, key : String, delta : Int32) -> Int32 {
  let value = self.num(key) + delta
  self.nums[key] = value
  value
}

///|
/// The kinds of endpoint a dialect can both call and serve.
#derive(Eq, Debug)
pub(all) enum RouteKind {
  Chat
  Complete
  Responses
  Embed
  Models
  Count
  Show
  Version
  Generate
}

///|
/// One endpoint a dialect serves. `path` may contain a single `*`, which matches any
/// run of characters — Gemini puts the model inside the path.
#derive(Eq, Debug)
pub(all) struct Route {
  kind : RouteKind
  verb : String
  path : String
}

///|
/// A route for a verb and a path pattern.
pub fn Route::new(kind : RouteKind, verb : String, path : String) -> Route {
  { kind, verb, path, }
}

///|
/// Whether this route answers `verb` at `path`.
pub fn Route::matches(self : Route, verb : String, path : String) -> Bool {
  if self.verb != verb {
    return false
  }
  match self.path.find("*") {
    None => self.path == path
    Some(at) => {
      let prefix = self.path.exact_view(start=0, end=at)
      let suffix = self.path.exact_view(start=at + 1)
      path.length() >= prefix.length() + suffix.length() &&
      path.has_prefix(prefix) &&
      path.has_suffix(suffix)
    }
  }
}

///|
/// What a server-side request asked for, decoded into the shared vocabulary.
#derive(Eq, Debug)
pub(all) enum Asked {
  Chat(Request)
  Embed(model~ : String, inputs~ : Array[String])
  Models
  Count(Request)
}

///|
/// One vendor's wire format, read and written in the same place. The client half turns
/// a `Request` into a `Call` and a body into a `Reply`; the server half turns a body
/// into a `Request` and a `Reply` into a body. Because both halves live here, a gateway
/// that speaks a format out cannot drift from the client that speaks it in.
pub(open) trait Dialect {
  /// The format's name, for diagnostics and for telling two formats apart when they share a
  /// path.
  fn name(Self) -> String
  /// The HTTP call that asks for this request.
  fn request(Self, Request) -> Call raise LlmError
  /// The reply a response body describes.
  fn reply(Self, status : Int32, body : Json) -> Reply raise LlmError
  /// The deltas one streamed frame carries.
  fn delta(Self, Frame, Turn) -> Array[Delta] raise LlmError
  /// The endpoints this dialect serves.
  fn routes(Self) -> Array[Route]
  /// The request a served body describes.
  fn parse(Self, Route, Json) -> Asked raise LlmError
  /// The body that answers a reply.
  fn answer(Self, Reply) -> Json
  /// The body that answers an embeddings request. Kept apart from `answer` because the
  /// five endpoints do not share a response shape.
  fn answer_embed(Self, String, Array[Array[Double]]) -> Json
  /// The body that answers a token-count request.
  fn answer_count(Self, Reply) -> Json
  /// The body that answers a model list.
  fn answer_models(Self, Array[ModelInfo]) -> Json
  /// The body that answers a reply at a particular endpoint. Most formats answer every
  /// endpoint the same way; the OpenAI one has three shapes.
  fn answer_at(Self, RouteKind, Reply) -> Json
  /// The frames that carry one delta out.
  fn frame(Self, Delta, Turn) -> Array[Frame]
  /// The status and body for an error.
  fn error(Self, LlmError) -> (Int32, Json)
}

///|
pub extend Call with Eq::{not_equal, equal}

///|
pub extend Call with Debug::{to_repr}

///|
pub extend Frame with Eq::{not_equal, equal}

///|
pub extend Frame with Debug::{to_repr}

///|
pub extend RouteKind with Eq::{not_equal, equal}

///|
pub extend RouteKind with Debug::{to_repr}

///|
pub extend Route with Eq::{not_equal, equal}

///|
pub extend Route with Debug::{to_repr}

///|
pub extend Asked with Eq::{not_equal, equal}

///|
pub extend Asked with Debug::{to_repr}
