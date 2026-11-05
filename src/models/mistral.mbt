// The Mistral AI model catalog (Koog `MistralAIModels`): each model's provider-side id, its declared
// capabilities, and its context window. Mistral's models carry no fixed output-token limit in the
// catalog. `Vision.Image` flattens to the single `Vision` leaf.
// Source: prompt/.../clients/mistralai/MistralAIModels.kt (tag 1.1.1).

///|
/// Mistral Medium 3 — frontier-class multimodal (128k context).
pub let mistral_medium_3 : LLModel = {
  provider: mistralai,
  id: "mistral-medium-latest",
  capabilities: [
    Temperature,
    Completion,
    Tools,
    ToolChoice,
    SchemaJsonBasic,
    SchemaJsonStandard,
    Vision,
    Document,
    MultipleChoices,
  ],
  context_length: Some(128_000),
  max_output_tokens: None,
}

///|
/// Mistral Large 2.1 — top-tier model for high-complexity tasks (128k context).
pub let mistral_large_2_1 : LLModel = {
  provider: mistralai,
  id: "mistral-large-latest",
  capabilities: [
    Temperature,
    Completion,
    Tools,
    ToolChoice,
    SchemaJsonBasic,
    SchemaJsonStandard,
    MultipleChoices,
  ],
  context_length: Some(128_000),
  max_output_tokens: None,
}

///|
/// Mistral Small 2 — efficient model for standard tasks (32k context).
pub let mistral_small_2 : LLModel = {
  provider: mistralai,
  id: "mistral-small-latest",
  capabilities: [
    Temperature,
    Completion,
    Tools,
    ToolChoice,
    SchemaJsonBasic,
    MultipleChoices,
  ],
  context_length: Some(32_000),
  max_output_tokens: None,
}

///|
/// Magistral Medium 1.2 — frontier reasoning model with vision (128k context).
pub let magistral_medium_1_2 : LLModel = {
  provider: mistralai,
  id: "magistral-medium-latest",
  capabilities: [
    Temperature,
    Completion,
    Tools,
    ToolChoice,
    SchemaJsonBasic,
    SchemaJsonStandard,
    Speculation,
    Vision,
    Document,
    MultipleChoices,
    Thinking,
  ],
  context_length: Some(128_000),
  max_output_tokens: None,
}

///|
/// Codestral — coding model for low-latency fill-in-the-middle and corrections (256k context).
pub let codestral : LLModel = {
  provider: mistralai,
  id: "codestral-latest",
  capabilities: [Temperature, Completion, Tools, ToolChoice, SchemaJsonBasic],
  context_length: Some(256_000),
  max_output_tokens: None,
}

///|
/// Devstral Medium — enterprise coding model for software-engineering agents (128k context).
pub let devstral_medium : LLModel = {
  provider: mistralai,
  id: "devstral-medium-latest",
  capabilities: [
    Temperature,
    Completion,
    Tools,
    ToolChoice,
    SchemaJsonBasic,
    SchemaJsonStandard,
    Document,
  ],
  context_length: Some(128_000),
  max_output_tokens: None,
}

///|
/// Mistral Embed — text embedding model (8k context).
pub let mistral_embed : LLModel = {
  provider: mistralai,
  id: "mistral-embed",
  capabilities: [Embed],
  context_length: Some(8_000),
  max_output_tokens: None,
}

///|
/// Codestral Embed — code embedding model (8k context).
pub let codestral_embed : LLModel = {
  provider: mistralai,
  id: "codestral-embed",
  capabilities: [Embed],
  context_length: Some(8_000),
  max_output_tokens: None,
}

///|
/// Mistral Moderation — content-safety moderation model (8k context).
pub let mistral_moderation : LLModel = {
  provider: mistralai,
  id: "mistral-moderation-2411",
  capabilities: [Moderation],
  context_length: Some(8_000),
  max_output_tokens: None,
}

///|
/// The Mistral AI models supported out of the box (Koog `MistralAIModels.supportedModels`).
pub fn mistral_models() -> Array[LLModel] {
  [
    mistral_medium_3, mistral_large_2_1, mistral_small_2, magistral_medium_1_2, codestral,
    devstral_medium, mistral_embed, codestral_embed, mistral_moderation,
  ]
}
