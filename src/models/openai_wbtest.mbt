// The OpenAI model catalog (Koog `OpenAIModels`).

///|
test "openai models: ids, limits, and capabilities match the Koog catalog" {
  // GPT-4o: 128k context, 16k output, both OpenAI endpoints, no Thinking.
  assert_eq(gpt_4o.id, "gpt-4o")
  assert_eq(gpt_4o.provider, openai)
  assert_eq(gpt_4o.context_length, Some(128_000))
  assert_eq(gpt_4o.max_output_tokens, Some(16_384))
  assert_eq(gpt_4o.supports(Vision), true)
  assert_eq(gpt_4o.supports(OpenAIEndpointCompletions), true)
  assert_eq(gpt_4o.supports(OpenAIEndpointResponses), true)
  assert_eq(gpt_4o.supports(Thinking), false)
  // GPT-4.1: the million-token context window.
  assert_eq(gpt_4_1.id, "gpt-4.1")
  assert_eq(gpt_4_1.context_length, Some(1_047_576))
  assert_eq(gpt_4_1.max_output_tokens, Some(32_768))
  // o-series reasoning models carry Thinking; o3-mini drops Vision/Document.
  assert_eq(o1.supports(Thinking), true)
  assert_eq(o3.max_output_tokens, Some(100_000))
  assert_eq(o3_mini.supports(Thinking), true)
  assert_eq(o3_mini.supports(Vision), false)
  assert_eq(o3_mini.supports(Document), false)
  // GPT-5 family: 400k context, Responses-only Codex/Pro variants.
  assert_eq(gpt_5.context_length, Some(400_000))
  assert_eq(gpt_5.max_output_tokens, Some(128_000))
  assert_eq(gpt_5_codex.supports(OpenAIEndpointResponses), true)
  assert_eq(gpt_5_codex.supports(OpenAIEndpointCompletions), false)
  assert_eq(gpt_5_pro.max_output_tokens, Some(272_000))
  // GPT-5.4 / 5.5: the 1.05M-token frontier models.
  assert_eq(gpt_5_4.context_length, Some(1_050_000))
  assert_eq(gpt_5_5.id, "gpt-5.5")
  assert_eq(gpt_5_5.context_length, Some(1_050_000))
  assert_eq(gpt_5_5_pro.supports(Completion), false)
  // Audio, embeddings, moderation groups.
  assert_eq(gpt_audio.supports(Audio), true)
  assert_eq(text_embedding_3_large.id, "text-embedding-3-large")
  assert_eq(text_embedding_3_large.capabilities, [Embed])
  assert_eq(text_embedding_3_large.max_output_tokens, None)
  assert_eq(omni_moderation.id, "omni-moderation-latest")
  assert_eq(omni_moderation.supports(Moderation), true)
  assert_eq(omni_moderation.supports(Vision), true)
  assert_eq(omni_moderation.context_length, Some(32_768))
}

///|
test "openai models: the supported list has every catalogued model, all under the OpenAI provider" {
  let models = openai_models()
  assert_eq(models.length(), 34)
  for m in models {
    assert_eq(m.provider, openai)
  }
  // First and last of the source's grouping order.
  assert_eq(models[0].id, "gpt-4o")
  assert_eq(models[models.length() - 1].id, "omni-moderation-latest")
}
