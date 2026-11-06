///|
/// The Gemini format in both directions. Two directions are checked on the wire rather
/// than on the shared types, because Gemini has no tool-call id: a body read into a
/// request and written out again must produce the same body.

///|
test "gemini: a generateContent body survives a read and a write" {
  let body = @moonmuse.parse_json_lossy(
    "{\"contents\":[{\"role\":\"user\",\"parts\":[{\"text\":\"hi\"}]}],\"systemInstruction\":{\"parts\":[{\"text\":\"be brief\"}]},\"generationConfig\":{\"temperature\":0.4,\"maxOutputTokens\":64,\"stopSequences\":[\"END\"]}}",
  )
  let request = generate_parse(body, "gemini-2.5-flash")
  let again = generate_parse(generate_call(request).body, "gemini-2.5-flash")
  assert_eq(again, request)
  assert_eq(again.temperature, Some(0.4))
  assert_eq(again.max_tokens, Some(64))
  assert_eq(again.stop, ["END"])
}

///|
test "gemini: the model sits in the path" {
  let call = generate_call(
    @moonmuse.Request::new("gemini-2.5-pro", [@moonmuse.Message::user("hi")]),
  )
  assert_eq(call.path, "/models/gemini-2.5-pro:generateContent")
  assert_eq(model_of(call.path), "gemini-2.5-pro")
}

///|
test "gemini: the assistant role is called model" {
  let call = generate_call(
    @moonmuse.Request::new("m", [
      @moonmuse.Message::assistant("hello"),
      @moonmuse.Message::user("hi"),
    ]),
  )
  let contents = @moonmuse.json_array(call.body, "contents")
  assert_eq(@moonmuse.json_string(contents[0], "role"), Some("model"))
}

///|
test "gemini: a tool result names the tool it answers" {
  let request = @moonmuse.Request::new("m", [
    @moonmuse.Message::new(@moonmuse.Assistant, [
      @moonmuse.Part::call("call_0", "add", { "a": 1 }),
    ]),
    @moonmuse.Message::tool("2", id="call_0"),
  ])
  let call = generate_call(request)
  let contents = @moonmuse.json_array(call.body, "contents")
  let parts = @moonmuse.json_array(contents[1], "parts")
  let response = @moonmuse.json_field(parts[0], "functionResponse").unwrap_or(
    Json::null(),
  )
  assert_eq(@moonmuse.json_string(response, "name"), Some("add"))
}

///|
test "gemini: a reply becomes a body and reads back the same" {
  let reply = @moonmuse.Reply::new(
    @moonmuse.Message::new(@moonmuse.Assistant, [
      @moonmuse.Part::text("four"),
      @moonmuse.Part::call("call_0", "add", { "a": 2 }),
    ]),
    finish=@moonmuse.Stop,
    usage=@moonmuse.Usage::new(7, 3, cached=1),
  )
  let back = generate_reply(200, generate_answer(reply))
  assert_eq(back.message, reply.message)
  assert_eq(back.finish, reply.finish)
  assert_eq(back.usage, reply.usage)
}

///|
/// A recorded stream: two text chunks, the counts, the stop.
let recorded : String = [
  "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"Hel\"}]},\"index\":0}]}",
  "", "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"lo\"}]},\"index\":0}],\"usageMetadata\":{\"promptTokenCount\":5,\"candidatesTokenCount\":2}}",
  "", "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[]},\"finishReason\":\"STOP\",\"index\":0}],\"usageMetadata\":{\"promptTokenCount\":5,\"candidatesTokenCount\":2}}",
  "", "",
].join("\n")

///|
test "gemini: a recorded stream folds into one reply" {
  let turn = @moonmuse.Turn::new()
  let assembly = @moonmuse.Assembly::new()
  for frame in @moonmuse.parse_sse(recorded) {
    for delta in stream_delta(frame, turn) {
      assembly.push(delta)
    }
  }
  let reply = assembly.reply()
  assert_eq(reply.message.text_content(separator=""), "Hello")
  assert_eq(reply.finish, @moonmuse.Stop)
  assert_eq(reply.usage.input, Some(5))
  assert_eq(reply.usage.output, Some(2))
}

///|
test "gemini: the server writes chunks the client reads back" {
  let reply = @moonmuse.Reply::new(
    @moonmuse.Message::new(@moonmuse.Assistant, [@moonmuse.Part::text("hi")]),
    finish=@moonmuse.Stop,
    usage=@moonmuse.Usage::new(1, 1),
  )
  let write_turn = @moonmuse.Turn::new()
  let frames = []
  for delta in [@moonmuse.Delta::Text("hi"), @moonmuse.Delta::Done(reply)] {
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
  assert_eq(assembly.reply().message.text_content(separator=""), "hi")
}

///|
test "gemini: embedding requests read their input" {
  let route = @moonmuse.Route::new(
    @moonmuse.Embed,
    "POST",
    "/v1beta/models/text-embedding-004:embedContent",
  )
  let asked = @moonmuse.Dialect::parse(
    dialect,
    route,
    @moonmuse.parse_json_lossy(
      "{\"content\":{\"parts\":[{\"text\":\"hello\"}]}}",
    ),
  )
  assert_eq(
    asked,
    @moonmuse.Asked::Embed(model="text-embedding-004", inputs=["hello"]),
  )
}
