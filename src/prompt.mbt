///|
/// How the model should use tools this request (Koog `LLMParams.ToolChoice`).
pub(all) enum ToolChoice {
  /// The model decides whether to call a tool or answer directly.
  Auto
  /// The model must not call any tool and only generates text.
  NoTools
  /// The model must call a tool.
  Required
  /// The model must call the named tool.
  Named(String)
} derive(Eq, Debug, ToJson)

///|
/// A structured-output schema the model must produce (Koog `LLMParams.Schema`): a named JSON
/// schema, in the provider's basic or the JSON-Schema-standard dialect.
pub(all) enum Schema {
  JsonBasic(name~ : String, schema~ : Json)
  JsonStandard(name~ : String, schema~ : Json)
} derive(Eq, Debug, ToJson)

///|
/// Per-request LLM parameters (Koog `LLMParams`). `None` means "let the provider default
/// apply". This carries the full Koog surface; each client maps the subset its provider
/// supports.
pub(all) struct LLMParams {
  temperature : Double?
  max_tokens : Int32?
  number_of_choices : Int32?
  speculation : String?
  schema : Schema?
  tool_choice : ToolChoice?
  user : String?
  include_thoughts : Bool?
  thinking_budget : Int32?
  additional_properties : Map[String, Json]?
} derive(Eq, Debug, ToJson)

///|
/// The empty params: no overrides.
pub fn LLMParams::default() -> LLMParams {
  {
    temperature: None,
    max_tokens: None,
    number_of_choices: None,
    speculation: None,
    schema: None,
    tool_choice: None,
    user: None,
    include_thoughts: None,
    thinking_budget: None,
    additional_properties: None,
  }
}

///|
/// The immutable request object handed to an LLM: an ordered message list, an
/// identifier, and the params. Koog builds it through a DSL; here it is built
/// through the fluent `PromptBuilder`.
pub(all) struct Prompt {
  messages : Array[Message]
  id : String
  params : LLMParams
} derive(Eq, Debug)

///|
/// A copy of this prompt with `message` appended — the immutable-append the agent
/// loop uses to grow the conversation without mutating a shared value.
pub fn Prompt::append(self : Prompt, message : Message) -> Prompt {
  { ..self, messages: [..self.messages, message], }
}

///|
/// A mutable builder for a `Prompt`. MoonBit has no receiver-lambda DSL, so the
/// Koog `prompt { system(...); user(...) }` block becomes a fluent chain
/// `PromptBuilder::new().system(...).user(...).build()`.
pub struct PromptBuilder {
  messages : Array[Message]
  id : String
  mut params : LLMParams
}

///|
/// A fresh builder.
pub fn PromptBuilder::new(
  id~ : String = "prompt",
  params~ : LLMParams = LLMParams::default(),
) -> PromptBuilder {
  { messages: [], id, params, }
}

///|
/// Append a system message.
pub fn PromptBuilder::system(
  self : PromptBuilder,
  text : String,
) -> PromptBuilder {
  self.messages.push(Message::system(text))
  self
}

///|
/// Append a user message.
pub fn PromptBuilder::user(
  self : PromptBuilder,
  text : String,
) -> PromptBuilder {
  self.messages.push(Message::user(text))
  self
}

///|
/// Append an assistant message.
pub fn PromptBuilder::assistant(
  self : PromptBuilder,
  text : String,
) -> PromptBuilder {
  self.messages.push(Message::assistant(text))
  self
}

///|
/// Append a whole pre-built message (e.g. an assistant reply carrying tool calls).
pub fn PromptBuilder::message(
  self : PromptBuilder,
  message : Message,
) -> PromptBuilder {
  self.messages.push(message)
  self
}

///|
/// Append a user message carrying a single tool result (Koog's `toolResult`; a
/// `ToolResult` is a request part, so it rides a user message).
pub fn PromptBuilder::tool_result(
  self : PromptBuilder,
  tool~ : String,
  output~ : String,
  id? : String,
  is_error~ : Bool = false,
) -> PromptBuilder {
  self.messages.push({
    role: User,
    parts: [ToolResult(id~, tool~, output~, is_error~)],
    finish_reason: None,
    meta: None,
  })
  self
}

///|
/// Set the LLM params.
pub fn PromptBuilder::params(
  self : PromptBuilder,
  params : LLMParams,
) -> PromptBuilder {
  self.params = params
  self
}

///|
/// Finish building.
pub fn PromptBuilder::build(self : PromptBuilder) -> Prompt {
  { messages: self.messages, id: self.id, params: self.params, }
}

///|
pub extend LLMParams with Debug::{to_repr}

///|
pub extend LLMParams with Eq::{not_equal, equal}

///|
pub extend LLMParams with ToJson::{to_json}

///|
pub extend Prompt with Debug::{to_repr}

///|
pub extend Prompt with Eq::{not_equal, equal}

///|
pub extend Schema with Debug::{to_repr}

///|
pub extend Schema with Eq::{not_equal, equal}

///|
pub extend Schema with ToJson::{to_json}

///|
pub extend ToolChoice with Debug::{to_repr}

///|
pub extend ToolChoice with Eq::{not_equal, equal}

///|
pub extend ToolChoice with ToJson::{to_json}
