///|
/// The Converse API: one JSON body for every model Bedrock serves, so this package does not
/// need a dialect per vendor. The vocabulary is AWS's — `messages` with `content` blocks,
/// `inferenceConfig`, `toolConfig` — and it maps onto the shared one closely enough that the
/// translation is a table rather than a decision.

///|
/// The body that asks for an answer.
pub fn converse_body(request : @moonmuse.Request) -> Json {
  let messages = []
  let system = []
  for message in request.messages {
    match message.role {
      @moonmuse.System => {
        let text = message.text_content(separator="\n")
        if text != "" {
          system.push(@moonmuse.object_json([("text", Json::string(text))]))
        }
      }
      _ => messages.push(message_json(message))
    }
  }
  let fields : Array[(String, Json)] = [("messages", Json::array(messages))]
  if !system.is_empty() {
    fields.push(("system", Json::array(system)))
  }
  let config = []
  match request.max_tokens {
    Some(value) => config.push(("maxTokens", Json::number(value.to_double())))
    None => ()
  }
  match request.temperature {
    Some(value) => config.push(("temperature", Json::number(value)))
    None => ()
  }
  if !request.stop.is_empty() {
    config.push(("stopSequences", @moonmuse.strings_json(request.stop)))
  }
  if !config.is_empty() {
    fields.push(("inferenceConfig", @moonmuse.object_json(config)))
  }
  if !request.tools.is_empty() {
    let tools = []
    for tool in request.tools {
      tools.push(
        @moonmuse.object_json([
          (
            "toolSpec",
            @moonmuse.object_json([
              ("name", Json::string(tool.name)),
              ("description", Json::string(tool.description)),
              ("inputSchema", @moonmuse.object_json([("json", tool.schema)])),
            ]),
          ),
        ]),
      )
    }
    fields.push(
      ("toolConfig", @moonmuse.object_json([("tools", Json::array(tools))])),
    )
  }
  Json::object(@moonmuse.merge_json(of_pairs(fields), request.extra))
}

///|
/// One message in Converse's shape. A tool result answers a tool use, so it goes back as a
/// user message whose block names the call it answers.
fn message_json(message : @moonmuse.Message) -> Json {
  let role = if message.role == @moonmuse.Assistant {
    "assistant"
  } else {
    "user"
  }
  let blocks = []
  for part in message.parts {
    match part {
      @moonmuse.Part::Text(text) =>
        blocks.push(@moonmuse.object_json([("text", Json::string(text))]))
      @moonmuse.Part::Image(url~, ..) =>
        blocks.push(
          @moonmuse.object_json([
            (
              "image",
              @moonmuse.object_json([
                ("format", Json::string(media_of(url))),
                (
                  "source",
                  @moonmuse.object_json([("bytes", Json::string(url))]),
                ),
              ]),
            ),
          ]),
        )
      @moonmuse.Part::Call(id~, name~, args~) =>
        blocks.push(
          @moonmuse.object_json([
            (
              "toolUse",
              @moonmuse.object_json([
                ("toolUseId", Json::string(id)),
                ("name", Json::string(name)),
                ("input", args),
              ]),
            ),
          ]),
        )
      @moonmuse.Part::Result(id~, content~, error~) =>
        blocks.push(
          @moonmuse.object_json([
            (
              "toolResult",
              @moonmuse.object_json([
                ("toolUseId", Json::string(id)),
                (
                  "content",
                  Json::array([
                    @moonmuse.object_json([("text", Json::string(content))]),
                  ]),
                ),
                (
                  "status",
                  Json::string(if error { "error" } else { "success" }),
                ),
              ]),
            ),
          ]),
        )
    }
  }
  @moonmuse.object_json([
    ("role", Json::string(role)),
    ("content", Json::array(blocks)),
  ])
}

///|
/// A media type from a URL's extension. Converse names the format rather than carrying the
/// type, so this is the one place the two conventions meet.
fn media_of(url : String) -> String {
  let lowered = url.to_lower()
  if lowered.has_suffix(".png") {
    "png"
  } else if lowered.has_suffix(".gif") {
    "gif"
  } else if lowered.has_suffix(".webp") {
    "webp"
  } else {
    "jpeg"
  }
}

///|
/// The reply a Converse body describes.
pub fn converse_reply(body : Json) -> @moonmuse.Reply raise @moonmuse.LlmError {
  let message = match @moonmuse.json_object(body, "output") {
    Some(fields) => Json::object(fields)
    None => raise @moonmuse.Decode("a Converse answer has no output")
  }
  let message = match @moonmuse.json_object(message, "message") {
    Some(fields) => Json::object(fields)
    None => raise @moonmuse.Decode("a Converse answer has no message")
  }
  let parts = []
  for block in @moonmuse.json_array(message, "content") {
    match @moonmuse.json_string(block, "text") {
      Some(text) => if text != "" { parts.push(@moonmuse.Part::text(text)) }
      None => ()
    }
    match @moonmuse.json_object(block, "toolUse") {
      Some(fields) => {
        let spec = Json::object(fields)
        parts.push(
          @moonmuse.Part::call(
            @moonmuse.json_string_or(spec, "toolUseId", ""),
            @moonmuse.json_string_or(spec, "name", ""),
            @moonmuse.json_field(spec, "input").unwrap_or(Json::object(Map([]))),
          ),
        )
      }
      None => ()
    }
  }
  let finish = @moonmuse.Finish::of(
    @moonmuse.json_string_or(body, "stopReason", ""),
  )
  let usage = usage_of(
    @moonmuse.json_field(body, "usage").unwrap_or(Json::null()),
  )
  @moonmuse.Reply::new(
    @moonmuse.Message::new(@moonmuse.Assistant, parts),
    finish~,
    usage~,
    raw=body,
  )
}

///|
/// The counts a Converse body reports. Cached input tokens are reported separately, which is
/// the number the shared vocabulary keeps in `cached`.
fn usage_of(usage : Json) -> @moonmuse.Usage {
  @moonmuse.Usage::{
    input: @moonmuse.json_int(usage, "inputTokens"),
    output: @moonmuse.json_int(usage, "outputTokens"),
    cached: @moonmuse.json_int(usage, "cacheReadInputTokens"),
  }
}

///|
/// A map from pairs.
fn of_pairs(fields : Array[(String, Json)]) -> Map[String, Json] {
  let map = Map([])
  for pair in fields {
    map[pair.0] = pair.1
  }
  map
}
