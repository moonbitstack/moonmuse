///|
/// Gemini's streamed answer: server-sent events, each carrying a whole part rather than a
/// slice of one. Text arrives in pieces, a function call arrives complete, and the finish
/// reason closes the stream — so the reader's job is mostly to accumulate.

///|
/// The deltas one chunk carries.
pub fn stream_delta(
  frame : @moonmuse.Frame,
  turn : @moonmuse.Turn,
) -> Array[@moonmuse.Delta] raise @moonmuse.LlmError {
  if turn.has_slot("done") {
    return []
  }
  if frame.data.trim() == "[DONE]" {
    turn.set_slot("done", "1")
    return [@moonmuse.Delta::Done(reply_of(turn, @moonmuse.Stop))]
  }
  let body = frame.json()
  match @moonmuse.json_object(body, "usageMetadata") {
    Some(fields) => {
      let usage = Json::object(fields)
      match @moonmuse.json_int(usage, "promptTokenCount") {
        Some(value) => turn.set_num("usage:input", value)
        None => ()
      }
      match @moonmuse.json_int(usage, "candidatesTokenCount") {
        Some(value) => turn.set_num("usage:output", value)
        None => ()
      }
      match @moonmuse.json_int(usage, "cachedContentTokenCount") {
        Some(value) => turn.set_num("usage:cached", value)
        None => ()
      }
    }
    None => ()
  }
  let candidates = @moonmuse.json_array(body, "candidates")
  if candidates.is_empty() {
    return []
  }
  let candidate = candidates[0]
  let deltas = []
  match @moonmuse.json_object(candidate, "content") {
    Some(fields) =>
      for part in @moonmuse.json_array(Json::object(fields), "parts") {
        match @moonmuse.json_string(part, "text") {
          Some(text) =>
            if text != "" {
              turn.add_slot("text", text)
              deltas.push(@moonmuse.Delta::Text(text))
            }
          None => ()
        }
        match @moonmuse.json_field(part, "functionCall") {
          Some(call) => {
            let index = turn.add_num("calls", 1) - 1
            let id = "call_" + index.to_string()
            let args = @moonmuse.json_field(call, "args").unwrap_or(
              Json::object(Map([])),
            )
            let key = "call:" + index.to_string()
            turn.set_slot(key + ":id", id)
            turn.set_slot(
              key + ":name",
              @moonmuse.json_string_or(call, "name", ""),
            )
            turn.set_slot(key + ":args", args.stringify())
            deltas.push(
              @moonmuse.Delta::CallStart(
                id~,
                name=@moonmuse.json_string_or(call, "name", ""),
              ),
            )
            deltas.push(@moonmuse.Delta::CallArgs(id~, chunk=args.stringify()))
          }
          None => ()
        }
      }
    None => ()
  }
  match @moonmuse.json_string(candidate, "finishReason") {
    Some(reason) if reason != "" => {
      turn.set_slot("done", "1")
      deltas.push(
        @moonmuse.Delta::Done(reply_of(turn, @moonmuse.Finish::of(reason))),
      )
    }
    _ => ()
  }
  deltas
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
/// The frames that carry one delta out, one chunk per event.
pub fn stream_frame(
  delta : @moonmuse.Delta,
  turn : @moonmuse.Turn,
) -> Array[@moonmuse.Frame] {
  match delta {
    @moonmuse.Delta::Text(text) =>
      [chunk_frame([text_part(text)].map(part => part), Json::null())]
    @moonmuse.Delta::CallStart(name~, ..) => {
      let index = turn.add_num("calls", 1) - 1
      turn.set_slot("call:" + index.to_string() + ":name", name)
      []
    }
    @moonmuse.Delta::CallArgs(chunk~, ..) =>
      [
        chunk_frame(
          [
            @moonmuse.object_json([
              (
                "functionCall",
                @moonmuse.object_json([
                  (
                    "name",
                    Json::string(
                      turn.slot(
                        "call:" + (turn.num("calls") - 1).to_string() + ":name",
                      ),
                    ),
                  ),
                  ("args", @moonmuse.parse_json_lossy(chunk)),
                ]),
              ),
            ]),
          ],
          Json::null(),
        ),
      ]
    @moonmuse.Delta::Done(reply) =>
      [chunk_frame([], Json::string(finish_code(reply.finish)))]
  }
}

///|
/// One streamed chunk.
fn chunk_frame(parts : Array[Json], finish : Json) -> @moonmuse.Frame {
  @moonmuse.Frame::new(
    @moonmuse.object_json([
      (
        "candidates",
        Json::array([
          @moonmuse.object_json([
            (
              "content",
              @moonmuse.object_json([
                ("role", Json::string("model")),
                ("parts", Json::array(parts)),
              ]),
            ),
            ("finishReason", finish),
            ("index", Json::number(0.0)),
          ]),
        ]),
      ),
    ]).stringify(),
  )
}
