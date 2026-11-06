///|
/// The two directions of the OpenAI format, checked against each other. A request that
/// goes out and comes back must be the same request; a reply that becomes a body and is
/// read back must be the same reply. The streaming cases replay a recorded stream.

///|
/// A request that uses every field this library models.
fn sample_request() -> @moonmuse.Request {
  let extra = Map([])
  extra["user"] = Json::string("u-1")
  @moonmuse.Request::new(
    "gpt-4o-mini",
    [
      @moonmuse.Message::system("be brief"),
      @moonmuse.Message::user("what is 2+2?"),
      @moonmuse.Message::new(@moonmuse.Assistant, [
        @moonmuse.Part::text("let me check"),
        @moonmuse.Part::call("call_1", "add", { "a": 2, "b": 2 }),
      ]),
      @moonmuse.Message::tool("4", id="call_1"),
    ],
    tools=[
      @moonmuse.Tool::new("add", "add two numbers", schema={
        "type": "object",
        "properties": { "a": { "type": "number" }, "b": { "type": "number" } },
        "required": ["a", "b"],
      }),
    ],
    choice=@moonmuse.Named("add"),
    temperature=0.2,
    max_tokens=256,
    stop=["END"],
    extra~,
  )
}

///|
test "openai: request survives a round trip through the wire" {
  let request = sample_request()
  let call = chat_call(request)
  assert_eq(call.verb, "POST")
  assert_eq(call.path, "/chat/completions")
  let back = chat_parse(call.body)
  assert_eq(back, request)
}

///|
test "openai: a plain text message stays a plain string" {
  let call = chat_call(
    @moonmuse.Request::new("m", [@moonmuse.Message::user("hi")]),
  )
  let messages = @moonmuse.json_array(call.body, "messages")
  assert_eq(messages.length(), 1)
  assert_eq(@moonmuse.json_string(messages[0], "content"), Some("hi"))
}

///|
test "openai: an image message becomes a typed content array" {
  let message = @moonmuse.Message::new(@moonmuse.User, [
    @moonmuse.Part::text("what is this?"),
    @moonmuse.Image(url="https://example.com/cat.png", media=None),
  ])
  let call = chat_call(@moonmuse.Request::new("m", [message]))
  let messages = @moonmuse.json_array(call.body, "messages")
  let content = @moonmuse.json_array(messages[0], "content")
  assert_eq(content.length(), 2)
  assert_eq(@moonmuse.json_string(content[1], "type"), Some("image_url"))
}

///|
test "openai: an inline image gets its media type" {
  let message = @moonmuse.Message::new(@moonmuse.User, [
    @moonmuse.Image(url="AAAA", media=Some("image/png")),
  ])
  let call = chat_call(@moonmuse.Request::new("m", [message]))
  let messages = @moonmuse.json_array(call.body, "messages")
  let content = @moonmuse.json_array(messages[0], "content")
  let url = match @moonmuse.json_field(content[0], "image_url") {
    Some(inner) => @moonmuse.json_string(inner, "url").unwrap_or("")
    None => ""
  }
  assert_eq(url, "data:image/png;base64,AAAA")
}

///|
test "openai: extra fields reach the body and come back" {
  let request = sample_request()
  let call = chat_call(request)
  assert_eq(@moonmuse.json_string(call.body, "user"), Some("u-1"))
  assert_eq(chat_parse(call.body).extra["user"], Json::string("u-1"))
}

///|
test "openai: a reply becomes a body and reads back the same" {
  let reply = @moonmuse.Reply::new(
    @moonmuse.Message::new(@moonmuse.Assistant, [
      @moonmuse.Part::text("the answer is 4"),
      @moonmuse.Part::call("call_2", "add", { "a": 2, "b": 2 }),
    ]),
    finish=@moonmuse.Calls,
    usage=@moonmuse.Usage::new(10, 5, cached=2),
  )
  let body = chat_answer(reply)
  let back = chat_reply(200, body)
  assert_eq(back.message, reply.message)
  assert_eq(back.finish, reply.finish)
  assert_eq(back.usage, reply.usage)
}

///|
test "openai: a non-success status is an error, not an empty reply" {
  let result = try {
    let _ = chat_reply(
      429,
      @moonmuse.parse_json_lossy("{\"error\":{\"message\":\"slow down\"}}"),
    )
    None
  } catch {
    @moonmuse.Status(code~, ..) => Some(code)
    _ => None
  }
  assert_eq(result, Some(429))
}

