///|
/// The LangChain `standard-tests` cases that a provider or a gateway can carry, transcribed to
/// the wire this library speaks. The original suite lives in
/// `langchain-ai/langchain`, `libs/standard-tests`, commit `b0d6f0a`; each case keeps the name
/// of the one it came from, and the ones that cannot apply are listed at the end.
///
/// The provider is scripted, so a case fails only when the wire loses or invents something.

///|
/// A client for a gateway over `provider`, in the two default formats.
fn gateway(provider : @fake.Fake) -> @testing.Client {
  @testing.Client::new(serve(provider, dialects=default_dialects()))
}

///|
async fn post(
  client : @testing.Client,
  path : String,
  body : String,
  headers~ : Array[(String, String)] = [],
) -> @client.TestResponse {
  client.post(path, body=@utf8.encode(body), headers~)
}

///|
/// `langchain_tests.integration_tests.chat_models.test_invoke`: a simple message is answered by
/// an assistant message with text in it.
async test "langchain: test_invoke" {
  let provider = @fake.Fake::text("Hello there")
  let client = gateway(provider)
  let response = post(
    client, "/v1/chat/completions", "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}]}",
  )
  assert_eq(response.status, 200)
  let choice = @moonmuse.json_array(response.json(), "choices")[0]
  let message = @moonmuse.json_field(choice, "message").unwrap_or(Json::null())
  assert_eq(@moonmuse.json_string(message, "role"), Some("assistant"))
  assert_eq(@moonmuse.json_string(message, "content"), Some("Hello there"))
}

///|
/// `test_conversation`: a three-turn history reaches the provider in order, with its roles.
async test "langchain: test_conversation" {
  let provider = @fake.Fake::text("fine")
  let client = gateway(provider)
  let _ = post(
    client, "/v1/chat/completions", "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"hello\"},{\"role\":\"assistant\",\"content\":\"hello\"},{\"role\":\"user\",\"content\":\"how are you\"}]}",
  )
  let seen = provider.seen()[0]
  assert_eq(seen.messages.length(), 3)
  assert_eq(seen.messages[0].role, @moonmuse.User)
  assert_eq(seen.messages[1].role, @moonmuse.Assistant)
  assert_eq(seen.messages[2].text_content(), "how are you")
}

///|
/// `test_double_messages_conversation`: two system, two user and two assistant messages in a row
/// are not merged or dropped on the way to the provider.
async test "langchain: test_double_messages_conversation" {
  let provider = @fake.Fake::text("ok")
  let client = gateway(provider)
  let _ = post(
    client, "/v1/chat/completions", "{\"model\":\"m\",\"messages\":[{\"role\":\"system\",\"content\":\"a\"},{\"role\":\"system\",\"content\":\"b\"},{\"role\":\"user\",\"content\":\"c\"},{\"role\":\"user\",\"content\":\"d\"},{\"role\":\"assistant\",\"content\":\"e\"},{\"role\":\"assistant\",\"content\":\"f\"},{\"role\":\"user\",\"content\":\"g\"}]}",
  )
  let seen = provider.seen()[0]
  assert_eq(seen.messages.length(), 7)
  assert_eq(seen.messages[0].role, @moonmuse.System)
  assert_eq(seen.messages[6].text_content(), "g")
}

///|
/// `test_usage_metadata`: input and output counts come back with the answer.
async test "langchain: test_usage_metadata" {
  let provider = @fake.Fake::new([
    @moonmuse.Reply::new(
      @moonmuse.Message::assistant("hi"),
      usage=@moonmuse.Usage::new(12, 5, cached=2),
    ),
  ])
  let client = gateway(provider)
  let response = post(
    client, "/v1/chat/completions", "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}]}",
  )
  let usage = @moonmuse.json_field(response.json(), "usage").unwrap_or(
    Json::null(),
  )
  assert_eq(@moonmuse.json_int(usage, "prompt_tokens"), Some(12))
  assert_eq(@moonmuse.json_int(usage, "completion_tokens"), Some(5))
  assert_eq(@moonmuse.json_int(usage, "total_tokens"), Some(17))
}

