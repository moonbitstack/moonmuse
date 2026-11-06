///|
/// The Ollama format in both directions: chat request through the wire and back, a reply
/// through a body and back, and a recorded newline-delimited stream folded into one reply.

///|
test "ollama: a chat request survives the wire" {
  let request = @moonmuse.Request::new(
    "llama3.2",
    [@moonmuse.Message::system("be brief"), @moonmuse.Message::user("hi")],
    temperature=0.5,
    max_tokens=64,
    stop=["END"],
  )
  let call = chat_call(request)
  assert_eq(call.path, "/api/chat")
  assert_eq(chat_parse(call.body), request)
}

///|
test "ollama: options nest under options" {
  let call = chat_call(
    @moonmuse.Request::new(
      "m",
      [@moonmuse.Message::user("hi")],
      temperature=0.1,
    ),
  )
  let options = @moonmuse.json_field(call.body, "options").unwrap_or(
    Json::null(),
  )
  assert_eq(@moonmuse.json_number(options, "temperature"), Some(0.1))
}

///|
test "ollama: a reply becomes a body and reads back the same" {
  let reply = @moonmuse.Reply::new(
    @moonmuse.Message::new(@moonmuse.Assistant, [
      @moonmuse.Part::text("four"),
      @moonmuse.Part::call("call_0", "add", { "a": 2 }),
    ]),
    finish=@moonmuse.Calls,
    usage=@moonmuse.Usage::new(8, 3),
  )
  let back = chat_reply(200, chat_answer(reply))
  assert_eq(back.message, reply.message)
  assert_eq(back.finish, reply.finish)
  assert_eq(back.usage, reply.usage)
}

///|
/// A recorded `/api/chat` stream.
let recorded : String = [
  "{\"message\":{\"role\":\"assistant\",\"content\":\"Hel\"},\"done\":false}", "{\"message\":{\"role\":\"assistant\",\"content\":\"lo\"},\"done\":false}",
  "{\"message\":{\"role\":\"assistant\",\"content\":\"\"},\"done\":true,\"done_reason\":\"stop\",\"prompt_eval_count\":4,\"eval_count\":2}",
  "",
].join("\n")

///|
test "ollama: a recorded stream folds into one reply" {
  let turn = @moonmuse.Turn::new()
  let assembly = @moonmuse.Assembly::new()
  for frame in @moonmuse.parse_ndjson(recorded) {
    for delta in stream_delta(frame, turn) {
      assembly.push(delta)
    }
  }
  let reply = assembly.reply()
  assert_eq(reply.message.text_content(separator=""), "Hello")
  assert_eq(reply.finish, @moonmuse.Stop)
  assert_eq(reply.usage.input, Some(4))
  assert_eq(reply.usage.output, Some(2))
}

///|
test "ollama: the server writes lines the client reads back" {
  let reply = @moonmuse.Reply::new(
    @moonmuse.Message::new(@moonmuse.Assistant, [@moonmuse.Part::text("ok")]),
    finish=@moonmuse.Stop,
    usage=@moonmuse.Usage::new(2, 1),
  )
  let write_turn = @moonmuse.Turn::new()
  let frames = []
  for delta in [@moonmuse.Delta::Text("ok"), @moonmuse.Delta::Done(reply)] {
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
  assert_eq(back.usage.input, Some(2))
}

///|
test "ollama: the routes cover the six endpoints" {
  assert_eq(@moonmuse.Dialect::routes(dialect).length(), 6)
}
