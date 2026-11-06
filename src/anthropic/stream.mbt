///|
/// Anthropic streams seven event kinds, one per change of state. Text and tool arguments
/// arrive on the same `content_block_delta` event, told apart by the delta's own type,
/// and the stop reason arrives on `message_delta` after the last block. The reader folds
/// all of that into the shared deltas; the writer produces the same seven events back.

///|
/// The deltas one event carries.
pub fn stream_delta(
  frame : @moonmuse.Frame,
  turn : @moonmuse.Turn,
) -> Array[@moonmuse.Delta] raise @moonmuse.LlmError {
  if turn.has_slot("done") {
    return []
  }
  let body = frame.json()
  let kind = match frame.event {
    Some(name) => name
    None => @moonmuse.json_string_or(body, "type", "")
  }
  match kind {
    "message_start" => {
      match @moonmuse.json_object(body, "message") {
        Some(fields) => {
          let message = Json::object(fields)
          match @moonmuse.json_object(message, "usage") {
            Some(usage) =>
              match @moonmuse.json_int(Json::object(usage), "input_tokens") {
                Some(value) => turn.set_num("usage:input", value)
                None => ()
              }
            None => ()
          }
        }
        None => ()
      }
      []
    }
    "content_block_start" => {
      let index = @moonmuse.json_int(body, "index").unwrap_or(0)
      let block = @moonmuse.json_field(body, "content_block").unwrap_or(
        Json::null(),
      )
      let block_type = @moonmuse.json_string_or(block, "type", "text")
      turn.set_slot("block:" + index.to_string(), block_type)
      if block_type == "tool_use" {
        let id = @moonmuse.json_string_or(block, "id", "")
        let slot = turn.add_num("calls", 1) - 1
        turn.set_slot("call:" + slot.to_string() + ":id", id)
        turn.set_slot(
          "call:" + slot.to_string() + ":name",
          @moonmuse.json_string_or(block, "name", ""),
        )
        turn.set_slot("index:" + index.to_string(), slot.to_string())
        [
          @moonmuse.Delta::CallStart(
            id~,
            name=@moonmuse.json_string_or(block, "name", ""),
          ),
        ]
      } else {
        []
      }
    }
    "content_block_delta" => {
      let index = @moonmuse.json_int(body, "index").unwrap_or(0)
      let delta = @moonmuse.json_field(body, "delta").unwrap_or(Json::null())
      match @moonmuse.json_string(delta, "type") {
        Some("text_delta") => {
          let text = @moonmuse.json_string_or(delta, "text", "")
          if text == "" {
            []
          } else {
            turn.add_slot("text", text)
            [@moonmuse.Delta::Text(text)]
          }
        }
        Some("input_json_delta") => {
          let chunk = @moonmuse.json_string_or(delta, "partial_json", "")
          let slot = @moonmuse.parse_int_lossy(
            turn.slot("index:" + index.to_string()),
          )
          let key = "call:" + slot.to_string()
          if chunk != "" {
            turn.add_slot(key + ":args", chunk)
            [@moonmuse.Delta::CallArgs(id=turn.slot(key + ":id"), chunk~)]
          } else {
            []
          }
        }
        Some("thinking_delta") =>
          // Extended thinking is a separate block kind; it is not part of the reply text.
          []
        _ => []
      }
    }
    "message_delta" => {
      let delta = @moonmuse.json_field(body, "delta").unwrap_or(Json::null())
      match @moonmuse.json_string(delta, "stop_reason") {
        Some(reason) => turn.set_slot("finish", reason)
        None => ()
      }
      match @moonmuse.json_object(body, "usage") {
        Some(fields) =>
          match @moonmuse.json_int(Json::object(fields), "output_tokens") {
            Some(value) => turn.set_num("usage:output", value)
            None => ()
          }
        None => ()
      }
      []
    }
    "message_stop" => {
      turn.set_slot("done", "1")
      let finish = match turn.slot("finish") {
        "" => @moonmuse.Stop
        reason => @moonmuse.Finish::of(reason)
      }
      [@moonmuse.Delta::Done(reply_of(turn, finish))]
    }
    "error" => raise @moonmuse.Stream(body.stringify())
    _ => []
  }
}

///|
/// The reply the folded events describe.
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
/// The events that carry one delta out.
pub fn stream_frame(
  delta : @moonmuse.Delta,
  turn : @moonmuse.Turn,
) -> Array[@moonmuse.Frame] {
  match delta {
    @moonmuse.Delta::Text(text) => {
      let index = start_block(turn, "text")
      [
        event(
          "content_block_delta",
          @moonmuse.object_json([
            ("type", Json::string("content_block_delta")),
            ("index", Json::number(index.to_double())),
            (
              "delta",
              @moonmuse.object_json([
                ("type", Json::string("text_delta")),
                ("text", Json::string(text)),
              ]),
            ),
          ]),
        ),
      ]
    }
    @moonmuse.Delta::CallStart(id~, name~) => {
      let index = start_block(turn, "tool_use")
      turn.set_slot("block:" + index.to_string() + ":id", id)
      turn.set_slot("id:" + id, index.to_string())
      [
        event(
          "content_block_start",
          @moonmuse.object_json([
            ("type", Json::string("content_block_start")),
            ("index", Json::number(index.to_double())),
            (
              "content_block",
              @moonmuse.object_json([
                ("type", Json::string("tool_use")),
                ("id", Json::string(id)),
                ("name", Json::string(name)),
                ("input", Json::object(Map([]))),
              ]),
            ),
          ]),
        ),
      ]
    }
    @moonmuse.Delta::CallArgs(id~, chunk~) => {
      let index = @moonmuse.parse_int_lossy(turn.slot("id:" + id))
      [
        event(
          "content_block_delta",
          @moonmuse.object_json([
            ("type", Json::string("content_block_delta")),
            ("index", Json::number(index.to_double())),
            (
              "delta",
              @moonmuse.object_json([
                ("type", Json::string("input_json_delta")),
                ("partial_json", Json::string(chunk)),
              ]),
            ),
          ]),
        ),
      ]
    }
    @moonmuse.Delta::Done(reply) => {
      let usage = []
      match reply.usage.output {
        Some(value) =>
          usage.push(("output_tokens", Json::number(value.to_double())))
        None => ()
      }
      [
        event(
          "message_delta",
          @moonmuse.object_json([
            ("type", Json::string("message_delta")),
            (
              "delta",
              @moonmuse.object_json([
                ("stop_reason", Json::string(stop_code(reply.finish))),
              ]),
            ),
            ("usage", @moonmuse.object_json(usage)),
          ]),
        ),
        event(
          "message_stop",
          @moonmuse.object_json([("type", Json::string("message_stop"))]),
        ),
      ]
    }
  }
}

///|
/// Start a block of `kind` unless one is already open, and return its ordinal.
fn start_block(turn : @moonmuse.Turn, kind : String) -> Int32 {
  let open = turn.slot("open")
  if open == kind {
    return @moonmuse.parse_int_lossy(turn.slot("open:index"))
  }
  let index = turn.num("blocks")
  turn.set_num("blocks", index + 1)
  turn.set_slot("open", kind)
  turn.set_slot("open:index", index.to_string())
  index
}

///|
/// A named event frame.
fn event(name : String, body : Json) -> @moonmuse.Frame {
  @moonmuse.Frame::named(name, body.stringify())
}