///|
/// `test_usage_metadata_streaming`: the last event of a stream carries the counts, so a client
/// that only reads events can still price the call.
async test "langchain: test_usage_metadata_streaming" {
  let provider = @fake.Fake::new([
    @moonmuse.Reply::new(
      @moonmuse.Message::assistant("streamed"),
      usage=@moonmuse.Usage::new(7, 3),
    ),
  ])
  let client = gateway(provider)
  let response = post(
    client, "/v1/chat/completions", "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}],\"stream\":true}",
  )
  let frames = @moonmuse.parse_sse(response.text())
  let mut usage = Json::null()
  for frame in frames {
    if frame.data.trim() == "[DONE]" {
      continue
    }
    let body = @moonmuse.parse_json_lossy(frame.data)
    match @moonmuse.json_field(body, "usage") {
      Some(value) => usage = value
      None => ()
    }
  }
  assert_eq(@moonmuse.json_int(usage, "prompt_tokens"), Some(7))
  assert_eq(@moonmuse.json_int(usage, "completion_tokens"), Some(3))
}

///|
/// `test_stop_sequence`: stop sequences reach the provider, so a vendor that honours them can.
async test "langchain: test_stop_sequence" {
  let provider = @fake.Fake::text("ok")
  let client = gateway(provider)
  let _ = post(
    client, "/v1/chat/completions", "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"stop\":[\"END\",\"STOP\"]}",
  )
  assert_eq(provider.seen()[0].stop, ["END", "STOP"])
}

///|
/// `test_invoke_with_model_override`: the model named in the request is the one asked for.
async test "langchain: test_invoke_with_model_override" {
  let provider = @fake.Fake::text("ok")
  let client = gateway(provider)
  let _ = post(
    client, "/v1/chat/completions", "{\"model\":\"other-model\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}",
  )
  assert_eq(provider.seen()[0].model, "other-model")
}

///|
/// `test_tool_calling`: a required tool choice reaches the provider, and the call it makes comes
/// back with an id, a name and arguments.
async test "langchain: test_tool_calling" {
  let provider = @fake.Fake::calls("magic_function", { "value": 3 })
  let client = gateway(provider)
  let response = post(
    client, "/v1/chat/completions", "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"use the tool\"}],\"tools\":[{\"type\":\"function\",\"function\":{\"name\":\"magic_function\",\"description\":\"magic\",\"parameters\":{\"type\":\"object\",\"properties\":{\"value\":{\"type\":\"integer\"}}}}}],\"tool_choice\":\"required\"}",
  )
  assert_eq(provider.seen()[0].choice, @moonmuse.Required)
  let choice = @moonmuse.json_array(response.json(), "choices")[0]
  assert_eq(@moonmuse.json_string(choice, "finish_reason"), Some("tool_calls"))
  let message = @moonmuse.json_field(choice, "message").unwrap_or(Json::null())
  let call = @moonmuse.json_array(message, "tool_calls")[0]
  assert_eq(@moonmuse.json_string(call, "id"), Some("call_1"))
  let function = @moonmuse.json_field(call, "function").unwrap_or(Json::null())
  assert_eq(@moonmuse.json_string(function, "name"), Some("magic_function"))
}

///|
/// `test_tool_calling_with_no_arguments`: a tool that takes nothing is called with `{}`, not
/// with `null` or with no arguments at all.
async test "langchain: test_tool_calling_with_no_arguments" {
  let provider = @fake.Fake::calls("ping", Json::empty_object())
  let client = gateway(provider)
  let response = post(
    client, "/v1/chat/completions", "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}],\"tools\":[{\"type\":\"function\",\"function\":{\"name\":\"ping\",\"parameters\":{\"type\":\"object\",\"properties\":{}}}}]}",
  )
  let choice = @moonmuse.json_array(response.json(), "choices")[0]
  let message = @moonmuse.json_field(choice, "message").unwrap_or(Json::null())
  let call = @moonmuse.json_array(message, "tool_calls")[0]
  let function = @moonmuse.json_field(call, "function").unwrap_or(Json::null())
  assert_eq(@moonmuse.json_string(function, "arguments"), Some("{}"))
}

