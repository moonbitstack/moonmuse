// The Claude model catalog (Koog `AnthropicModels`).

///|
test "anthropic models: ids, limits, and capabilities match the Koog catalog" {
  // 3.5 Sonnet: 200k context, 8k output, gains the Document capability.
  assert_eq(claude_3_5_sonnet.id, "claude-3-5-sonnet")
  assert_eq(claude_3_5_sonnet.provider, anthropic)
  assert_eq(claude_3_5_sonnet.context_length, Some(200000))
  assert_eq(claude_3_5_sonnet.max_output_tokens, Some(8192))
  assert_eq(claude_3_5_sonnet.supports(Document), true)
  assert_eq(claude_3_5_sonnet.supports(Tools), true)
  // 3 Opus: 4k output and no Document.
  assert_eq(claude_3_opus.id, "claude-3-opus")
  assert_eq(claude_3_opus.max_output_tokens, Some(4096))
  assert_eq(claude_3_opus.supports(Document), false)
  // 4.5 Sonnet: 64k output.
  assert_eq(claude_sonnet_4_5.id, "claude-sonnet-4-5")
  assert_eq(claude_sonnet_4_5.max_output_tokens, Some(64000))
  // Opus 4 / 4.1: 32k output.
  assert_eq(claude_opus_4.max_output_tokens, Some(32000))
  assert_eq(claude_opus_4_1.id, "claude-opus-4-1")
}
