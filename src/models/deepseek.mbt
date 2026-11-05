// The DeepSeek model catalog (Koog `DeepSeekModels`): each model's provider-side id, its declared
// capabilities, and its context / output-token limits. Both V4 models share the same capability set
// and 1M-context / 384k-output limits; both support thinking and non-thinking modes.
// Source: prompt/.../clients/deepseek/DeepSeekModels.kt (tag 1.1.1).

///|
/// DeepSeek V4 Flash — fast, cost-effective generation (also moonkoog's default smoke-test model).
pub let deepseek_v4_flash : LLModel = {
  provider: deepseek,
  id: "deepseek-v4-flash",
  capabilities: [
    Completion,
    Temperature,
    Tools,
    ToolChoice,
    SchemaJsonBasic,
    SchemaJsonStandard,
    MultipleChoices,
    Thinking,
  ],
  context_length: Some(1_000_000),
  max_output_tokens: Some(384_000),
}

///|
/// DeepSeek V4 Pro — advanced reasoning and agentic tasks.
pub let deepseek_v4_pro : LLModel = {
  provider: deepseek,
  id: "deepseek-v4-pro",
  capabilities: [
    Completion,
    Temperature,
    Tools,
    ToolChoice,
    SchemaJsonBasic,
    SchemaJsonStandard,
    MultipleChoices,
    Thinking,
  ],
  context_length: Some(1_000_000),
  max_output_tokens: Some(384_000),
}

///|
/// The DeepSeek models supported out of the box (Koog `DeepSeekModels.supportedModels`).
pub fn deepseek_models() -> Array[LLModel] {
  [deepseek_v4_flash, deepseek_v4_pro]
}