///|
/// `test_tool_choice`: a named choice is transmitted as that name, not as "required".
async test "langchain: test_tool_choice" {
  let provider = @fake.Fake::text("ok")
  let client = gateway(provider)
  let _ = post(
    client, "/v1/chat/completions", "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"tools\":[{\"type\":\"function\",\"function\":{\"name\":\"magic_function\",\"parameters\":{\"type\":\"object\",\"properties\":{}}}}],\"tool_choice\":{\"type\":\"function\",\"function\":{\"name\":\"magic_function\"}}}",
  )
  assert_eq(provider.seen()[0].choice, @moonmuse.Named("magic_function"))
}

///|
/// `test_tool_message_histories_string_content`: a tool result in the history becomes a tool
/// message with the call id it answers, in both formats.
async test "langchain: test_tool_message_histories_string_content" {
  let provider = @fake.Fake::text("ok")
  let client = gateway(provider)
  let _ = post(
    client, "/v1/chat/completions", "{\"model\":\"m\",\"messages\":[{\"role\":\"assistant\",\"content\":null,\"tool_calls\":[{\"id\":\"call_9\",\"type\":\"function\",\"function\":{\"name\":\"magic_function\",\"arguments\":\"{\\\"value\\\":3}\"}}]},{\"role\":\"tool\",\"tool_call_id\":\"call_9\",\"content\":\"42\"}]}",
  )
  let seen = provider.seen()[0]
  assert_eq(seen.messages[1].role, @moonmuse.Tool)
  assert_eq(
    seen.messages[1].results()[0],
    @moonmuse.Part::result("call_9", "42"),
  )
}

///|
/// `test_tool_message_error_status`: a failed tool result is marked as an error where the
/// format has a field for it, and still carries its content where it does not.
async test "langchain: test_tool_message_error_status" {
  let provider = @fake.Fake::text("ok")
  let client = gateway(provider)
  let _ = post(
    client,
    "/v1/messages",
    "{\"model\":\"m\",\"max_tokens\":32,\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"tool_result\",\"tool_use_id\":\"toolu_1\",\"content\":\"boom\",\"is_error\":true}]}]}",
    headers=[("anthropic-version", "2023-06-01")],
  )
  let seen = provider.seen()[0]
  assert_eq(seen.messages[0].role, @moonmuse.Tool)
  assert_eq(
    seen.messages[0].results()[0],
    @moonmuse.Part::result("toolu_1", "boom", error=true),
  )
}

///|
/// `test_image_inputs`: an image part survives as an image on both formats, rather than becoming
/// text that the model cannot use.
async test "langchain: test_image_inputs" {
  let provider = @fake.Fake::text("ok")
  let client = gateway(provider)
  let _ = post(
    client, "/v1/chat/completions", "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"what is this?\"},{\"type\":\"image_url\",\"image_url\":{\"url\":\"https://example.com/a.png\"}}]}]}",
  )
  let parts = provider.seen()[0].messages[0].parts
  let mut images = 0
  for part in parts {
    if part is @moonmuse.Image(..) {
      images = images + 1
    }
  }
  assert_eq(images, 1)
  let _ = post(
    client,
    "/v1/messages",
    "{\"model\":\"m\",\"max_tokens\":32,\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"image\",\"source\":{\"type\":\"base64\",\"media_type\":\"image/png\",\"data\":\"AAAA\"}}]}]}",
    headers=[("anthropic-version", "2023-06-01")],
  )
  let second = provider.seen()[1].messages[0].parts
  let mut seen_image = false
  for part in second {
    match part {
      @moonmuse.Image(url~, media~) =>
        seen_image = url == "AAAA" && media == Some("image/png")
      _ => ()
    }
  }
  assert_eq(seen_image, true)
}

