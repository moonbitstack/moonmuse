///|
/// Why generation stopped, in the four cases worth branching on plus a catch-all for
/// a vendor's own reason string.
#derive(Eq, Debug)
pub(all) enum Finish {
  /// The model finished its answer.
  Stop
  /// A token limit cut the answer short.
  Length
  /// The model wants a tool called.
  Calls
  /// A content filter blocked the answer.
  Filtered
  /// Anything else, kept verbatim.
  Other(String)
}

///|
/// The `Finish` a vendor's reason string names. Shared by the four dialects, which
/// differ in spelling but not in meaning.
pub fn Finish::of(reason : String) -> Finish {
  match reason {
    "stop" | "end_turn" | "stop_sequence" | "STOP" | "eos_token" => Stop
    "length" | "max_tokens" | "MAX_TOKENS" | "max_output_tokens" => Length
    "tool_calls" | "function_call" | "tool_use" | "TOOL_CALLS" => Calls
    "content_filter" | "safety" | "SAFETY" | "refusal" => Filtered
    other => Other(other)
  }
}

///|
/// What a call cost. `None` means the provider reported nothing; a zero would claim
/// the call was free.
#derive(Eq, Debug)
pub(all) struct Usage {
  input : Int32?
  output : Int32?
  cached : Int32?
}

///|
/// Usage with nothing reported.
pub fn Usage::zero() -> Usage {
  { input: None, output: None, cached: None, }
}

///|
/// Usage with both counts known and no cache report.
pub fn Usage::new(input : Int32, output : Int32, cached? : Int32) -> Usage {
  { input: Some(input), output: Some(output), cached, }
}

///|
/// Input plus output, when both were reported.
pub fn Usage::total(self : Usage) -> Int32? {
  match (self.input, self.output) {
    (Some(input), Some(output)) => Some(input + output)
    _ => None
  }
}

///|
/// A model's answer: the assistant message, why it stopped, what it cost, and the
/// response body as it arrived, for fields the shared vocabulary does not model.
#derive(Eq, Debug)
pub(all) struct Reply {
  message : Message
  finish : Finish
  usage : Usage
  raw : Json
}

///|
/// A reply from an assistant message.
pub fn Reply::new(
  message : Message,
  finish~ : Finish = Stop,
  usage~ : Usage = Usage::zero(),
  raw~ : Json = Json::null(),
) -> Reply {
  { message, finish, usage, raw, }
}

///|
/// The reply's text.
pub fn Reply::text(self : Reply) -> String {
  self.message.text_content()
}

///|
/// The reply's tool calls.
pub fn Reply::calls(self : Reply) -> Array[Part] {
  self.message.calls()
}

///|
/// One event of a streamed answer. `Done` closes it with the assembled reply, so a
/// caller that ignores the deltas still gets the same value as a non-streamed call.
#derive(Eq, Debug)
pub(all) enum Delta {
  Text(String)
  CallStart(id~ : String, name~ : String)
  CallArgs(id~ : String, chunk~ : String)
  Done(Reply)
}

///|
/// Assembles deltas into the reply they describe. Text accumulates in arrival order,
/// argument fragments accumulate per call, and the `Done` reply wins when present.
pub struct Assembly {
  mut text : String
  order : Array[String]
  names : Map[String, String]
  args : Map[String, String]
  mut done : Reply?
}

///|
/// An empty assembly.
pub fn Assembly::new() -> Assembly {
  { text: "", order: [], names: Map([]), args: Map([]), done: None, }
}

///|
/// Feed one delta in.
pub fn Assembly::push(self : Assembly, delta : Delta) -> Unit {
  match delta {
    Text(chunk) => self.text = self.text + chunk
    CallStart(id~, name~) => {
      if !self.names.contains(id) {
        self.order.push(id)
      }
      self.names[id] = name
      if !self.args.contains(id) {
        self.args[id] = ""
      }
    }
    CallArgs(id~, chunk~) => {
      if !self.args.contains(id) {
        self.order.push(id)
      }
      self.args[id] = self.args.get(id).unwrap_or("") + chunk
    }
    Done(reply) => self.done = Some(reply)
  }
}

///|
/// The assembled reply: the `Done` one when the stream sent it, otherwise one built
/// from what accumulated.
pub fn Assembly::reply(self : Assembly) -> Reply {
  match self.done {
    Some(reply) => reply
    None => {
      let parts = []
      if self.text != "" {
        parts.push(Part::Text(self.text))
      }
      for id in self.order {
        parts.push(
          Part::Call(
            id~,
            name=self.names.get(id).unwrap_or(""),
            args=parse_json_lossy(self.args.get(id).unwrap_or("")),
          ),
        )
      }
      Reply::new(Message::new(Assistant, parts))
    }
  }
}

///|
/// A JSON document from a string, or the empty object when the string is not JSON.
/// A streamed tool call whose arguments never complete is left as `{}` so the loop
/// can report the tool's own error instead of failing the whole turn.
pub fn parse_json_lossy(text : String) -> Json {
  if text.trim().is_empty() {
    return Json::object(Map([]))
  }
  @json.parse(text) catch {
    _ => Json::object(Map([]))
  }
}

///|
pub extend Finish with Eq::{not_equal, equal}

///|
pub extend Finish with Debug::{to_repr}

///|
pub extend Usage with Eq::{not_equal, equal}

///|
pub extend Usage with Debug::{to_repr}

///|
pub extend Reply with Eq::{not_equal, equal}

///|
pub extend Reply with Debug::{to_repr}

///|
pub extend Delta with Eq::{not_equal, equal}

///|
pub extend Delta with Debug::{to_repr}
