///|
test "to_llm_message maps a plain user message" {
  let m = to_llm_message(@moonmuse.Message::user("hello"))
  assert_eq(m.role, @moonllm.User)
  assert_eq(m.content.to_text(), "hello")
  assert_true(m.tool_calls is None)
}

///|
test "to_llm_message maps a tool result to a tool-role message linked by id" {
  let m = to_llm_message(
    @moonmuse.Message::tool_result(tool="add", output="5", id="c1"),
  )
  assert_eq(m.role, @moonllm.Tool)
  assert_eq(m.content.to_text(), "5")
  assert_eq(m.tool_call_id, Some("c1"))
}

///|
test "to_llm_message maps an assistant tool call" {
  let m = to_llm_message({
    role: Assistant,
    parts: [@moonmuse.ToolCall(id=Some("c1"), tool="add", args={ "a": 2 })],
    finish_reason: None,
    meta: None,
  })
  assert_eq(m.role, @moonllm.Assistant)
  guard m.tool_calls is Some(tcs) else { fail("expected tool calls") }
  assert_eq(tcs.length(), 1)
  assert_eq(tcs[0].id, "c1")
  assert_eq(tcs[0].function.name, "add")
}

///|
test "to_llm_tool builds a JSON-schema object from the descriptor" {
  let d : @toolbox.ToolDescriptor = {
    name: "add",
    description: "add two ints",
    required_parameters: [
      { name: "a", description: "x", ptype: @toolbox.TInteger, },
      { name: "b", description: "y", ptype: @toolbox.TInteger, },
    ],
    optional_parameters: [],
  }
  let t = to_llm_tool(d)
  assert_eq(t.name, "add")
  // parameters is { "type": "object", "properties": {a,b}, "required": [a,b] }
  match t.parameters {
    Object(m) => {
      assert_eq(m.get("type"), Some(Json::string("object")))
      guard m.get("required") is Some(Array(req)) else {
        fail("no required array")
      }
      assert_eq(req.length(), 2)
    }
    _ => fail("parameters is not an object")
  }
}

///|
test "from_llm_message maps text and tool calls back to Koog parts" {
  let llm_msg : @moonllm.Message = {
    role: @moonllm.Assistant,
    content: Str(""),
    tool_calls: Some([
      { id: "c1", function: { name: "add", arguments: "{\"a\":2,\"b\":3}", }, },
    ]),
    tool_call_id: None,
    name: None,
  }
  let m = from_llm_message(llm_msg, Some("tool_calls"))
  assert_eq(m.role, Assistant)
  let calls = m.tool_calls()
  assert_eq(calls.length(), 1)
  guard calls[0] is @moonmuse.ToolCall(tool=name, ..) else {
    fail("no tool call")
  }
  assert_eq(name, "add")
  assert_eq(m.finish_reason, Some("tool_calls"))
}

///|
test "from_moderation_response maps flags and confidence scores to a Koog verdict" {
  let resp : @moonllm.ModerationResponse = {
    model: "omni-moderation-latest",
    results: [
      {
        flagged: true,
        categories: { "hate": true, "violence": false },
        category_scores: { "hate": 0.92, "violence": 0.03 },
      },
    ],
  }
  let verdict = from_moderation_response(resp)
  assert_eq(verdict.is_harmful, true)
  assert_eq(verdict.is_category_detected("hate"), true)
  assert_eq(verdict.is_category_detected("violence"), false)
  guard verdict.categories.get("hate") is Some(hate) else {
    fail("no hate category")
  }
  assert_eq(hate.detected, true)
  assert_eq(hate.confidence_score, Some(0.92))
}

///|
test "from_moderation_response is safe when the response carries no results" {
  let resp : @moonllm.ModerationResponse = { model: "m", results: [], }
  assert_eq(from_moderation_response(resp).is_harmful, false)
}

///|
test "moderation_input joins the prompt's text parts" {
  let p = @moonmuse.PromptBuilder::new().system("policy").user("bad text").build()
  assert_eq(moderation_input(p), "policy\nbad text")
}

///|
test "from_chat_response_all maps every choice to its own Koog message" {
  let resp : @moonllm.ChatResponse = {
    id: "x",
    object: "chat.completion",
    created: 0L,
    model: "m",
    choices: [
      {
        index: 0,
        message: {
          role: @moonllm.Assistant,
          content: Str("first"),
          tool_calls: None,
          tool_call_id: None,
          name: None,
        },
        finish_reason: Some("stop"),
      },
      {
        index: 1,
        message: {
          role: @moonllm.Assistant,
          content: Str("second"),
          tool_calls: None,
          tool_call_id: None,
          name: None,
        },
        finish_reason: Some("length"),
      },
    ],
    usage: None,
    system_fingerprint: None,
  }
  let msgs = from_chat_response_all(resp)
  assert_eq(msgs.length(), 2)
  assert_eq(msgs[0].text_content(), "first")
  assert_eq(msgs[1].text_content(), "second")
  assert_eq(msgs[1].finish_reason, Some("length"))
}

