///|
/// Who authored a message. A tool exchange is a role of its own here rather than a
/// part of a user message, because OpenAI, Anthropic, Gemini and Ollama all put it
/// in a distinct place on the wire.
#derive(Eq, Debug)
pub(all) enum Role {
  System
  User
  Assistant
  Tool
}

///|
/// The lowercase name a role goes by on the wire, using the OpenAI spelling.
pub fn Role::code(self : Role) -> String {
  match self {
    System => "system"
    User => "user"
    Assistant => "assistant"
    Tool => "tool"
  }
}

///|
/// One typed piece of a message. A message is an ordered list of these, so text and
/// a tool call can share one assistant turn — which is what every provider returns
/// when a model calls a tool and explains itself in the same breath.
#derive(Eq, Debug)
pub(all) enum Part {
  /// Literal text.
  Text(String)
  /// An image, either a URL or an inline media type plus URL.
  Image(url~ : String, media~ : String?)
  /// The model asks for a tool: its id (for matching the result), its name, and the
  /// parsed arguments.
  Call(id~ : String, name~ : String, args~ : Json)
  /// A tool's answer, linked to the call by `id`. A failed tool is a result with
  /// `error` set, not an exception: the model is supposed to see what went wrong.
  Result(id~ : String, content~ : String, error~ : Bool)
}

///|
/// A text part.
pub fn Part::text(text : String) -> Part {
  Text(text)
}

///|
/// A tool call part.
pub fn Part::call(id : String, name : String, args : Json) -> Part {
  Call(id~, name~, args~)
}

///|
/// A tool result part.
pub fn Part::result(
  id : String,
  content : String,
  error~ : Bool = false,
) -> Part {
  Result(id~, content~, error~)
}

///|
/// The text this part carries: a text part's own text, a result's content, and nothing for a
/// call or an image.
pub fn Part::text_of(self : Part) -> String {
  match self {
    Text(text) => text
    Result(content~, ..) => content
    _ => ""
  }
}

///|
/// A message: a role and its ordered parts.
#derive(Eq, Debug)
pub(all) struct Message {
  role : Role
  parts : Array[Part]
}

///|
/// A message built from a role and its parts.
pub fn Message::new(role : Role, parts : Array[Part]) -> Message {
  { role, parts, }
}

///|
/// A system message carrying one text part.
pub fn Message::system(text : String) -> Message {
  { role: System, parts: [Text(text)], }
}

///|
/// A user message carrying one text part.
pub fn Message::user(text : String) -> Message {
  { role: User, parts: [Text(text)], }
}

///|
/// An assistant message carrying one text part.
pub fn Message::assistant(text : String) -> Message {
  { role: Assistant, parts: [Text(text)], }
}

///|
/// A tool message carrying one result, addressed to the call `id`.
pub fn Message::tool(
  content : String,
  id~ : String,
  error~ : Bool = false,
) -> Message {
  { role: Tool, parts: [Result(id~, content~, error~)], }
}

///|
/// A copy with `part` appended. The tool loop grows the conversation this way.
pub fn Message::push(self : Message, part : Part) -> Message {
  { ..self, parts: [..self.parts, part], }
}

///|
/// The text parts joined by `separator`. What a caller shows a human, and what a
/// provider without structured content receives.
pub fn Message::text_content(
  self : Message,
  separator~ : String = "\n",
) -> String {
  let texts = []
  for part in self.parts {
    if part is Text(text) {
      texts.push(text)
    }
  }
  texts.join(separator)
}

///|
/// The tool calls this message requests, in order. Empty on a plain text reply.
pub fn Message::calls(self : Message) -> Array[Part] {
  self.parts.filter(part => part is Call(..))
}

///|
/// The tool results this message carries, in order.
pub fn Message::results(self : Message) -> Array[Part] {
  self.parts.filter(part => part is Result(..))
}

///|
/// Whether this message asks for a tool.
pub fn Message::is_call(self : Message) -> Bool {
  for part in self.parts {
    if part is Call(..) {
      return true
    }
  }
  false
}

///|
pub extend Role with Eq::{not_equal, equal}

///|
pub extend Role with Debug::{to_repr}

///|
pub extend Part with Eq::{not_equal, equal}

///|
pub extend Part with Debug::{to_repr}

///|
pub extend Message with Eq::{not_equal, equal}

///|
pub extend Message with Debug::{to_repr}
