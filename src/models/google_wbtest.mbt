// The Google Gemini model catalog (Koog `GoogleModels`).

///|
test "google models: ids, limits, and capabilities match the Koog catalog" {
  // 2.0 Flash-Lite: full capabilities, 8k output, no Thinking.
  assert_eq(gemini_2_0_flash_lite_001.id, "gemini-2.0-flash-lite-001")
  assert_eq(gemini_2_0_flash_lite_001.provider, google)
  assert_eq(gemini_2_0_flash_lite_001.context_length, Some(1_048_576))
  assert_eq(gemini_2_0_flash_lite_001.max_output_tokens, Some(8_192))
  assert_eq(gemini_2_0_flash_lite_001.supports(Vision), true)
  assert_eq(gemini_2_0_flash_lite_001.supports(Audio), true)
  assert_eq(gemini_2_0_flash_lite_001.supports(MultipleChoices), true)
  assert_eq(gemini_2_0_flash_lite_001.supports(Thinking), false)
  // 2.5 Pro / Flash: 65k output and the Thinking capability.
  assert_eq(gemini_2_5_pro.id, "gemini-2.5-pro")
  assert_eq(gemini_2_5_pro.max_output_tokens, Some(65_536))
  assert_eq(gemini_2_5_pro.supports(Thinking), true)
  assert_eq(gemini_2_5_flash.supports(Thinking), true)
  // 2.5 Flash-Lite: full but no Thinking.
  assert_eq(gemini_2_5_flash_lite.supports(Thinking), false)
  // 3.x preview / flash generation.
  assert_eq(gemini_3_1_pro_preview.id, "gemini-3.1-pro-preview")
  assert_eq(gemini_3_5_flash.supports(Thinking), true)
  // Embedding model: Embed only, no output-token limit.
  assert_eq(gemini_embedding_001.id, "gemini-embedding-001")
  assert_eq(gemini_embedding_001.capabilities, [Embed])
  assert_eq(gemini_embedding_001.context_length, Some(2_048))
  assert_eq(gemini_embedding_001.max_output_tokens, None)
}

///|
test "google models: the supported list has every catalogued model under the Google provider" {
  let models = google_models()
  assert_eq(models.length(), 10)
  for m in models {
    assert_eq(m.provider, google)
  }
  assert_eq(models[0].id, "gemini-2.0-flash-lite-001")
  assert_eq(models[models.length() - 1].id, "gemini-embedding-001")
}
