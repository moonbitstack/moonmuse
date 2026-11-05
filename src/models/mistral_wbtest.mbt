// The Mistral AI model catalog (Koog `MistralAIModels`).

///|
test "mistral models: ids, contexts, and capabilities match the Koog catalog" {
  // Medium 3: multimodal, 128k context, no output limit.
  assert_eq(mistral_medium_3.id, "mistral-medium-latest")
  assert_eq(mistral_medium_3.provider, mistralai)
  assert_eq(mistral_medium_3.context_length, Some(128_000))
  assert_eq(mistral_medium_3.max_output_tokens, None)
  assert_eq(mistral_medium_3.supports(Vision), true)
  assert_eq(mistral_medium_3.supports(Document), true)
  // Small 2: 32k context, JSON basic only, no vision.
  assert_eq(mistral_small_2.context_length, Some(32_000))
  assert_eq(mistral_small_2.supports(SchemaJsonStandard), false)
  assert_eq(mistral_small_2.supports(Vision), false)
  // Magistral: reasoning (Thinking) + vision.
  assert_eq(magistral_medium_1_2.supports(Thinking), true)
  assert_eq(magistral_medium_1_2.supports(Vision), true)
  // Codestral: the 256k coding model.
  assert_eq(codestral.id, "codestral-latest")
  assert_eq(codestral.context_length, Some(256_000))
  // Embedding + moderation models.
  assert_eq(mistral_embed.capabilities, [Embed])
  assert_eq(codestral_embed.capabilities, [Embed])
  assert_eq(mistral_moderation.capabilities, [Moderation])
  assert_eq(mistral_moderation.context_length, Some(8_000))
}

///|
test "mistral models: the supported list has all nine models under the MistralAI provider" {
  let models = mistral_models()
  assert_eq(models.length(), 9)
  for m in models {
    assert_eq(m.provider, mistralai)
  }
  assert_eq(models[0].id, "mistral-medium-latest")
  assert_eq(models[models.length() - 1].id, "mistral-moderation-2411")
}
