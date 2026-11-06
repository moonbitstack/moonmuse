///|
/// The bodies this library writes, checked against the official description of the OpenAI API.
/// The field tables come from `scripts/openapi/gen_fields.py`, which reads `openai-openapi` at
/// a pinned commit; these cases fail if a body carries a key the description does not have.

///|
/// The keys of a JSON object, or none when the value is not one.
fn keys_of(value : Json) -> Array[String] {
  let out = []
  match value {
    Object(fields) =>
      for key, _ in fields {
        out.push(key)
      }
    _ => ()
  }
  out
}

///|
/// Assert every key is in `allowed`, naming the offending key when it is not.
fn assert_documented(
  body : Json,
  allowed : Array[String],
  what : String,
) -> Unit raise {
  for key in keys_of(body) {
    let mut known = false
    for name in allowed {
      if name == key {
        known = true
      }
    }
    if !known {
      fail(what + " writes an undocumented field: " + key)
    }
  }
}

///|
test "openapi: a plain chat request uses documented fields only" {
  let request = @moonmuse.Request::new(
    "gpt-4o-mini",
    [@moonmuse.Message::user("hi")],
    temperature=0.2,
    max_tokens=64,
    stop=["END"],
  )
  let body = chat_call(request).body
  assert_documented(body, chat_completion_request_fields, "a chat request")
  assert_documented(
    @moonmuse.json_array(body, "messages")[0],
    chat_message_user_fields,
    "a user message",
  )
}

///|
test "openapi: a request with tools, a choice and an image uses documented fields only" {
  let extra = Map([])
  extra["user"] = Json::string("u-1")
  let request = @moonmuse.Request::new(
    "gpt-4o",
    [
      @moonmuse.Message::system("be brief"),
      @moonmuse.Message::new(@moonmuse.User, [
        @moonmuse.Part::text("what is this?"),
        @moonmuse.Image(url="https://example.com/a.png", media=None),
      ]),
      @moonmuse.Message::new(@moonmuse.Assistant, [
        @moonmuse.Part::call("call_1", "add", { "a": 1 }),
      ]),
      @moonmuse.Message::tool("2", id="call_1"),
    ],
    tools=[
      @moonmuse.Tool::new("add", "add numbers", schema={ "type": "object" }),
    ],
    choice=@moonmuse.Named("add"),
    extra~,
  )
  let body = chat_call(request).body
  assert_documented(body, chat_completion_request_fields, "a chat request")
  let messages = @moonmuse.json_array(body, "messages")
  assert_documented(messages[0], chat_message_system_fields, "a system message")
  assert_documented(messages[1], chat_message_user_fields, "a user message")
  assert_documented(
    messages[2],
    chat_message_assistant_fields,
    "an assistant message",
  )
  assert_documented(messages[3], chat_message_tool_fields, "a tool message")
  assert_documented(
    @moonmuse.json_array(messages[2], "tool_calls")[0],
    chat_message_tool_call_fields,
    "a tool call",
  )
  assert_documented(
    @moonmuse.json_array(body, "tools")[0],
    chat_completion_tool_fields,
    "a tool declaration",
  )
}

///|
test "openapi: an embeddings request uses documented fields only" {
  let request = @moonmuse.object_json([
    ("model", Json::string("text-embedding-3-small")),
    ("input", @moonmuse.strings_json(["a", "b"])),
  ])
  assert_documented(request, embedding_request_fields, "an embeddings request")
}

///|
test "openapi: the tool arguments are a string, as the description says" {
  let request = @moonmuse.Request::new("m", [
    @moonmuse.Message::new(@moonmuse.Assistant, [
      @moonmuse.Part::call("c1", "add", { "a": 1 }),
    ]),
  ])
  let body = chat_call(request).body
  let messages = @moonmuse.json_array(body, "messages")
  let call = @moonmuse.json_array(messages[0], "tool_calls")[0]
  let function = @moonmuse.json_field(call, "function").unwrap_or(Json::null())
  assert_eq(@moonmuse.json_string(call, "type"), Some("function"))
  assert_eq(
    @moonmuse.json_field(function, "arguments") is Some(String(_)),
    true,
  )
}

///|
test "openapi: a fully populated response parses, and unknown fields survive in raw" {
  let body = @moonmuse.parse_json_lossy(
    "{\"id\":\"chatcmpl-1\",\"object\":\"chat.completion\",\"created\":1700000000,\"model\":\"gpt-4o\",\"system_fingerprint\":\"fp_1\",\"service_tier\":\"default\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"hello\",\"refusal\":null,\"annotations\":[]},\"finish_reason\":\"stop\",\"logprobs\":null}],\"usage\":{\"prompt_tokens\":5,\"completion_tokens\":2,\"total_tokens\":7,\"prompt_tokens_details\":{\"cached_tokens\":1}}}",
  )
  let reply = chat_reply(200, body)
  assert_eq(reply.text(), "hello")
  assert_eq(reply.usage.input, Some(5))
  assert_eq(reply.usage.output, Some(2))
  assert_eq(reply.usage.cached, Some(1))
  // Everything the shared vocabulary does not model stays reachable.
  assert_eq(
    @moonmuse.json_string(reply.raw, "system_fingerprint"),
    Some("fp_1"),
  )
  assert_eq(@moonmuse.json_string(reply.raw, "service_tier"), Some("default"))
}

///|
test "openapi: the generated tables are not empty and cover every writer" {
  assert_eq(chat_completion_request_fields.length() > 30, true)
  for
    field in [
      "model", "messages", "tools", "tool_choice", "temperature", "max_tokens", "stop",
    ] {
    let mut found = false
    for name in chat_completion_request_fields {
      if name == field {
        found = true
      }
    }
    assert_eq(found, true)
  }
  assert_eq(chat_completion_response_fields.contains("choices"), true)
  assert_eq(chat_completion_choice_fields.contains("finish_reason"), true)
  assert_eq(embedding_response_fields.contains("data"), true)
}