///|
/// From the bytes an endpoint actually sends to the message the agent goes on with: the `usage`
/// object used to be dropped on the floor here.
test "a reply's token counts survive from the wire to the message" {
  let body =
    #|{"id":"chatcmpl-233","object":"chat.completion","created":1,
    #| "model":"deepseek-v4-flash-0801",
    #| "choices":[{"index":0,"message":{"role":"assistant","content":"hhh"},
    #|             "finish_reason":"stop"}],
    #| "usage":{"prompt_tokens":66,"completion_tokens":6,"total_tokens":72}}
  let resp : @moonllm.ChatResponse = @json.from_json(@json.parse(body)) catch {
    e => fail("could not decode the response: " + e.to_string())
  }
  let m = from_chat_response(resp)
  assert_eq(m.text_content(), "hhh")
  guard m.meta is Some(meta) else { fail("the reply carries no meta") }
  assert_eq(meta.input_tokens, Some(66))
  assert_eq(meta.output_tokens, Some(6))
  assert_eq(meta.total_tokens, Some(72))
  // The model the provider says served it, which need not be the one asked for.
  assert_eq(meta.model, Some("deepseek-v4-flash-0801"))
  assert_eq(m.total_tokens(), Some(72))
}

///|
/// An endpoint that reports no usage leaves the counts unset — not zero, which would read as a
/// call that cost nothing.
test "a reply without usage carries the model but no counts" {
  let resp : @moonllm.ChatResponse = {
    id: "x",
    object: "chat.completion",
    created: 0L,
    model: "m",
    choices: [
      {
        index: 0,
        message: {
          role: @moonllm.Assistant,
          content: Str("emm"),
          tool_calls: None,
          tool_call_id: None,
          name: None,
        },
        finish_reason: Some("stop"),
      },
    ],
    usage: None,
    system_fingerprint: None,
  }
  guard from_chat_response(resp).meta is Some(meta) else {
    fail("the reply carries no meta")
  }
  assert_eq(meta.total_tokens, None)
  assert_eq(meta.model, Some("m"))
}

///|
test "every choice of a multi-choice reply carries the response's usage" {
  let body =
    #|{"id":"c","object":"chat.completion","created":1,"model":"m",
    #| "choices":[{"index":0,"message":{"role":"assistant","content":"one"},"finish_reason":"stop"},
    #|            {"index":1,"message":{"role":"assistant","content":"two"},"finish_reason":"stop"}],
    #| "usage":{"prompt_tokens":10,"completion_tokens":4,"total_tokens":14}}
  let resp : @moonllm.ChatResponse = @json.from_json(@json.parse(body)) catch {
    e => fail("could not decode the response: " + e.to_string())
  }
  let msgs = from_chat_response_all(resp)
  assert_eq(msgs.length(), 2)
  assert_eq(msgs.map(m => m.total_tokens()), [Some(14), Some(14)])
}

///|
test "to_chat_request maps tool_choice=Required and a schema to the wire request" {
  let schema : Json = {
    "type": "object",
    "properties": { "answer": { "type": "string" } },
  }
  let params : @moonmuse.LLMParams = {
    ..@moonmuse.LLMParams::default(),
    tool_choice: Some(@moonmuse.Required),
    schema: Some(@moonmuse.JsonStandard(name="out", schema~)),
  }
  let p = @moonmuse.PromptBuilder::new(params~).user("2+3?").build()
  let req = to_chat_request(p, @models.deepseek_v4_flash, [])
  guard req.to_json() is Object(obj) else {
    fail("request json is not an object")
  }
  assert_eq(obj.get("tool_choice"), Some(Json::string("required")))
  assert_eq(
    obj.get("response_format"),
    Some(
      Json::object({
        "type": Json::string("json_schema"),
        "json_schema": Json::object({
          "name": Json::string("out"),
          "schema": schema,
        }),
      }),
    ),
  )
}

///|
test "to_chat_request maps a named tool-choice to the function shape" {
  let params : @moonmuse.LLMParams = {
    ..@moonmuse.LLMParams::default(),
    tool_choice: Some(@moonmuse.Named("search")),
  }
  let p = @moonmuse.PromptBuilder::new(params~).user("find it").build()
  let req = to_chat_request(p, @models.deepseek_v4_flash, [])
  assert_eq(req.tool_choice, Some(@moonllm.Function("search")))
}

///|
test "to_chat_request leaves tool_choice and response_format unset by default" {
  let p = @moonmuse.PromptBuilder::new().user("hi").build()
  let req = to_chat_request(p, @models.deepseek_v4_flash, [])
  assert_true(req.tool_choice is None)
  assert_true(req.response_format is None)
}

///|
test "to_chat_request carries the model, messages, and tools" {
  let p = @moonmuse.PromptBuilder::new().system("be helpful").user("2+3?").build()
  let d : @toolbox.ToolDescriptor = {
    name: "add",
    description: "add",
    required_parameters: [
      { name: "a", description: "x", ptype: @toolbox.TInteger, },
    ],
    optional_parameters: [],
  }
  let req = to_chat_request(p, @models.deepseek_v4_flash, [d])
  assert_eq(req.model, "deepseek-v4-flash")
  assert_eq(req.messages.length(), 2)
  guard req.tools is Some(ts) else { fail("expected tools on the request") }
  assert_eq(ts.length(), 1)
  assert_eq(ts[0].name, "add")
}
