// The OpenAI model catalog (Koog `OpenAIModels`): each model's provider-side id, its declared
// capabilities (in the source's order), and its context / output-token limits. Reasoning models
// (o-series, GPT-5 family) carry `Thinking`; capability leaves are flattened the same way the enum
// documents (Schema.JSON.* → SchemaJson*, OpenAIEndpoint.* → OpenAIEndpoint*, Vision.Image → Vision).
// Source: prompt/.../clients/openai/OpenAIModels.kt (tag 1.1.1).

///|
/// GPT-4o — the versatile omni flagship (128k context, 16k output).
pub let gpt_4o : LLModel = {
  provider: openai,
  id: "gpt-4o",
  capabilities: [
    Temperature,
    ToolChoice,
    SchemaJsonBasic,
    SchemaJsonStandard,
    Speculation,
    Tools,
    Vision,
    Document,
    Completion,
    MultipleChoices,
    OpenAIEndpointCompletions,
    OpenAIEndpointResponses,
  ],
  context_length: Some(128_000),
  max_output_tokens: Some(16_384),
}

///|
/// GPT-4o mini — the cost-optimised 4o (128k context, 16k output).
pub let gpt_4o_mini : LLModel = {
  provider: openai,
  id: "gpt-4o-mini",
  capabilities: [
    Temperature,
    SchemaJsonBasic,
    SchemaJsonStandard,
    Speculation,
    Tools,
    ToolChoice,
    Vision,
    Document,
    Completion,
    MultipleChoices,
    OpenAIEndpointCompletions,
    OpenAIEndpointResponses,
  ],
  context_length: Some(128_000),
  max_output_tokens: Some(16_384),
}

///|
/// GPT-4.1 — complex-task model (1,047,576 context, 32k output).
pub let gpt_4_1 : LLModel = {
  provider: openai,
  id: "gpt-4.1",
  capabilities: [
    Temperature,
    SchemaJsonBasic,
    SchemaJsonStandard,
    Speculation,
    Tools,
    ToolChoice,
    Vision,
    Document,
    Completion,
    MultipleChoices,
    OpenAIEndpointCompletions,
    OpenAIEndpointResponses,
  ],
  context_length: Some(1_047_576),
  max_output_tokens: Some(32_768),
}

///|
/// GPT-4.1 nano — smallest, cheapest 4.1 (1,047,576 context, 32k output).
pub let gpt_4_1_nano : LLModel = {
  provider: openai,
  id: "gpt-4.1-nano",
  capabilities: [
    Temperature,
    SchemaJsonBasic,
    SchemaJsonStandard,
    Speculation,
    Tools,
    ToolChoice,
    Vision,
    Document,
    Completion,
    MultipleChoices,
    OpenAIEndpointCompletions,
    OpenAIEndpointResponses,
  ],
  context_length: Some(1_047_576),
  max_output_tokens: Some(32_768),
}

///|
/// GPT-4.1 mini — balanced 4.1 (1,047,576 context, 32k output).
pub let gpt_4_1_mini : LLModel = {
  provider: openai,
  id: "gpt-4.1-mini",
  capabilities: [
    Temperature,
    SchemaJsonBasic,
    SchemaJsonStandard,
    Speculation,
    Tools,
    ToolChoice,
    Vision,
    Document,
    Completion,
    MultipleChoices,
    OpenAIEndpointCompletions,
    OpenAIEndpointResponses,
  ],
  context_length: Some(1_047_576),
  max_output_tokens: Some(32_768),
}

///|
/// o1 — the reasoning model (200k context, 100k output).
pub let o1 : LLModel = {
  provider: openai,
  id: "o1",
  capabilities: [
    Tools,
    ToolChoice,
    Speculation,
    SchemaJsonBasic,
    SchemaJsonStandard,
    Vision,
    Document,
    Completion,
    MultipleChoices,
    OpenAIEndpointCompletions,
    OpenAIEndpointResponses,
    Thinking,
  ],
  context_length: Some(200_000),
  max_output_tokens: Some(100_000),
}

