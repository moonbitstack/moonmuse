///|
/// A capability a model may declare. The catalogue in `moonmuse/models` uses these
/// to describe what an endpoint can actually do, so a caller can pick a model for a
/// job instead of guessing from its name.
#derive(Eq, Debug)
pub(all) enum Capability {
  Chat
  Tools
  Reasoning
  Vision
  Audio
  Embedding
  Json
}

///|
/// What a provider says about one model. Prices are US dollars per million tokens,
/// because that is the unit every vendor publishes and the one a cost estimate wants.
#derive(Eq, Debug)
pub(all) struct ModelInfo {
  id : String
  context : Int32?
  output : Int32?
  input_price : Double?
  output_price : Double?
  capabilities : Array[Capability]
}

///|
/// A model with everything unknown except its id.
pub fn ModelInfo::new(
  id : String,
  context? : Int32,
  output? : Int32,
  input_price? : Double,
  output_price? : Double,
  capabilities~ : Array[Capability] = [],
) -> ModelInfo {
  { id, context, output, input_price, output_price, capabilities, }
}

///|
/// Whether the model declares `capability`.
pub fn ModelInfo::supports(self : ModelInfo, capability : Capability) -> Bool {
  for item in self.capabilities {
    if item == capability {
      return true
    }
  }
  false
}

///|
/// How a request should use tools.
#derive(Eq, Debug)
pub(all) enum ToolChoice {
  /// The model decides. The default of every provider here.
  Auto
  /// The model must answer in text.
  NoTools
  /// The model must call some tool.
  Required
  /// The model must call this tool.
  Named(String)
}

///|
/// A tool the model may call: a name, a description, and a JSON Schema object for
/// the arguments.
#derive(Eq, Debug)
pub(all) struct Tool {
  name : String
  description : String
  schema : Json
}

///|
/// A tool with an empty object schema, for a tool that takes no arguments.
pub fn Tool::new(
  name : String,
  description : String,
  schema~ : Json = { "type": "object", "properties": {} },
) -> Tool {
  { name, description, schema, }
}

///|
/// One request, in the vocabulary every provider shares. `extra` is merged into the
/// request body last of all, so a field this library does not model — a vendor's
/// beta switch, a reasoning budget — still reaches the wire.
#derive(Eq, Debug)
pub(all) struct Request {
  model : String
  messages : Array[Message]
  tools : Array[Tool]
  choice : ToolChoice
  temperature : Double?
  max_tokens : Int32?
  stop : Array[String]
  extra : Map[String, Json]
}

///|
/// A request with the provider's defaults.
pub fn Request::new(
  model : String,
  messages : Array[Message],
  tools~ : Array[Tool] = [],
  choice~ : ToolChoice = Auto,
  temperature? : Double,
  max_tokens? : Int32,
  stop~ : Array[String] = [],
  extra~ : Map[String, Json] = Map([]),
) -> Request {
  { model, messages, tools, choice, temperature, max_tokens, stop, extra, }
}

///|
/// A copy with one more message — the tool loop appends the assistant's call and the
/// tool's result this way.
pub fn Request::push(self : Request, message : Message) -> Request {
  { ..self, messages: [..self.messages, message], }
}

///|
/// A copy with the messages replaced.
pub fn Request::with_messages(
  self : Request,
  messages : Array[Message],
) -> Request {
  { ..self, messages, }
}

///|
pub extend Capability with Eq::{not_equal, equal}

///|
pub extend Capability with Debug::{to_repr}

///|
pub extend ModelInfo with Eq::{not_equal, equal}

///|
pub extend ModelInfo with Debug::{to_repr}

///|
pub extend ToolChoice with Eq::{not_equal, equal}

///|
pub extend ToolChoice with Debug::{to_repr}

///|
pub extend Tool with Eq::{not_equal, equal}

///|
pub extend Tool with Debug::{to_repr}

///|
pub extend Request with Eq::{not_equal, equal}

///|
pub extend Request with Debug::{to_repr}
