///|
/// Ollama's stream is newline-delimited JSON: one object per line, the last one flagged
/// `done`. Text arrives on `message.content`, a tool call arrives whole, and the counts
/// come with the last line.

///|
/// The deltas one line carries.
pub fn stream_delta(
  frame : @moonmuse.Frame,
  turn : @moonmuse.Turn,
) -> Array[@moonmuse.Delta] raise @moonmuse.LlmError {
  if turn.has_slot("done") {
    return []
  }
  let body = frame.json()
  let deltas = []
  match @moonmuse.json_object(body, "message") {
    Some(fields) => {
      let message = Json::object(fields)
      let text = @moonmuse.json_string_or(message, "content", "")
      if text != "" {
        turn.add_slot("text", text)
        deltas.push(@moonmuse.Delta::Text(text))
      }
      for call in @moonmuse.json_array(message, "tool_calls") {
        let function = @moonmuse.json_field(call, "function").unwrap_or(
          Json::null(),
        )
        let index = turn.add_num("calls", 1) - 1
        let id = "call_" + index.to_string()
        let key = "call:" + index.to_string()
        let args = @moonmuse.json_field(function, "arguments").unwrap_or(
          Json::object(Map([])),
        )
        turn.set_slot(key + ":id", id)
        turn.set_slot(
          key + ":name",
          @moonmuse.json_string_or(function, "name", ""),
        )
        turn.set_slot(key + ":args", args.stringify())
        deltas.push(
          @moonmuse.Delta::CallStart(
            id~,
            name=@moonmuse.json_string_or(function, "name", ""),
          ),
        )
        deltas.push(@moonmuse.Delta::CallArgs(id~, chunk=args.stringify()))
      }
    }
    None => ()
  }
  if @moonmuse.json_bool(body, "done").unwrap_or(false) {
    turn.set_slot("done", "1")
    match @moonmuse.json_int(body, "prompt_eval_count") {
      Some(value) => turn.set_num("usage:input", value)
      None => ()
    }
    match @moonmuse.json_int(body, "eval_count") {
      Some(value) => turn.set_num("usage:output", value)
      None => ()
    }
    deltas.push(
      @moonmuse.Delta::Done(
        reply_of(
          turn,
          @moonmuse.Finish::of(
            @moonmuse.json_string_or(body, "done_reason", "stop"),
          ),
        ),
      ),
    )
  }
  deltas
}

///|
/// The reply the accumulated lines describe.
pub fn reply_of(
  turn : @moonmuse.Turn,
  finish : @moonmuse.Finish,
) -> @moonmuse.Reply {
  let parts = []
  let text = turn.slot("text")
  if text != "" {
    parts.push(@moonmuse.Part::text(text))
  }
  for index = 0; index < turn.num("calls"); index = index + 1 {
    let key = "call:" + index.to_string()
    parts.push(
      @moonmuse.Part::call(
        turn.slot(key + ":id"),
        turn.slot(key + ":name"),
        @moonmuse.parse_json_lossy(turn.slot(key + ":args")),
      ),
    )
  }
  let usage : @moonmuse.Usage = {
    input: if turn.num("usage:input") > 0 {
      Some(turn.num("usage:input"))
    } else {
      None
    },
    output: if turn.num("usage:output") > 0 {
      Some(turn.num("usage:output"))
    } else {
      None
    },
    cached: None,
  }
  @moonmuse.Reply::new(
    @moonmuse.Message::new(@moonmuse.Assistant, parts),
    finish~,
    usage~,
    raw=Json::null(),
  )
}

///|
/// The lines that carry one delta out.
pub fn stream_frame(
  delta : @moonmuse.Delta,
  turn : @moonmuse.Turn,
) -> Array[@moonmuse.Frame] {
  match delta {
    @moonmuse.Delta::Text(text) =>
      [line(@moonmuse.object_json([("content", Json::string(text))]), false)]
    @moonmuse.Delta::CallStart(id~, name~) => {
      let index = turn.add_num("calls", 1) - 1
      turn.set_slot("id:" + id, index.to_string())
      // Ollama names a tool call in the same object as its arguments, which arrive on a
      // later line: the name has to be kept until then.
      turn.set_slot("call:" + index.to_string() + ":name", name)
      []
    }
    @moonmuse.Delta::CallArgs(id~, chunk~) => {
      let index = @moonmuse.parse_int_lossy(turn.slot("id:" + id))
      let name = turn.slot("call:" + index.to_string() + ":name")
      [
        line(
          @moonmuse.object_json([
            (
              "tool_calls",
              Json::array([
                @moonmuse.object_json([
                  (
                    "function",
                    @moonmuse.object_json([
                      ("name", Json::string(name)),
                      ("arguments", @moonmuse.parse_json_lossy(chunk)),
                    ]),
                  ),
                ]),
              ]),
            ),
          ]),
          false,
        ),
      ]
    }
    @moonmuse.Delta::Done(reply) =>
      [
        line(
          @moonmuse.object_json([("content", Json::string(""))]),
          true,
          reason=finish_code(reply.finish),
          input?=reply.usage.input,
          output?=reply.usage.output,
        ),
      ]
  }
}

///|
/// One streamed line: a `message` object, the `done` flag, and on the last line the
/// reason and the counts.
fn line(
  message : Json,
  done : Bool,
  reason~ : String = "stop",
  input? : Int32,
  output? : Int32,
) -> @moonmuse.Frame {
  let fields = [
    (
      "message",
      @moonmuse.object_json([
        ("role", Json::string("assistant")),
        (
          "tool_calls",
          @moonmuse.json_field(message, "tool_calls").unwrap_or(Json::null()),
        ),
        (
          "content",
          Json::string(@moonmuse.json_string_or(message, "content", "")),
        ),
      ]),
    ),
    ("done", Json::boolean(done)),
  ]
  if done {
    fields.push(("done_reason", Json::string(reason)))
    match input {
      Some(value) =>
        fields.push(("prompt_eval_count", Json::number(value.to_double())))
      None => ()
    }
    match output {
      Some(value) =>
        fields.push(("eval_count", Json::number(value.to_double())))
      None => ()
    }
  }
  @moonmuse.Frame::new(@moonmuse.object_json(fields).stringify())
}