///|
/// o3 — well-rounded reasoning across domains (200k context, 100k output).
pub let o3 : LLModel = {
  provider: openai,
  id: "o3",
  capabilities: [
    Tools,
    ToolChoice,
    Speculation,
    SchemaJsonBasic,
    SchemaJsonStandard,
    Vision,
    Document,
    Completion,
    MultipleChoices,
    OpenAIEndpointCompletions,
    OpenAIEndpointResponses,
    Thinking,
  ],
  context_length: Some(200_000),
  max_output_tokens: Some(100_000),
}

///|
/// o3-mini — small reasoning model, no vision (200k context, 100k output).
pub let o3_mini : LLModel = {
  provider: openai,
  id: "o3-mini",
  capabilities: [
    Tools,
    ToolChoice,
    Speculation,
    SchemaJsonBasic,
    SchemaJsonStandard,
    Completion,
    MultipleChoices,
    OpenAIEndpointCompletions,
    OpenAIEndpointResponses,
    Thinking,
  ],
  context_length: Some(200_000),
  max_output_tokens: Some(100_000),
}

///|
/// o4-mini — cost-effective reasoning (200k context, 100k output).
pub let o4_mini : LLModel = {
  provider: openai,
  id: "o4-mini",
  capabilities: [
    SchemaJsonBasic,
    SchemaJsonStandard,
    Speculation,
    Tools,
    ToolChoice,
    Vision,
    Document,
    Completion,
    MultipleChoices,
    OpenAIEndpointCompletions,
    OpenAIEndpointResponses,
    Thinking,
  ],
  context_length: Some(200_000),
  max_output_tokens: Some(100_000),
}

///|
/// GPT-5 — flagship for coding, reasoning, agentic tasks (400k context, 128k output).
pub let gpt_5 : LLModel = {
  provider: openai,
  id: "gpt-5",
  capabilities: [
    SchemaJsonBasic,
    SchemaJsonStandard,
    Speculation,
    Tools,
    ToolChoice,
    Vision,
    Document,
    Completion,
    MultipleChoices,
    OpenAIEndpointCompletions,
    OpenAIEndpointResponses,
    Thinking,
  ],
  context_length: Some(400_000),
  max_output_tokens: Some(128_000),
}

///|
/// GPT-5 mini — faster, cheaper GPT-5 (400k context, 128k output).
pub let gpt_5_mini : LLModel = {
  provider: openai,
  id: "gpt-5-mini",
  capabilities: [
    SchemaJsonBasic,
    SchemaJsonStandard,
    Speculation,
    Tools,
    ToolChoice,
    Vision,
    Document,
    Completion,
    MultipleChoices,
    OpenAIEndpointCompletions,
    OpenAIEndpointResponses,
    Thinking,
  ],
  context_length: Some(400_000),
  max_output_tokens: Some(128_000),
}

///|
/// GPT-5 nano — fastest, cheapest GPT-5 (400k context, 128k output).
pub let gpt_5_nano : LLModel = {
  provider: openai,
  id: "gpt-5-nano",
  capabilities: [
    SchemaJsonBasic,
    SchemaJsonStandard,
    Speculation,
    Tools,
    ToolChoice,
    Vision,
    Document,
    Completion,
    MultipleChoices,
    OpenAIEndpointCompletions,
    OpenAIEndpointResponses,
    Thinking,
  ],
  context_length: Some(400_000),
  max_output_tokens: Some(128_000),
}

///|
/// GPT-5-Codex — agentic coding, Responses API only (400k context, 128k output).
pub let gpt_5_codex : LLModel = {
  provider: openai,
  id: "gpt-5-codex",
  capabilities: [
    Completion,
    SchemaJsonBasic,
    SchemaJsonStandard,
    Speculation,
    Tools,
    ToolChoice,
    OpenAIEndpointResponses,
    Thinking,
  ],
  context_length: Some(400_000),
  max_output_tokens: Some(128_000),
}

