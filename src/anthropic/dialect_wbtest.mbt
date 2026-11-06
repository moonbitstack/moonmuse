///|
/// The Anthropic format in both directions: a request through the wire and back, a reply
/// through a body and back, and a recorded event stream folded into one reply.

///|
/// A request that uses the fields Anthropic has: a system prompt, tools, a tool exchange.
fn sample() -> @moonmuse.Request {
  @moonmuse.Request::new(
    "claude-sonnet-4-20250514",
    [
      @moonmuse.Message::system("be brief"),
      @moonmuse.Message::user("what is 2+2?"),
      @moonmuse.Message::new(@moonmuse.Assistant, [
        @moonmuse.Part::text("checking"),
        @moonmuse.Part::call("toolu_1", "add", { "a": 2, "b": 2 }),
      ]),
      @moonmuse.Message::tool("4", id="toolu_1"),
    ],
    tools=[@moonmuse.Tool::new("add", "add numbers")],
    choice=@moonmuse.Named("add"),
    temperature=0.3,
    max_tokens=512,
    stop=["END"],
  )
}

///|
test "anthropic: a request survives the wire" {
  let request = sample()
  let call = message_call(request)
  assert_eq(call.path, "/messages")
  assert_eq(@moonmuse.json_string(call.body, "system"), Some("be brief"))
  assert_eq(@moonmuse.json_int(call.body, "max_tokens"), Some(512))
  let back = message_parse(call.body)
  assert_eq(back, request)
}

///|
test "anthropic: max_tokens defaults to 4096 when the request leaves it out" {
  let call = message_call(
    @moonmuse.Request::new("claude", [@moonmuse.Message::user("hi")]),
  )
  assert_eq(@moonmuse.json_int(call.body, "max_tokens"), Some(4096))
}

///|
test "anthropic: a tool result rides in a user message" {
  let call = message_call(
    @moonmuse.Request::new("claude", [
      @moonmuse.Message::tool("42", id="toolu_9"),
    ]),
  )
  let messages = @moonmuse.json_array(call.body, "messages")
  assert_eq(@moonmuse.json_string(messages[0], "role"), Some("user"))
  let blocks = @moonmuse.json_array(messages[0], "content")
  assert_eq(@moonmuse.json_string(blocks[0], "tool_use_id"), Some("toolu_9"))
}

///|
test "anthropic: no tool choice means no tools at all" {
  let request = @moonmuse.Request::new(
    "claude",
    [@moonmuse.Message::user("hi")],
    tools=[@moonmuse.Tool::new("f", "f")],
    choice=@moonmuse.NoTools,
  )
  let call = message_call(request)
  assert_eq(@moonmuse.json_field(call.body, "tools"), None)
}

///|
test "anthropic: a reply becomes a body and reads back the same" {
  let reply = @moonmuse.Reply::new(
    @moonmuse.Message::new(@moonmuse.Assistant, [
      @moonmuse.Part::text("four"),
      @moonmuse.Part::call("toolu_2", "add", { "a": 2 }),
    ]),
    finish=@moonmuse.Calls,
    usage=@moonmuse.Usage::new(9, 4, cached=3),
  )
  let back = message_reply(200, message_answer(reply))
  assert_eq(back.message, reply.message)
  assert_eq(back.finish, reply.finish)
  assert_eq(back.usage, reply.usage)
}

///|
/// A recorded Messages stream: a text block, a tool block, the stop reason, the end.
let recorded : String = [
  "event: message_start", "data: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_1\",\"usage\":{\"input_tokens\":11}}}",
  "", "event: content_block_start", "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}",
  "", "event: content_block_delta", "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hel\"}}",
  "", "event: content_block_delta", "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"lo\"}}",
  "", "event: content_block_start", "data: {\"type\":\"content_block_start\",\"index\":1,\"content_block\":{\"type\":\"tool_use\",\"id\":\"toolu_7\",\"name\":\"add\",\"input\":{}}}",
  "", "event: content_block_delta", "data: {\"type\":\"content_block_delta\",\"index\":1,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"{\\\"a\\\":2\"}}",
  "", "event: content_block_delta", "data: {\"type\":\"content_block_delta\",\"index\":1,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"}\"}}",
  "", "event: message_delta", "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"tool_use\"},\"usage\":{\"output_tokens\":6}}",
  "", "event: message_stop", "data: {\"type\":\"message_stop\"}", "", "",
].join("\n")

///|
test "anthropic: a recorded stream folds into one reply" {
  let turn = @moonmuse.Turn::new()
  let assembly = @moonmuse.Assembly::new()
  for frame in @moonmuse.parse_sse(recorded) {
    for delta in stream_delta(frame, turn) {
      assembly.push(delta)
    }
  }
  let reply = assembly.reply()
  assert_eq(reply.message.text_content(separator=""), "Hello")
  assert_eq(reply.finish, @moonmuse.Calls)
  assert_eq(reply.usage.input, Some(11))
  assert_eq(reply.usage.output, Some(6))
  assert_eq(
    reply.message.calls()[0],
    @moonmuse.Part::call("toolu_7", "add", { "a": 2 }),
  )
}

///|
test "anthropic: the server writes events the client reads back" {
  let reply = @moonmuse.Reply::new(
    @moonmuse.Message::new(@moonmuse.Assistant, [
      @moonmuse.Part::text("ok"),
      @moonmuse.Part::call("toolu_3", "add", { "a": 1 }),
    ]),
    finish=@moonmuse.Calls,
    usage=@moonmuse.Usage::new(2, 1),
  )
  let write_turn = @moonmuse.Turn::new()
  let frames = []
  for
    delta in [
      @moonmuse.Delta::Text("ok"),
      @moonmuse.Delta::CallStart(id="toolu_3", name="add"),
      @moonmuse.Delta::CallArgs(id="toolu_3", chunk="{\"a\":1}"),
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
  assert_eq(back.message.text_content(separator=""), "ok")
  assert_eq(
    back.message.calls()[0],
    @moonmuse.Part::call("toolu_3", "add", { "a": 1 }),
  )
}
