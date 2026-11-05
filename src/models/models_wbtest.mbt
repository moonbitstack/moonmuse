///|
test "a model reports the capabilities it declares" {
  let m = deepseek_v4_flash
  assert_eq(m.provider, deepseek)
  assert_eq(m.id, "deepseek-v4-flash")
  assert_true(m.supports(Tools))
  assert_true(m.supports(ToolChoice))
  assert_false(m.supports(Vision))
}

///|
test "providers are distinct identities" {
  assert_not_eq(openai, deepseek)
  assert_eq(deepseek.display, "DeepSeek")
}
