// The Google Gemini model catalog (Koog `GoogleModels`): each model's provider-side id, its
// declared capabilities, and its context / output-token limits. Every Gemini model shares the same
// full capability set (temperature, completion, multiple choices, vision, audio, tools, JSON
// schema); the 2.5+ generation adds `Thinking`. `Vision.Image` and `Vision.Video` both flatten to
// the single `Vision` leaf the enum documents.
// Source: prompt/.../clients/google/GoogleModels.kt (tag 1.1.1).

///|
/// The capabilities every Gemini chat model declares (Koog `fullCapabilities` = standard +
/// multimodal + tools + structured output).
let gemini_full : Array[LLMCapability] = [
  Temperature,
  Completion,
  MultipleChoices,
  Vision,
  Audio,
  Tools,
  ToolChoice,
  SchemaJsonBasic,
  SchemaJsonStandard,
]

///|
/// The full capability set plus `Thinking`, for the reasoning-capable 2.5+ models.
let gemini_full_thinking : Array[LLMCapability] = [
  Temperature,
  Completion,
  MultipleChoices,
  Vision,
  Audio,
  Tools,
  ToolChoice,
  SchemaJsonBasic,
  SchemaJsonStandard,
  Thinking,
]

///|
/// Gemini 2.0 Flash-Lite (specific version).
pub let gemini_2_0_flash_lite_001 : LLModel = {
  provider: google,
  id: "gemini-2.0-flash-lite-001",
  capabilities: gemini_full,
  context_length: Some(1_048_576),
  max_output_tokens: Some(8_192),
}

///|
/// Gemini 2.5 Pro — advanced capabilities for complex tasks.
pub let gemini_2_5_pro : LLModel = {
  provider: google,
  id: "gemini-2.5-pro",
  capabilities: gemini_full_thinking,
  context_length: Some(1_048_576),
  max_output_tokens: Some(65_536),
}

///|
/// Gemini 2.5 Flash — a balance of speed and capability.
pub let gemini_2_5_flash : LLModel = {
  provider: google,
  id: "gemini-2.5-flash",
  capabilities: gemini_full_thinking,
  context_length: Some(1_048_576),
  max_output_tokens: Some(65_536),
}

///|
/// Gemini 2.5 Flash-Lite — cost-efficient, high throughput.
pub let gemini_2_5_flash_lite : LLModel = {
  provider: google,
  id: "gemini-2.5-flash-lite",
  capabilities: gemini_full,
  context_length: Some(1_048_576),
  max_output_tokens: Some(65_536),
}

///|
/// Gemini 3 Flash Preview — Pro-level intelligence at Flash speed.
pub let gemini_3_flash_preview : LLModel = {
  provider: google,
  id: "gemini-3-flash-preview",
  capabilities: gemini_full_thinking,
  context_length: Some(1_048_576),
  max_output_tokens: Some(65_536),
}

///|
/// Gemini 3.1 Pro Preview — advanced reasoning.
pub let gemini_3_1_pro_preview : LLModel = {
  provider: google,
  id: "gemini-3.1-pro-preview",
  capabilities: gemini_full_thinking,
  context_length: Some(1_048_576),
  max_output_tokens: Some(65_536),
}

///|
/// Gemini 3.1 Flash-Lite Preview — low latency.
pub let gemini_3_1_flash_lite_preview : LLModel = {
  provider: google,
  id: "gemini-3.1-flash-lite-preview",
  capabilities: gemini_full_thinking,
  context_length: Some(1_048_576),
  max_output_tokens: Some(65_536),
}

///|
/// Gemini 3.1 Flash-Lite — low latency.
pub let gemini_3_1_flash_lite : LLModel = {
  provider: google,
  id: "gemini-3.1-flash-lite",
  capabilities: gemini_full_thinking,
  context_length: Some(1_048_576),
  max_output_tokens: Some(65_536),
}

///|
/// Gemini 3.5 Flash — fast multimodal generation.
pub let gemini_3_5_flash : LLModel = {
  provider: google,
  id: "gemini-3.5-flash",
  capabilities: gemini_full_thinking,
  context_length: Some(1_048_576),
  max_output_tokens: Some(65_536),
}

///|
/// Gemini embedding model (text embeddings).
pub let gemini_embedding_001 : LLModel = {
  provider: google,
  id: "gemini-embedding-001",
  capabilities: [Embed],
  context_length: Some(2_048),
  max_output_tokens: None,
}

///|
/// The Google models supported out of the box (Koog `GoogleModels.supportedModels`), in the
/// source's order.
pub fn google_models() -> Array[LLModel] {
  [
    gemini_2_0_flash_lite_001, gemini_2_5_pro, gemini_2_5_flash, gemini_2_5_flash_lite,
    gemini_3_flash_preview, gemini_3_1_pro_preview, gemini_3_1_flash_lite_preview,
    gemini_3_1_flash_lite, gemini_3_5_flash, gemini_embedding_001,
  ]
}
