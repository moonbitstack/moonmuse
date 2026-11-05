///|
/// A conversation role. Koog 1.1.1 collapses to three: a tool exchange is carried
/// as parts inside a user/assistant message, not as a fourth top-level role.
pub(all) enum Role {
  System
  User
  Assistant
} derive(Eq, Debug, ToJson, FromJson)

///|
/// One typed piece of a message's content. Koog 1.1.1 moved off flat string
/// content to an ordered list of `MessagePart`s. A `ToolCall` carries its
/// arguments as a JSON value (Koog keeps the raw JSON string; we keep it parsed);
/// a `ToolResult` carries the exact string the model is shown.
pub(all) enum MessagePart {
  Text(String)
  Reasoning(Array[String])
  ToolCall(id~ : String?, tool~ : String, args~ : Json)
  ToolResult(id~ : String?, tool~ : String, output~ : String, is_error~ : Bool)
} derive(Eq, Debug, ToJson, FromJson)

///|
/// What the provider reported about the call that produced a reply (Koog
/// `ResponseMetaInfo`): the tokens it charged and the model id that actually served it,
/// which can differ from the one asked for. Every field is optional, because an
/// endpoint may answer without a `usage` object at all — and an absent count is not the
/// same as a zero one, which would read as a call that cost nothing.
pub(all) struct ResponseMetaInfo {
  total_tokens : Int32?
  input_tokens : Int32?
  output_tokens : Int32?
  model : String?
} derive(Eq, Debug, ToJson, FromJson)

///|
/// Meta with nothing reported — what a request message carries and what a reply from an
/// endpoint that sends no usage gets.
pub fn ResponseMetaInfo::empty() -> ResponseMetaInfo {
  { total_tokens: None, input_tokens: None, output_tokens: None, model: None, }
}

///|
/// A single message: a role and its ordered content parts. `finish_reason` is the
/// provider's stop reason on an assistant reply, `None` on a request message; `meta` is
/// what the provider reported about the call, `None` on anything the caller wrote.
pub(all) struct Message {
  role : Role
  parts : Array[MessagePart]
  finish_reason : String?
  meta : ResponseMetaInfo?
} derive(Eq, Debug, ToJson, FromJson)

///|
/// A plain system message.
pub fn Message::system(text : String) -> Message {
  { role: System, parts: [Text(text)], finish_reason: None, meta: None, }
}

///|
/// A plain user message.
pub fn Message::user(text : String) -> Message {
  { role: User, parts: [Text(text)], finish_reason: None, meta: None, }
}

///|
/// A plain assistant message.
pub fn Message::assistant(text : String) -> Message {
  { role: Assistant, parts: [Text(text)], finish_reason: None, meta: None, }
}

///|
/// A copy of this message carrying `meta` — how a client attaches the provider's token
/// counts once the reply's content has been mapped.
pub fn Message::with_meta(self : Message, meta : ResponseMetaInfo) -> Message {
  { ..self, meta: Some(meta), }
}

///|
/// The tokens this reply cost in total, when the provider reported them.
pub fn Message::total_tokens(self : Message) -> Int32? {
  self.meta.bind(m => m.total_tokens)
}

///|
/// A user message carrying a single tool result (a `ToolResult` is a request
/// part, so it rides a user message). What the agent loop appends after running a
/// tool.
pub fn Message::tool_result(
  tool~ : String,
  output~ : String,
  id? : String,
  is_error~ : Bool = false,
) -> Message {
  {
    role: User,
    parts: [ToolResult(id~, tool~, output~, is_error~)],
    finish_reason: None,
    meta: None,
  }
}

///|
/// The concatenated text of every `Text` part, joined by `separator` (Koog's
/// `Message.textContent`). Non-text parts contribute nothing.
pub fn Message::text_content(
  self : Message,
  separator~ : String = "\n",
) -> String {
  let texts = []
  for part in self.parts {
    match part {
      Text(t) => texts.push(t)
      _ => ()
    }
  }
  texts.join(separator)
}

///|
/// The tool calls this message requests: its `ToolCall` parts, in order. Empty
/// when the message is a plain text reply — the loop's signal to finish.
pub fn Message::tool_calls(self : Message) -> Array[MessagePart] {
  let calls = []
  for part in self.parts {
    if part is ToolCall(..) {
      calls.push(part)
    }
  }
  calls
}

///|
pub extend Message with Debug::{to_repr}

///|
pub extend Message with FromJson::{from_json}

///|
pub extend Message with Eq::{not_equal, equal}

///|
pub extend Message with ToJson::{to_json}

///|
pub extend MessagePart with Debug::{to_repr}

///|
pub extend MessagePart with FromJson::{from_json}

///|
pub extend MessagePart with Eq::{not_equal, equal}

///|
pub extend MessagePart with ToJson::{to_json}

///|
pub extend ResponseMetaInfo with Debug::{to_repr}

///|
pub extend ResponseMetaInfo with FromJson::{from_json}

///|
pub extend ResponseMetaInfo with Eq::{not_equal, equal}

///|
pub extend ResponseMetaInfo with ToJson::{to_json}

///|
pub extend Role with Debug::{to_repr}

///|
pub extend Role with FromJson::{from_json}

///|
pub extend Role with Eq::{not_equal, equal}

///|
pub extend Role with ToJson::{to_json}
