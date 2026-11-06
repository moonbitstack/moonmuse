///|
/// Reading a chat-completions stream and writing one. A chunk carries a slice of text, a
/// slice of a tool call's arguments, or the finish reason; the reader accumulates all
/// three in `Turn` so the reply after the last frame equals the reply a non-streamed call
/// would have produced.

///|
/// The deltas one chunk carries. The last chunk closes the stream with `Done`, so a
/// caller that only reads deltas still gets the final reply.
pub fn stream_delta(
  frame : @moonmuse.Frame,
  turn : @moonmuse.Turn,
) -> Array[@moonmuse.Delta] raise @moonmuse.LlmError {
  if turn.has_slot("done") {
    return []
  }
  if frame.data.trim() == "[DONE]" {
    turn.set_slot("done", "1")
    return [@moonmuse.Done(reply_of(turn, @moonmuse.Stop))]
  }
  let body = frame.json()
  if body is Object(fields) {
    match fields.get("usage") {
      Some(usage) => remember_usage(turn, usage)
      None => ()
    }
    match fields.get("model") {
      Some(String(model)) => turn.set_slot("model", model)
      _ => ()
    }
  }
  let choices = @moonmuse.json_array(body, "choices")
  if choices.is_empty() {
    return []
  }
  let choice = choices[0]
  let deltas = []
  match @moonmuse.json_object(choice, "delta") {
    Some(fields) => {
      let delta = Json::object(fields)
      match @moonmuse.json_string(delta, "content") {
        Some(text) =>
          if text != "" {
            turn.add_slot("text", text)
            deltas.push(@moonmuse.Delta::Text(text))
          }
        None => ()
      }
      for item in @moonmuse.json_array(delta, "tool_calls") {
        let index = @moonmuse.json_int(item, "index").unwrap_or(0)
        let key = "call:" + index.to_string()
        let id = @moonmuse.json_string_or(item, "id", "")
        let function = match @moonmuse.json_object(item, "function") {
          Some(inner) => Json::object(inner)
          None => Json::null()
        }
        if id != "" {
          turn.set_slot(key + ":id", id)
          turn.set_slot(
            key + ":name",
            @moonmuse.json_string_or(function, "name", ""),
          )
          if turn.num("calls") < index + 1 {
            turn.set_num("calls", index + 1)
          }
          deltas.push(
            @moonmuse.CallStart(
              id~,
              name=@moonmuse.json_string_or(function, "name", ""),
            ),
          )
        }
        match @moonmuse.json_string(function, "arguments") {
          Some(chunk) =>
            if chunk != "" {
              turn.add_slot(key + ":args", chunk)
              deltas.push(@moonmuse.CallArgs(id=turn.slot(key + ":id"), chunk~))
            }
          None => ()
        }
      }
    }
    None => ()
  }
  match @moonmuse.json_string(choice, "finish_reason") {
    Some(reason) => {
      turn.set_slot("done", "1")
      deltas.push(@moonmuse.Done(reply_of(turn, @moonmuse.Finish::of(reason))))
    }
    None => ()
  }
  deltas
}

///|
/// Remember the usage a chunk reported; the counts of a streamed call arrive on the
/// last chunk, after the text.
fn remember_usage(turn : @moonmuse.Turn, usage : Json) -> Unit {
  match @moonmuse.json_int(usage, "prompt_tokens") {
    Some(value) => turn.set_num("usage:input", value)
    None => ()
  }
  match @moonmuse.json_int(usage, "completion_tokens") {
    Some(value) => turn.set_num("usage:output", value)
    None => ()
  }
  match @moonmuse.json_object(usage, "prompt_tokens_details") {
    Some(fields) =>
      match @moonmuse.json_int(Json::object(fields), "cached_tokens") {
        Some(value) => turn.set_num("usage:cached", value)
        None => ()
      }
    None => ()
  }
}

///|
/// The reply the accumulated chunks describe.
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
    let id = turn.slot(key + ":id")
    if id != "" {
      parts.push(
        @moonmuse.Part::call(
          id,
          turn.slot(key + ":name"),
          @moonmuse.parse_json_lossy(turn.slot(key + ":args")),
        ),
      )
    }
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
    cached: if turn.num("usage:cached") > 0 {
      Some(turn.num("usage:cached"))
    } else {
      None
    },
  }
  @moonmuse.Reply::new(
    @moonmuse.Message::new(@moonmuse.Assistant, parts),
    finish~,
    usage~,
    raw=Json::null(),
  )
}

///|
/// The frames that carry one delta out, in the shape a chat-completions stream uses.
pub fn stream_frame(
  delta : @moonmuse.Delta,
  turn : @moonmuse.Turn,
) -> Array[@moonmuse.Frame] {
  match delta {
    @moonmuse.Text(text) =>
      [
        @moonmuse.Frame::new(
          chunk_json(
            @moonmuse.object_json([("content", Json::string(text))]),
            Json::null(),
          ),
        ),
      ]
    @moonmuse.CallStart(id~, name~) => {
      let index = turn.add_num("calls", 1) - 1
      turn.set_slot("id:" + id, index.to_string())
      [
        @moonmuse.Frame::new(
          chunk_json(
            @moonmuse.object_json([
              (
                "tool_calls",
                Json::array([
                  @moonmuse.object_json([
                    ("index", Json::number(index.to_double())),
                    ("id", Json::string(id)),
                    ("type", Json::string("function")),
                    (
                      "function",
                      @moonmuse.object_json([
                        ("name", Json::string(name)),
                        ("arguments", Json::string("")),
                      ]),
                    ),
                  ]),
                ]),
              ),
            ]),
            Json::null(),
          ),
        ),
      ]
    }
    @moonmuse.CallArgs(id~, chunk~) => {
      let index = @moonmuse.parse_int_lossy(turn.slot("id:" + id))
      [
        @moonmuse.Frame::new(
          chunk_json(
            @moonmuse.object_json([
              (
                "tool_calls",
                Json::array([
                  @moonmuse.object_json([
                    ("index", Json::number(index.to_double())),
                    (
                      "function",
                      @moonmuse.object_json([("arguments", Json::string(chunk))]),
                    ),
                  ]),
                ]),
              ),
            ]),
            Json::null(),
          ),
        ),
      ]
    }
    @moonmuse.Done(reply) =>
      [
        @moonmuse.Frame::new(
          // The last chunk carries the usage, as the endpoint does with
          // `stream_options.include_usage`; a client pricing the call reads it there.
          chunk_json(
            Json::empty_object(),
            Json::string(finish_code(reply.finish)),
            usage=usage_json(reply.usage),
          ),
        ),
        @moonmuse.Frame::new("[DONE]"),
      ]
  }
}

///|
/// One chunk object, wrapped in the envelope every chat-completions stream uses.
fn chunk_json(delta : Json, finish : Json, usage? : Json) -> String {
  let fields = [
    ("id", Json::string("chatcmpl-stream")),
    ("object", Json::string("chat.completion.chunk")),
    (
      "choices",
      Json::array([
        @moonmuse.object_json([
          ("index", Json::number(0.0)),
          ("delta", delta),
          ("finish_reason", finish),
        ]),
      ]),
    ),
  ]
  match usage {
    Some(value) => fields.push(("usage", value))
    None => ()
  }
  @moonmuse.object_json(fields).stringify()
}
