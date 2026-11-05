// The Anthropic (Claude) model catalog (Koog `AnthropicModels`): each model's provider-side id,
// its declared capabilities, and its context / output-token limits. Every Claude model has a
// 200k context; the 3-series tops out at 4,096 output tokens and carries no Document capability,
// while 3.5 and later add Document and larger output windows.
// Source: prompt/.../clients/anthropic/AnthropicModels.kt.

///|
/// Claude 3 Opus.
pub let claude_3_opus : LLModel = {
  provider: anthropic,
  id: "claude-3-opus",
  capabilities: [Completion, Temperature, Tools, ToolChoice, Vision],
  context_length: Some(200000),
  max_output_tokens: Some(4096),
}

///|
/// Claude 3 Haiku.
pub let claude_3_haiku : LLModel = {
  provider: anthropic,
  id: "claude-3-haiku",
  capabilities: [Completion, Temperature, Tools, ToolChoice, Vision],
  context_length: Some(200000),
  max_output_tokens: Some(4096),
}

///|
/// Claude 3.5 Sonnet.
pub let claude_3_5_sonnet : LLModel = {
  provider: anthropic,
  id: "claude-3-5-sonnet",
  capabilities: [Completion, Temperature, Tools, ToolChoice, Vision, Document],
  context_length: Some(200000),
  max_output_tokens: Some(8192),
}

///|
/// Claude 3.5 Haiku.
pub let claude_3_5_haiku : LLModel = {
  provider: anthropic,
  id: "claude-3-5-haiku",
  capabilities: [Completion, Temperature, Tools, ToolChoice, Vision, Document],
  context_length: Some(200000),
  max_output_tokens: Some(8192),
}

///|
/// Claude 3.7 Sonnet.
pub let claude_3_7_sonnet : LLModel = {
  provider: anthropic,
  id: "claude-3-7-sonnet",
  capabilities: [Completion, Temperature, Tools, ToolChoice, Vision, Document],
  context_length: Some(200000),
  max_output_tokens: Some(64000),
}

///|
/// Claude Sonnet 4.
pub let claude_sonnet_4 : LLModel = {
  provider: anthropic,
  id: "claude-sonnet-4-0",
  capabilities: [Completion, Temperature, Tools, ToolChoice, Vision, Document],
  context_length: Some(200000),
  max_output_tokens: Some(64000),
}

///|
/// Claude Opus 4.
pub let claude_opus_4 : LLModel = {
  provider: anthropic,
  id: "claude-opus-4-0",
  capabilities: [Completion, Temperature, Tools, ToolChoice, Vision, Document],
  context_length: Some(200000),
  max_output_tokens: Some(32000),
}

///|
/// Claude Opus 4.1.
pub let claude_opus_4_1 : LLModel = {
  provider: anthropic,
  id: "claude-opus-4-1",
  capabilities: [Completion, Temperature, Tools, ToolChoice, Vision, Document],
  context_length: Some(200000),
  max_output_tokens: Some(32000),
}

///|
/// Claude Sonnet 4.5.
pub let claude_sonnet_4_5 : LLModel = {
  provider: anthropic,
  id: "claude-sonnet-4-5",
  capabilities: [Completion, Temperature, Tools, ToolChoice, Vision, Document],
  context_length: Some(200000),
  max_output_tokens: Some(64000),
}
