///|
/// The wire shapes this dialect shares between the client and the server halves: a
/// message as OpenAI writes it, a usage object as it reports it, and the field names
/// that mark a body as one of the five endpoints.

///|
/// The keys `request` writes. `parse` treats every other key as a caller's own and keeps
/// it in `extra`, so a request that arrives at a gateway leaves with the same fields it
/// came with.
pub let request_keys : Array[String] = [
  "model", "messages", "tools", "tool_choice", "temperature", "max_tokens", "stop",
  "stream", "n",
]

///|
/// The content of a message as OpenAI writes it: a plain string when it is all text, an
/// array of typed parts when it carries images.
pub fn content_json(message : @moonmuse.Message) -> Json {
  let images = message.parts.filter(part => part is Image(..))
  if images.is_empty() {
    return Json::string(message.text_content(separator=""))
  }
  let parts = []
  let text = message.text_content(separator="")
  if text != "" {
    parts.push(
      @moonmuse.object_json([
        ("type", Json::string("text")),
        ("text", Json::string(text)),
      ]),
    )
  }
  for part in images {
    match part {
      Image(url~, media~) => {
        let url = match media {
          Some(kind) =>
            if url.has_prefix("data:") || url.contains("://") {
              url
            } else {
              "data:" + kind + ";base64," + url
            }
          None => url
        }
        parts.push(
          @moonmuse.object_json([
            ("type", Json::string("image_url")),
            ("image_url", @moonmuse.object_json([("url", Json::string(url))])),
          ]),
        )
      }
      _ => ()
    }
  }
  Json::array(parts)
}

///|
/// One message's wire form. A tool message expands to one message per result, because
/// OpenAI pairs each result with exactly one call.
pub fn messages_json(message : @moonmuse.Message) -> Array[Json] {
  let out = []
  match message.role {
    @moonmuse.Tool =>
      for part in message.parts {
        match part {
          Result(id~, content~, ..) =>
            out.push(
              @moonmuse.object_json([
                ("role", Json::string("tool")),
                ("tool_call_id", Json::string(id)),
                ("content", Json::string(content)),
              ]),
            )
          _ => ()
        }
      }
    role => {
      let calls = message.calls()
      let fields = [("role", Json::string(role.code()))]
      if calls.is_empty() {
        fields.push(("content", content_json(message)))
      } else {
        let text = message.text_content(separator="")
        fields.push(
          (
            "content",
            if text == "" {
              Json::null()
            } else {
              Json::string(text)
            },
          ),
        )
        let encoded = []
        for part in calls {
          match part {
            Call(id~, name~, args~) =>
              encoded.push(
                @moonmuse.object_json([
                  ("id", Json::string(id)),
                  ("type", Json::string("function")),
                  (
                    "function",
                    @moonmuse.object_json([
                      ("name", Json::string(name)),
                      ("arguments", Json::string(args.stringify())),
                    ]),
                  ),
                ]),
              )
            _ => ()
          }
        }
        fields.push(("tool_calls", Json::array(encoded)))
      }
      out.push(@moonmuse.object_json(fields))
    }
  }
  out
}

///|
/// A tool as OpenAI writes it.
pub fn tool_json(tool : @moonmuse.Tool) -> Json {
  @moonmuse.object_json([
    ("type", Json::string("function")),
    (
      "function",
      @moonmuse.object_json([
        ("name", Json::string(tool.name)),
        ("description", Json::string(tool.description)),
        ("parameters", tool.schema),
      ]),
    ),
  ])
}

///|
/// How the request allows tools.
pub fn tool_choice_json(choice : @moonmuse.ToolChoice) -> Json {
  match choice {
    Auto => Json::string("auto")
    NoTools => Json::string("none")
    Required => Json::string("required")
    Named(name) =>
      @moonmuse.object_json([
        ("type", Json::string("function")),
        ("function", @moonmuse.object_json([("name", Json::string(name))])),
      ])
  }
}

///|
/// The usage object, from what the endpoint reported. A field it did not report stays
/// absent rather than becoming a zero.
pub fn usage_json(usage : @moonmuse.Usage) -> Json {
  let fields = []
  match usage.input {
    Some(input) =>
      fields.push(("prompt_tokens", Json::number(input.to_double())))
    None => ()
  }
  match usage.output {
    Some(output) =>
      fields.push(("completion_tokens", Json::number(output.to_double())))
    None => ()
  }
  match usage.total() {
    Some(total) =>
      fields.push(("total_tokens", Json::number(total.to_double())))
    None => ()
  }
  match usage.cached {
    Some(cached) =>
      fields.push(
        (
          "prompt_tokens_details",
          @moonmuse.object_json([
            ("cached_tokens", Json::number(cached.to_double())),
          ]),
        ),
      )
    None => ()
  }
  Json::object(of_fields(fields))
}

///|
/// The usage an OpenAI body reports.
pub fn usage_of(body : Json) -> @moonmuse.Usage {
  let usage = @moonmuse.json_object(body, "usage")
  let cached = @moonmuse.json_object(body, "usage").bind(map => {
    match map.get("prompt_tokens_details") {
      Some(details) => @moonmuse.json_int(details, "cached_tokens")
      None => None
    }
  })
  match usage {
    Some(fields) =>
      {
        input: @moonmuse.json_field(Json::object(fields), "prompt_tokens").bind(value => {
            @moonmuse.json_as_number(value).map(number => number.to_int())
          },
        ),
        output: @moonmuse.json_field(Json::object(fields), "completion_tokens").bind(value => {
            @moonmuse.json_as_number(value).map(number => number.to_int())
          },
        ),
        cached,
      }
    None => @moonmuse.Usage::zero()
  }
}

///|
/// A map from a list of pairs, keeping the last value for a repeated key.
fn of_fields(fields : Array[(String, Json)]) -> Map[String, Json] {
  let map = Map([])
  for pair in fields {
    map[pair.0] = pair.1
  }
  map
}

///|
/// The error body OpenAI sends, for a status the client turned into an `LlmError`.
pub fn error_json(error : @moonmuse.LlmError) -> (Int32, Json) {
  match error {
    @moonmuse.Status(code~, body~, ..) => {
      let parsed = @json.parse(body) catch { _ => Json::string(body) }
      let message = match parsed {
        Object(map) =>
          match map.get("error") {
            Some(inner) => @moonmuse.json_string_or(inner, "message", body)
            None => body
          }
        _ => body
      }
      (
        code,
        @moonmuse.object_json([
          (
            "error",
            @moonmuse.object_json([
              ("message", Json::string(message)),
              ("type", Json::string("invalid_request_error")),
            ]),
          ),
        ]),
      )
    }
    @moonmuse.Stream(message) =>
      (
        400,
        @moonmuse.object_json([
          (
            "error",
            @moonmuse.object_json([
              ("message", Json::string(message)),
              ("type", Json::string("stream_error")),
            ]),
          ),
        ]),
      )
    @moonmuse.Decode(message) =>
      (
        400,
        @moonmuse.object_json([
          (
            "error",
            @moonmuse.object_json([
              ("message", Json::string(message)),
              ("type", Json::string("invalid_request_error")),
            ]),
          ),
        ]),
      )
    @moonmuse.Unsupported(what) =>
      (
        404,
        @moonmuse.object_json([
          (
            "error",
            @moonmuse.object_json([
              ("message", Json::string(what)),
              ("type", Json::string("not_found_error")),
            ]),
          ),
        ]),
      )
  }
}