///|
/// GPT-5 pro — highest-compute reasoning, Responses API only (400k context, 272k output).
pub let gpt_5_pro : LLModel = {
  provider: openai,
  id: "gpt-5-pro",
  capabilities: [
    Tools,
    ToolChoice,
    Speculation,
    SchemaJsonBasic,
    SchemaJsonStandard,
    Vision,
    MultipleChoices,
    OpenAIEndpointResponses,
    Thinking,
  ],
  context_length: Some(400_000),
  max_output_tokens: Some(272_000),
}

///|
/// GPT-5.1 — flagship with configurable reasoning effort (400k context, 128k output).
pub let gpt_5_1 : LLModel = {
  provider: openai,
  id: "gpt-5.1",
  capabilities: [
    Completion,
    SchemaJsonBasic,
    SchemaJsonStandard,
    Speculation,
    Tools,
    ToolChoice,
    Vision,
    Document,
    MultipleChoices,
    OpenAIEndpointCompletions,
    OpenAIEndpointResponses,
    Thinking,
  ],
  context_length: Some(400_000),
  max_output_tokens: Some(128_000),
}

///|
/// GPT-5.1-Codex — agentic coding, Responses API only (400k context, 128k output).
pub let gpt_5_1_codex : LLModel = {
  provider: openai,
  id: "gpt-5.1-codex",
  capabilities: [
    Completion,
    SchemaJsonBasic,
    SchemaJsonStandard,
    Speculation,
    Tools,
    ToolChoice,
    Vision,
    Document,
    MultipleChoices,
    OpenAIEndpointResponses,
    Thinking,
  ],
  context_length: Some(400_000),
  max_output_tokens: Some(128_000),
}

///|
/// GPT-5.1-Codex-Max — purpose-built agentic coding, Responses API only (400k context, 128k output).
pub let gpt_5_1_codex_max : LLModel = {
  provider: openai,
  id: "gpt-5.1-codex-max",
  capabilities: [
    Completion,
    SchemaJsonBasic,
    SchemaJsonStandard,
    Speculation,
    Tools,
    ToolChoice,
    Vision,
    Document,
    MultipleChoices,
    OpenAIEndpointResponses,
    Thinking,
  ],
  context_length: Some(400_000),
  max_output_tokens: Some(128_000),
}

///|
/// GPT-5.2 — flagship for coding and agentic tasks (400k context, 128k output).
pub let gpt_5_2 : LLModel = {
  provider: openai,
  id: "gpt-5.2",
  capabilities: [
    Completion,
    SchemaJsonBasic,
    SchemaJsonStandard,
    Speculation,
    Tools,
    ToolChoice,
    Vision,
    Document,
    MultipleChoices,
    OpenAIEndpointCompletions,
    OpenAIEndpointResponses,
    Thinking,
  ],
  context_length: Some(400_000),
  max_output_tokens: Some(128_000),
}

///|
/// GPT-5.2 pro — Responses API only, no JSON schema (400k context, 128k output).
pub let gpt_5_2_pro : LLModel = {
  provider: openai,
  id: "gpt-5.2-pro",
  capabilities: [
    Completion,
    Speculation,
    Tools,
    ToolChoice,
    Vision,
    Document,
    MultipleChoices,
    OpenAIEndpointResponses,
    Thinking,
  ],
  context_length: Some(400_000),
  max_output_tokens: Some(128_000),
}

///|
/// GPT-5.2-Codex — agentic coding, Responses API only, no JSON schema (400k context, 128k output).
pub let gpt_5_2_codex : LLModel = {
  provider: openai,
  id: "gpt-5.2-codex",
  capabilities: [
    Completion,
    Speculation,
    Tools,
    ToolChoice,
    Vision,
    Document,
    MultipleChoices,
    OpenAIEndpointResponses,
    Thinking,
  ],
  context_length: Some(400_000),
  max_output_tokens: Some(128_000),
}

