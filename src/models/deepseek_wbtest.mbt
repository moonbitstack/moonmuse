// The DeepSeek model catalog (Koog `DeepSeekModels`).

///|
test "deepseek models: ids, limits, and capabilities match the Koog catalog" {
  // V4 Flash: 1M context, 384k output, full capability set.
  assert_eq(deepseek_v4_flash.id, "deepseek-v4-flash")
  assert_eq(deepseek_v4_flash.provider, deepseek)
  assert_eq(deepseek_v4_flash.context_length, Some(1_000_000))
  assert_eq(deepseek_v4_flash.max_output_tokens, Some(384_000))
  // The fidelity fix: Flash carries SchemaJsonBasic and MultipleChoices (previously missing).
  assert_eq(deepseek_v4_flash.supports(SchemaJsonBasic), true)
  assert_eq(deepseek_v4_flash.supports(SchemaJsonStandard), true)
  assert_eq(deepseek_v4_flash.supports(MultipleChoices), true)
  assert_eq(deepseek_v4_flash.supports(Thinking), true)
  // V4 Pro: same limits and capabilities.
  assert_eq(deepseek_v4_pro.id, "deepseek-v4-pro")
  assert_eq(deepseek_v4_pro.context_length, Some(1_000_000))
  assert_eq(deepseek_v4_pro.max_output_tokens, Some(384_000))
  assert_eq(deepseek_v4_pro.supports(MultipleChoices), true)
}

///|
test "deepseek models: the supported list has both V4 models under the DeepSeek provider" {
  let models = deepseek_models()
  assert_eq(models.length(), 2)
  for m in models {
    assert_eq(m.provider, deepseek)
  }
  assert_eq(models[0].id, "deepseek-v4-flash")
  assert_eq(models[1].id, "deepseek-v4-pro")
}
