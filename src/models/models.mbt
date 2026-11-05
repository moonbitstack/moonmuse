///|
/// An LLM provider identity. Koog models `LLMProvider` as an *open* class, not a
/// closed enum, because a user can define their own provider — so moonkoog uses a
/// struct plus named constants rather than a variant set.
/// Source: prompt/prompt-llm/.../llm/LLMProvider.kt.
pub(all) struct LLMProvider {
  id : String
  display : String
} derive(Eq, Debug)

///|
pub let openai : LLMProvider = { id: "openai", display: "OpenAI", }

///|
pub let anthropic : LLMProvider = { id: "anthropic", display: "Anthropic", }

///|
pub let google : LLMProvider = { id: "google", display: "Google", }

///|
pub let deepseek : LLMProvider = { id: "deepseek", display: "DeepSeek", }

///|
pub let alibaba : LLMProvider = { id: "alibaba", display: "Alibaba", }

///|
pub let meta : LLMProvider = { id: "meta", display: "Meta", }

///|
pub let ollama : LLMProvider = { id: "ollama", display: "Ollama", }

///|
pub let openrouter : LLMProvider = { id: "openrouter", display: "OpenRouter", }

///|
pub let mistralai : LLMProvider = { id: "mistralai", display: "MistralAI", }

///|
/// A capability a model may declare. Koog's `LLMCapability` is a sealed hierarchy;
/// this flattens its leaves (the two JSON-schema levels become `SchemaJsonBasic` /
/// `SchemaJsonStandard`; the two OpenAI endpoints become `OpenAIEndpointCompletions` /
/// `OpenAIEndpointResponses`; `Vision` is a single leaf here rather than its
/// image/video subtypes — those land when multimodal does).
/// Source: prompt/prompt-llm/.../llm/LLMCapability.kt.
pub(all) enum LLMCapability {
  Completion
  Temperature
  Tools
  ToolChoice
  MultipleChoices
  Vision
  Audio
  Document
  Embed
  PromptCaching
  Moderation
  Thinking
  Speculation
  SchemaJsonBasic
  SchemaJsonStandard
  OpenAIEndpointCompletions
  OpenAIEndpointResponses
} derive(Eq, Debug)

///|
/// A specific model: which provider serves it, its provider-side id, its declared
/// capabilities, and the optional context / output-token limits.
/// Source: prompt/prompt-llm/.../llm/LLModel.kt.
pub(all) struct LLModel {
  provider : LLMProvider
  id : String
  capabilities : Array[LLMCapability]
  context_length : Int32?
  max_output_tokens : Int32?
} derive(Eq, Debug)

///|
/// Whether the model declares `capability` (Koog `LLModel.supports`).
pub fn LLModel::supports(self : LLModel, capability : LLMCapability) -> Bool {
  for c in self.capabilities {
    if c == capability {
      return true
    }
  }
  false
}

// The predefined model catalogs live in their per-provider files: `openai_models.mbt`,
// `anthropic_models.mbt`, `google_models.mbt`, `deepseek_models.mbt`.

///|
pub extend LLMCapability with Debug::{to_repr}

///|
pub extend LLMCapability with Eq::{not_equal, equal}

///|
pub extend LLMProvider with Debug::{to_repr}

///|
pub extend LLMProvider with Eq::{not_equal, equal}

///|
pub extend LLModel with Debug::{to_repr}

///|
pub extend LLModel with Eq::{not_equal, equal}