///|
/// A recorded stream: text in two chunks, then a tool call in three, then the finish.
let recorded_stream : String = [
  "data: {\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":\"Hel\"},\"finish_reason\":null}]}",
  "", "data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"lo\"},\"finish_reason\":null}]}",
  "", "data: {\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_9\",\"type\":\"function\",\"function\":{\"name\":\"add\",\"arguments\":\"\"}}]},\"finish_reason\":null}]}",
  "", "data: {\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"{\\\"a\\\":\"}}]},\"finish_reason\":null}]}",
  "", "data: {\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"2}\"}}]},\"finish_reason\":null}]}",
  "", "data: {\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"tool_calls\"}],\"usage\":{\"prompt_tokens\":7,\"completion_tokens\":3}}",
  "", "data: [DONE]", "", "",
].join("\n")

///|
test "openai: a recorded stream assembles into one reply" {
  let turn = @moonmuse.Turn::new()
  let assembly = @moonmuse.Assembly::new()
  for frame in @moonmuse.parse_sse(recorded_stream) {
    for delta in stream_delta(frame, turn) {
      assembly.push(delta)
    }
  }
  let reply = assembly.reply()
  assert_eq(reply.message.text_content(separator=""), "Hello")
  assert_eq(reply.finish, @moonmuse.Calls)
  assert_eq(reply.usage.input, Some(7))
  assert_eq(reply.usage.output, Some(3))
  let calls = reply.message.calls()
  assert_eq(calls.length(), 1)
  assert_eq(calls[0], @moonmuse.Part::call("call_9", "add", { "a": 2 }))
}

///|
test "openai: a stream split before its last blank line still closes" {
  let turn = @moonmuse.Turn::new()
  let reader = @moonmuse.Sse::new()
  let assembly = @moonmuse.Assembly::new()
  let cut = recorded_stream.length() - 3
  for
    batch in [
      reader.feed(recorded_stream.exact_view(start=0, end=cut)),
      reader.feed(recorded_stream.exact_view(start=cut)),
      reader.finish(),
    ] {
    for frame in batch {
      for delta in stream_delta(frame, turn) {
        assembly.push(delta)
      }
    }
  }
  assert_eq(assembly.reply().message.text_content(separator=""), "Hello")
}

///|
test "openai: the server writes frames the client reads back" {
  let reply = @moonmuse.Reply::new(
    @moonmuse.Message::new(@moonmuse.Assistant, [
      @moonmuse.Part::text("hi"),
      @moonmuse.Part::call("c1", "add", { "a": 1 }),
    ]),
    finish=@moonmuse.Stop,
    usage=@moonmuse.Usage::new(4, 2),
  )
  let write_turn = @moonmuse.Turn::new()
  let frames = []
  for
    delta in [
      @moonmuse.Delta::Text("hi"),
      @moonmuse.Delta::CallStart(id="c1", name="add"),
      @moonmuse.Delta::CallArgs(id="c1", chunk="{\"a\":1}"),
      @moonmuse.Delta::Done(reply),
    ] {
    for frame in stream_frame(delta, write_turn) {
      frames.push(frame)
    }
  }
  let read_turn = @moonmuse.Turn::new()
  let assembly = @moonmuse.Assembly::new()
  for frame in frames {
    for delta in stream_delta(frame, read_turn) {
      assembly.push(delta)
    }
  }
  let back = assembly.reply()
  assert_eq(back.message.text_content(separator=""), "hi")
  assert_eq(back.message.calls().length(), 1)
  assert_eq(back.finish, @moonmuse.Stop)
}

///|
test "openai: the server decodes the endpoints it serves" {
  let chat_route = @moonmuse.Route::new(
    @moonmuse.Chat,
    "POST",
    "/v1/chat/completions",
  )
  let chat_body = @moonmuse.parse_json_lossy(
    "{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}",
  )
  assert_eq(
    @moonmuse.Dialect::parse(dialect, chat_route, chat_body),
    @moonmuse.Asked::Chat(
      @moonmuse.Request::new("gpt-4o", [@moonmuse.Message::user("hi")]),
    ),
  )
  let embed_route = @moonmuse.Route::new(
    @moonmuse.Embed,
    "POST",
    "/v1/embeddings",
  )
  let embed_body = @moonmuse.parse_json_lossy(
    "{\"model\":\"text-embedding-3-small\",\"input\":[\"a\",\"b\"]}",
  )
  assert_eq(
    @moonmuse.Dialect::parse(dialect, embed_route, embed_body),
    @moonmuse.Asked::Embed(model="text-embedding-3-small", inputs=["a", "b"]),
  )
}

///|
test "openai: the model list decodes" {
  let list = models_answer([@moonmuse.ModelInfo::new("gpt-4o")])
  assert_eq(@moonmuse.json_array(list, "data").length(), 1)
}