///|
/// GPT-5.3-Codex — agentic coding, Responses API only, no JSON schema (400k context, 128k output).
pub let gpt_5_3_codex : LLModel = {
  provider: openai,
  id: "gpt-5.3-codex",
  capabilities: [
    Completion,
    Speculation,
    Tools,
    ToolChoice,
    Vision,
    Document,
    MultipleChoices,
    OpenAIEndpointResponses,
    Thinking,
  ],
  context_length: Some(400_000),
  max_output_tokens: Some(128_000),
}

///|
/// GPT-5.4 — frontier model for complex professional work (1,050,000 context, 128k output).
pub let gpt_5_4 : LLModel = {
  provider: openai,
  id: "gpt-5.4",
  capabilities: [
    Completion,
    Speculation,
    Tools,
    ToolChoice,
    Vision,
    Document,
    MultipleChoices,
    OpenAIEndpointCompletions,
    OpenAIEndpointResponses,
    SchemaJsonBasic,
    SchemaJsonStandard,
    Thinking,
  ],
  context_length: Some(1_050_000),
  max_output_tokens: Some(128_000),
}

///|
/// GPT-5.4 mini — faster GPT-5.4 for high-volume workloads (400k context, 128k output).
pub let gpt_5_4_mini : LLModel = {
  provider: openai,
  id: "gpt-5.4-mini",
  capabilities: [
    Completion,
    Speculation,
    Tools,
    ToolChoice,
    Vision,
    Document,
    MultipleChoices,
    OpenAIEndpointCompletions,
    OpenAIEndpointResponses,
    SchemaJsonBasic,
    SchemaJsonStandard,
    Thinking,
  ],
  context_length: Some(400_000),
  max_output_tokens: Some(128_000),
}

///|
/// GPT-5.4 nano — speed/cost model for classification and sub-agents (400k context, 128k output).
pub let gpt_5_4_nano : LLModel = {
  provider: openai,
  id: "gpt-5.4-nano",
  capabilities: [
    Completion,
    Speculation,
    Tools,
    ToolChoice,
    Vision,
    Document,
    MultipleChoices,
    OpenAIEndpointCompletions,
    OpenAIEndpointResponses,
    SchemaJsonBasic,
    SchemaJsonStandard,
    Thinking,
  ],
  context_length: Some(400_000),
  max_output_tokens: Some(128_000),
}

///|
/// GPT-5.4 pro — highest-compute GPT-5.4, Responses API only (1,050,000 context, 128k output).
pub let gpt_5_4_pro : LLModel = {
  provider: openai,
  id: "gpt-5.4-pro",
  capabilities: [
    Completion,
    Speculation,
    Tools,
    ToolChoice,
    Vision,
    Document,
    MultipleChoices,
    OpenAIEndpointResponses,
    SchemaJsonBasic,
    SchemaJsonStandard,
    Thinking,
  ],
  context_length: Some(1_050_000),
  max_output_tokens: Some(128_000),
}

///|
/// GPT-5.5 — newest frontier model (1,050,000 context, 128k output).
pub let gpt_5_5 : LLModel = {
  provider: openai,
  id: "gpt-5.5",
  capabilities: [
    Completion,
    Speculation,
    Tools,
    ToolChoice,
    Vision,
    Document,
    MultipleChoices,
    OpenAIEndpointCompletions,
    OpenAIEndpointResponses,
    SchemaJsonBasic,
    SchemaJsonStandard,
    Thinking,
  ],
  context_length: Some(1_050_000),
  max_output_tokens: Some(128_000),
}

