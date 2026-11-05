// The full Koog LLMParams surface (temperature/maxTokens/numberOfChoices/speculation/schema/
// toolChoice/user/includeThoughts/thinkingBudget/additionalProperties).

///|
test "llm params: the full Koog parameter surface is carried" {
  let p : LLMParams = {
    temperature: Some(0.7),
    max_tokens: Some(1024),
    number_of_choices: Some(3),
    speculation: Some("draft"),
    schema: Some(JsonStandard(name="out", schema="object".to_json())),
    tool_choice: Some(Named("search")),
    user: Some("lfanke"),
    include_thoughts: Some(true),
    thinking_budget: Some(2000),
    additional_properties: Some({ "seed": (233).to_json() }),
  }
  assert_eq(p.number_of_choices, Some(3))
  assert_eq(p.speculation, Some("draft"))
  assert_eq(p.tool_choice, Some(Named("search")))
  assert_eq(p.user, Some("lfanke"))
  assert_eq(p.include_thoughts, Some(true))
  assert_eq(p.thinking_budget, Some(2000))
}

///|
test "llm params: default leaves every override unset" {
  let d = LLMParams::default()
  assert_eq(d.temperature, None)
  assert_eq(d.number_of_choices, None)
  assert_eq(d.speculation, None)
  assert_eq(d.schema, None)
  assert_eq(d.tool_choice, None)
  assert_eq(d.user, None)
  assert_eq(d.include_thoughts, None)
  assert_eq(d.thinking_budget, None)
  assert_eq(d.additional_properties, None)
}

///|
test "llm params: the tool-choice modes are distinct" {
  assert_not_eq((Auto : ToolChoice), NoTools)
  assert_not_eq((Required : ToolChoice), Auto)
  assert_eq((Named("x") : ToolChoice), Named("x"))
  assert_not_eq((Named("x") : ToolChoice), Named("y"))
}