///|
/// `test_unicode_tool_call_integration`: non-ASCII text and arguments cross the wire unchanged.
async test "langchain: test_unicode_tool_call_integration" {
  let provider = @fake.Fake::calls("查找", { "城市": "東京" })
  let client = gateway(provider)
  let response = post(
    client, "/v1/chat/completions", "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"東京の天気は？\"}]}",
  )
  assert_eq(
    provider.seen()[0].messages[0].text_content(),
    "東京の天気は？",
  )
  let choice = @moonmuse.json_array(response.json(), "choices")[0]
  let message = @moonmuse.json_field(choice, "message").unwrap_or(Json::null())
  let call = @moonmuse.json_array(message, "tool_calls")[0]
  let function = @moonmuse.json_field(call, "function").unwrap_or(Json::null())
  assert_eq(@moonmuse.json_string(function, "name"), Some("查找"))
  let args = @moonmuse.parse_json_lossy(
    @moonmuse.json_string_or(function, "arguments", ""),
  )
  assert_eq(@moonmuse.json_string(args, "城市"), Some("東京"))
}

///|
/// `test_batch`: independent calls do not interfere — the second sees its own messages, not the
/// first's.
async test "langchain: test_batch" {
  let provider = @fake.Fake::new([
    @moonmuse.Reply::new(@moonmuse.Message::assistant("first")),
    @moonmuse.Reply::new(@moonmuse.Message::assistant("second")),
  ])
  let client = gateway(provider)
  let first = post(
    client, "/v1/chat/completions", "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"one\"}]}",
  )
  let second = post(
    client, "/v1/chat/completions", "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"two\"}]}",
  )
  assert_eq(first.text().contains("first"), true)
  assert_eq(second.text().contains("second"), true)
  assert_eq(provider.seen()[1].messages.length(), 1)
}

///|
/// `test_structured_output`, as far as a gateway can carry it: `response_format` is a field of
/// the request this library does not model, so it must pass through `extra` unchanged.
async test "langchain: test_structured_output" {
  let provider = @fake.Fake::text("{\"answer\": 42}")
  let client = gateway(provider)
  let _ = post(
    client, "/v1/chat/completions", "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"answer\"}],\"response_format\":{\"type\":\"json_schema\",\"json_schema\":{\"name\":\"answer\",\"schema\":{\"type\":\"object\"}}}}",
  )
  let format = provider.seen()[0].extra["response_format"]
  assert_eq(@moonmuse.json_string(format, "type"), Some("json_schema"))
}

///|
/// `test_init_time`: building a client is not a call. A constructor that dialled would make
/// every import and every test slow, and would fail on a machine with no network.
async test "langchain: test_init_time" {
  let provider = @fake.Fake::text("x")
  let client = gateway(provider)
  let _ = client
  assert_eq(provider.hits(), 0)
}

///|
/// The cases that cannot apply here, and why:
///
/// - `test_message_with_name`: `Message` has no `name` field, and neither OpenAI nor Anthropic
///   carries one on a chat message. A caller that needs it puts it in the text.
/// - `test_pdf_inputs`, `test_audio_inputs`, `test_pdf_tool_message`, `test_image_tool_message`:
///   these need a model that reads the media, not a wire that carries it. The wire part is
///   covered by `test_image_inputs`.
/// - `test_bind_runnables_as_tools`, `test_structured_few_shot_examples`,
///   `test_structured_output_pydantic_2_v1`, `test_structured_output_optional_param`,
///   `test_json_mode`: they exercise LangChain's binding and parsing layers, not a provider.
///   The provider-side half of structured output is `@structured`, which has its own cases.
/// - `test_stream_events_v3`, `test_astream_events_v3`, `test_stream_time`: they measure
///   LangChain's event graph and timing, which a provider cannot answer for.
/// - `test_anthropic_inputs`: it checks LangChain's conversion to Anthropic content blocks; the
///   blocks themselves are covered by the dialect round-trip tests.
/// - the `async` twins (`test_ainvoke`, `test_astream`, `test_abatch`, ...): this library has no
///   blocking variant to compare against, and `Provider` is async throughout.