///|
/// GPT-5.5 pro — highest-compute GPT-5.5, Responses API only (1,050,000 context, 128k output).
pub let gpt_5_5_pro : LLModel = {
  provider: openai,
  id: "gpt-5.5-pro",
  capabilities: [
    Speculation,
    Tools,
    ToolChoice,
    Vision,
    Document,
    MultipleChoices,
    OpenAIEndpointResponses,
    SchemaJsonBasic,
    SchemaJsonStandard,
    Thinking,
  ],
  context_length: Some(1_050_000),
  max_output_tokens: Some(128_000),
}

///|
/// GPT Audio — audio in and out (128k context, 16k output).
pub let gpt_audio : LLModel = {
  provider: openai,
  id: "gpt-audio",
  capabilities: [
    Temperature,
    Completion,
    Tools,
    ToolChoice,
    Audio,
    OpenAIEndpointCompletions,
  ],
  context_length: Some(128_000),
  max_output_tokens: Some(16_384),
}

///|
/// GPT-4o mini Audio — cheaper audio model (128k context, 16k output).
pub let gpt_4o_mini_audio : LLModel = {
  provider: openai,
  id: "gpt-4o-mini-audio-preview",
  capabilities: [
    Temperature,
    Completion,
    Tools,
    ToolChoice,
    Audio,
    OpenAIEndpointCompletions,
  ],
  context_length: Some(128_000),
  max_output_tokens: Some(16_384),
}

///|
/// GPT-4o Audio — audio in and out (128k context, 16k output).
pub let gpt_4o_audio : LLModel = {
  provider: openai,
  id: "gpt-4o-audio-preview",
  capabilities: [
    Temperature,
    Completion,
    Tools,
    ToolChoice,
    Audio,
    OpenAIEndpointCompletions,
  ],
  context_length: Some(128_000),
  max_output_tokens: Some(16_384),
}

///|
/// text-embedding-3-small — cost-effective embeddings (8191 context).
pub let text_embedding_3_small : LLModel = {
  provider: openai,
  id: "text-embedding-3-small",
  capabilities: [Embed],
  context_length: Some(8_191),
  max_output_tokens: None,
}

///|
/// text-embedding-3-large — highest-quality embeddings (8191 context).
pub let text_embedding_3_large : LLModel = {
  provider: openai,
  id: "text-embedding-3-large",
  capabilities: [Embed],
  context_length: Some(8_191),
  max_output_tokens: None,
}

///|
/// text-embedding-ada-002 — the older ada embeddings (8191 context).
pub let text_embedding_ada_002 : LLModel = {
  provider: openai,
  id: "text-embedding-ada-002",
  capabilities: [Embed],
  context_length: Some(8_191),
  max_output_tokens: None,
}

///|
/// omni-moderation — the most capable moderation model, text + image (32768 context).
pub let omni_moderation : LLModel = {
  provider: openai,
  id: "omni-moderation-latest",
  capabilities: [Moderation, Vision],
  context_length: Some(32_768),
  max_output_tokens: None,
}

///|
/// The OpenAI models supported out of the box (Koog `OpenAIModels.supportedModels`), in the
/// source's grouping order.
pub fn openai_models() -> Array[LLModel] {
  [
    gpt_4o, gpt_4o_mini, gpt_4_1, gpt_4_1_nano, gpt_4_1_mini, o1, o3, o3_mini, o4_mini,
    gpt_5, gpt_5_mini, gpt_5_nano, gpt_5_codex, gpt_5_pro, gpt_5_1, gpt_5_1_codex,
    gpt_5_1_codex_max, gpt_5_2, gpt_5_2_pro, gpt_5_2_codex, gpt_5_3_codex, gpt_5_4,
    gpt_5_4_mini, gpt_5_4_nano, gpt_5_4_pro, gpt_5_5, gpt_5_5_pro, gpt_audio, gpt_4o_mini_audio,
    gpt_4o_audio, text_embedding_3_small, text_embedding_3_large, text_embedding_ada_002,
    omni_moderation,
  ]
}
