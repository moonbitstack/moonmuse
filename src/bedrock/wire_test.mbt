///|
/// The Converse body and answer, checked against the shapes AWS documents: a system prompt is
/// a field of its own, a tool is a `toolSpec` with a JSON schema inside it, and a tool result
/// answers the call it names.

///|
test "bedrock: a request becomes a Converse body" {
  let request = @moonmuse.Request::new(
    "anthropic.claude",
    [@moonmuse.Message::system("be brief"), @moonmuse.Message::user("hello")],
    temperature=0.2,
    max_tokens=64,
    stop=["\n\n"],
    tools=[
      @moonmuse.Tool::new("add", "add two numbers", schema={
        "type": "object",
        "properties": { "a": { "type": "number" } },
      }),
    ],
  )
  let body = @bedrock.converse_body(request)
  let messages = @moonmuse.json_array(body, "messages")
  assert_eq(messages.length(), 1)
  assert_eq(@moonmuse.json_string(messages[0], "role"), Some("user"))
  let blocks = @moonmuse.json_array(messages[0], "content")
  assert_eq(@moonmuse.json_string(blocks[0], "text"), Some("hello"))
  // The system prompt is not a message: Converse keeps it beside them.
  let system = @moonmuse.json_array(body, "system")
  assert_eq(@moonmuse.json_string(system[0], "text"), Some("be brief"))
  let config = @moonmuse.json_field(body, "inferenceConfig").unwrap_or(
    Json::null(),
  )
  assert_eq(@moonmuse.json_int(config, "maxTokens"), Some(64))
  assert_eq(@moonmuse.json_number(config, "temperature"), Some(0.2))
  let tools = @moonmuse.json_array(
    @moonmuse.json_field(body, "toolConfig").unwrap_or(Json::null()),
    "tools",
  )
  assert_eq(
    @moonmuse.json_string(
      @moonmuse.json_field(tools[0], "toolSpec").unwrap_or(Json::null()),
      "name",
    ),
    Some("add"),
  )
}

///|
test "bedrock: a tool result goes back as the answer to its call" {
  let request = @moonmuse.Request::new("m", [
    @moonmuse.Message::user("add 2 and 3"),
    @moonmuse.Message::new(@moonmuse.Assistant, [
      @moonmuse.Part::call(
        "call_1",
        "add",
        @moonmuse.parse_json_lossy("{\"a\":2}"),
      ),
    ]),
    @moonmuse.Message::new(@moonmuse.Tool, [
      @moonmuse.Part::result("call_1", "5", error=false),
    ]),
  ])
  let body = @bedrock.converse_body(request)
  let messages = @moonmuse.json_array(body, "messages")
  assert_eq(messages.length(), 3)
  let result = @moonmuse.json_field(
    @moonmuse.json_array(messages[2], "content")[0],
    "toolResult",
  ).unwrap_or(Json::null())
  assert_eq(@moonmuse.json_string(result, "toolUseId"), Some("call_1"))
  assert_eq(@moonmuse.json_string(result, "status"), Some("success"))
}

///|
test "bedrock: an answer becomes a reply" {
  let body = @moonmuse.parse_json_lossy(
    "{\"output\":{\"message\":{\"role\":\"assistant\",\"content\":[{\"text\":\"hi there\"},{\"toolUse\":{\"toolUseId\":\"t1\",\"name\":\"add\",\"input\":{\"a\":2}}}]}},\"stopReason\":\"tool_use\",\"usage\":{\"inputTokens\":7,\"outputTokens\":3,\"cacheReadInputTokens\":1}}",
  )
  let reply = @bedrock.converse_reply(body)
  assert_eq(reply.text(), "hi there")
  assert_eq(reply.finish, @moonmuse.Calls)
  assert_eq(reply.usage.input, Some(7))
  assert_eq(reply.usage.cached, Some(1))
  let calls = reply.calls()
  assert_eq(calls.length(), 1)
  match calls[0] {
    @moonmuse.Part::Call(name~, args~, ..) => {
      assert_eq(name, "add")
      assert_eq(@moonmuse.json_int(args, "a"), Some(2))
    }
    _ => abort("expected a call")
  }
}
