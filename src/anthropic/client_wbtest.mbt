// The Anthropic Messages API request format.

///|
fn anthropic_test_model() -> @models.LLModel {
  {
    provider: @models.anthropic,
    id: "claude-3-5-sonnet",
    capabilities: [],
    context_length: None,
    max_output_tokens: None,
  }
}

///|
test "anthropic request: the system prompt is lifted, max_tokens defaults, messages mapped" {
  let prompt = @moonmuse.PromptBuilder::new()
    .system("you are helpful")
    .user("hi")
    .build()
  let req = to_anthropic_request(prompt, anthropic_test_model(), [])
  let expected : Json = Json::object({
    "model": Json::string("claude-3-5-sonnet"),
    "max_tokens": (4096).to_json(),
    "messages": Json::array([
      Json::object({
        "role": Json::string("user"),
        "content": Json::string("hi"),
      }),
    ]),
    "system": Json::string("you are helpful"),
  })
  assert_eq(req, expected)
}

///|
test "anthropic request: params max_tokens and temperature are carried" {
  let params : @moonmuse.LLMParams = {
    ..@moonmuse.LLMParams::default(),
    temperature: Some(0.5),
    max_tokens: Some(512),
  }
  let prompt = @moonmuse.PromptBuilder::new(params~).user("go").build()
  let req = to_anthropic_request(prompt, anthropic_test_model(), [])
  let expected : Json = Json::object({
    "model": Json::string("claude-3-5-sonnet"),
    "max_tokens": (512).to_json(),
    "messages": Json::array([
      Json::object({
        "role": Json::string("user"),
        "content": Json::string("go"),
      }),
    ]),
    "temperature": 0.5.to_json(),
  })
  assert_eq(req, expected)
}

///|
test "anthropic request: tool_choice maps to Anthropic's typed object" {
  let named = @moonmuse.PromptBuilder::new(params={
      ..@moonmuse.LLMParams::default(),
      tool_choice: Some(@moonmuse.Named("search")),
    })
    .user("go")
    .build()
  guard to_anthropic_request(named, anthropic_test_model(), []) is Object(obj) else {
    fail("request is not an object")
  }
  assert_eq(
    obj.get("tool_choice"),
    Some(
      Json::object({
        "type": Json::string("tool"),
        "name": Json::string("search"),
      }),
    ),
  )
  let required = @moonmuse.PromptBuilder::new(params={
      ..@moonmuse.LLMParams::default(),
      tool_choice: Some(@moonmuse.Required),
    })
    .user("go")
    .build()
  guard to_anthropic_request(required, anthropic_test_model(), []) is Object(r) else {
    fail("request is not an object")
  }
  assert_eq(
    r.get("tool_choice"),
    Some(Json::object({ "type": Json::string("any") })),
  )
}

///|
test "anthropic client: constructs and reports the Anthropic provider" {
  let client = AnthropicClient::new(api_key="test-key")
  let c : &@moonmuse.LLMClient = client
  assert_eq(c.provider(), @models.anthropic)
  // A custom gateway base_url and anthropic-version are accepted by the builder.
  let gateway = AnthropicClient::new(
    api_key="k",
    base_url="https://gateway.example/v1",
    version="2024-01-01",
  )
  let g : &@moonmuse.LLMClient = gateway
  assert_eq(g.provider(), @models.anthropic)
}

///|
test "anthropic response: text and tool_use blocks become a Koog assistant message" {
  let response = @json.parse(
    (
      #|{"id":"msg_1","type":"message","role":"assistant","content":[{"type":"text","text":"hello"},{"type":"tool_use","id":"tu_1","name":"search","input":{"q":"x"}}],"stop_reason":"tool_use"}
    ),
  )
  let msg = from_anthropic_response(response)
  assert_eq(msg.role, Assistant)
  assert_eq(msg.finish_reason, Some("tool_use"))
  assert_eq(msg.parts.length(), 2)
  match msg.parts[0] {
    Text(t) => assert_eq(t, "hello")
    _ => abort("expected a text part")
  }
  match msg.parts[1] {
    ToolCall(id~, tool~, args~) => {
      assert_eq(id, Some("tu_1"))
      assert_eq(tool, "search")
      assert_eq(args, @json.parse("{\"q\":\"x\"}"))
    }
    _ => abort("expected a tool call")
  }
}

///|
/// Anthropic reports the two counts separately and no total, so the total is their sum.
test "anthropic response: usage becomes the reply's token counts" {
  let response = @json.parse(
    (
      #|{"id":"msg_1","type":"message","role":"assistant","model":"claude-3-5-sonnet-20241022","content":[{"type":"text","text":"hi"}],"stop_reason":"end_turn","usage":{"input_tokens":66,"output_tokens":6}}
    ),
  )
  guard from_anthropic_response(response).meta is Some(meta) else {
    fail("the reply carries no meta")
  }
  assert_eq(meta.input_tokens, Some(66))
  assert_eq(meta.output_tokens, Some(6))
  assert_eq(meta.total_tokens, Some(72))
  assert_eq(meta.model, Some("claude-3-5-sonnet-20241022"))
}

///|
test "anthropic response: no usage block leaves the counts unset" {
  let response = @json.parse(
    (
      #|{"id":"msg_1","type":"message","role":"assistant","content":[{"type":"text","text":"hi"}],"stop_reason":"end_turn"}
    ),
  )
  guard from_anthropic_response(response).meta is Some(meta) else {
    fail("the reply carries no meta")
  }
  assert_eq(meta.total_tokens, None)
  assert_eq(meta.model, None)
}
