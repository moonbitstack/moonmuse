///|
/// Anthropic's wire format. One value serves the client and the server, so a gateway that
/// offers this format cannot drift from the client that speaks it.

///|
/// The Anthropic wire format.
pub struct Wire {}

///|
/// The one instance; it carries no state.
pub let dialect : Wire = Wire::{ }

///|
/// The version header Anthropic requires. A gateway serving this format sends it too.
pub let version : String = "2023-06-01"

///|
/// The keys `request` writes; anything else in a served body is kept as `extra`.
pub let request_keys : Array[String] = [
  "model", "messages", "system", "max_tokens", "temperature", "tools", "tool_choice",
  "stop_sequences", "stream",
]

///|
/// The Messages API call for `request`.
pub fn message_call(request : @moonmuse.Request) -> @moonmuse.Call {
  let messages = []
  let mut system = ""
  for message in request.messages {
    match message.role {
      @moonmuse.System => {
        let text = message.text_content(separator="\n")
        if text != "" {
          if system != "" {
            system = system + "\n"
          }
          system = system + text
        }
      }
      _ => messages.push(message_json(message))
    }
  }
  let fields : Array[(String, Json)] = [
    ("model", Json::string(request.model)),
    ("max_tokens", Json::number(request.max_tokens.unwrap_or(4096).to_double())),
    ("messages", Json::array(messages)),
  ]
  if system != "" {
    fields.push(("system", Json::string(system)))
  }
  match request.temperature {
    Some(value) => fields.push(("temperature", Json::number(value)))
    None => ()
  }
  if !request.stop.is_empty() {
    fields.push(("stop_sequences", @moonmuse.strings_json(request.stop)))
  }
  if !request.tools.is_empty() && request.choice != @moonmuse.NoTools {
    fields.push(("tools", Json::array(request.tools.map(tool_json))))
  }
  match request.choice {
    @moonmuse.Auto => ()
    @moonmuse.NoTools => ()
    @moonmuse.Required =>
      fields.push(
        ("tool_choice", @moonmuse.object_json([("type", Json::string("any"))])),
      )
    @moonmuse.Named(name) =>
      fields.push(
        (
          "tool_choice",
          @moonmuse.object_json([
            ("type", Json::string("tool")),
            ("name", Json::string(name)),
          ]),
        ),
      )
  }
  @moonmuse.Call::new(
    "POST",
    "/messages",
    Json::object(@moonmuse.merge_json(of_pairs(fields), request.extra)),
  )
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

///|
/// One message as Anthropic writes it. A tool message becomes a user message carrying
/// `tool_result` blocks, which is where Anthropic expects them.
fn message_json(message : @moonmuse.Message) -> Json {
  match message.role {
    @moonmuse.Tool => {
      let blocks = []
      for part in message.parts {
        match part {
          @moonmuse.Part::Result(id~, content~, error~) =>
            blocks.push(
              @moonmuse.object_json([
                ("type", Json::string("tool_result")),
                ("tool_use_id", Json::string(id)),
                (
                  "content",
                  if error {
                    @moonmuse.object_json([
                      ("type", Json::string("text")),
                      ("text", Json::string(content)),
                    ])
                  } else {
                    Json::string(content)
                  },
                ),
                ("is_error", Json::boolean(error)),
              ]),
            )
          _ => ()
        }
      }
      @moonmuse.object_json([
        ("role", Json::string("user")),
        ("content", Json::array(blocks)),
      ])
    }
    role => {
      let blocks = []
      for part in message.parts {
        match part {
          @moonmuse.Part::Text(text) =>
            blocks.push(
              @moonmuse.object_json([
                ("type", Json::string("text")),
                ("text", Json::string(text)),
              ]),
            )
          @moonmuse.Part::Image(url~, media~) =>
            blocks.push(
              @moonmuse.object_json([
                ("type", Json::string("image")),
                (
                  "source",
                  @moonmuse.object_json([
                    ("type", Json::string("base64")),
                    ("media_type", Json::string(media.unwrap_or("image/png"))),
                    ("data", Json::string(url)),
                  ]),
                ),
              ]),
            )
          @moonmuse.Part::Call(id~, name~, args~) =>
            blocks.push(
              @moonmuse.object_json([
                ("type", Json::string("tool_use")),
                ("id", Json::string(id)),
                ("name", Json::string(name)),
                ("input", args),
              ]),
            )
          @moonmuse.Part::Result(id~, content~, error~) =>
            blocks.push(
              @moonmuse.object_json([
                ("type", Json::string("tool_result")),
                ("tool_use_id", Json::string(id)),
                ("content", Json::string(content)),
                ("is_error", Json::boolean(error)),
              ]),
            )
        }
      }
      @moonmuse.object_json([
        ("role", Json::string(role.code())),
        ("content", Json::array(blocks)),
      ])
    }
  }
}

///|
/// A tool as Anthropic writes it.
pub fn tool_json(tool : @moonmuse.Tool) -> Json {
  @moonmuse.object_json([
    ("name", Json::string(tool.name)),
    ("description", Json::string(tool.description)),
    ("input_schema", tool.schema),
  ])
}

///|
/// The usage an Anthropic body reports. Its two counts are named, and a cached read is
/// reported apart from the input count.
pub fn usage_of(body : Json) -> @moonmuse.Usage {
  match @moonmuse.json_object(body, "usage") {
    Some(fields) => {
      let usage = Json::object(fields)
      {
        input: @moonmuse.json_int(usage, "input_tokens"),
        output: @moonmuse.json_int(usage, "output_tokens"),
        cached: @moonmuse.json_int(usage, "cache_read_input_tokens"),
      }
    }
    None => @moonmuse.Usage::zero()
  }
}

///|
/// The reply a Messages body describes.
pub fn message_reply(
  status : Int32,
  body : Json,
) -> @moonmuse.Reply raise @moonmuse.LlmError {
  if status >= 400 {
    raise @moonmuse.Status(code=status, body=body.stringify(), retry_after=None)
  }
  let parts = []
  for block in @moonmuse.json_array(body, "content") {
    match @moonmuse.json_string(block, "type") {
      Some("text") =>
        parts.push(
          @moonmuse.Part::text(@moonmuse.json_string_or(block, "text", "")),
        )
      Some("tool_use") =>
        parts.push(
          @moonmuse.Part::call(
            @moonmuse.json_string_or(block, "id", ""),
            @moonmuse.json_string_or(block, "name", ""),
            @moonmuse.json_field(block, "input").unwrap_or(
              Json::object(Map([])),
            ),
          ),
        )
      _ => ()
    }
  }
  @moonmuse.Reply::new(
    @moonmuse.Message::new(@moonmuse.Assistant, parts),
    finish=@moonmuse.Finish::of(
      @moonmuse.json_string_or(body, "stop_reason", "end_turn"),
    ),
    usage=usage_of(body),
    raw=body,
  )
}

///|
/// The Messages body that answers `reply`.
pub fn message_answer(reply : @moonmuse.Reply) -> Json {
  let blocks = []
  for part in reply.message.parts {
    match part {
      @moonmuse.Part::Text(text) =>
        blocks.push(
          @moonmuse.object_json([
            ("type", Json::string("text")),
            ("text", Json::string(text)),
          ]),
        )
      @moonmuse.Part::Call(id~, name~, args~) =>
        blocks.push(
          @moonmuse.object_json([
            ("type", Json::string("tool_use")),
            ("id", Json::string(id)),
            ("name", Json::string(name)),
            ("input", args),
          ]),
        )
      _ => ()
    }
  }
  let usage = []
  match reply.usage.input {
    Some(value) => usage.push(("input_tokens", Json::number(value.to_double())))
    None => ()
  }
  match reply.usage.output {
    Some(value) =>
      usage.push(("output_tokens", Json::number(value.to_double())))
    None => ()
  }
  match reply.usage.cached {
    Some(value) =>
      usage.push(("cache_read_input_tokens", Json::number(value.to_double())))
    None => ()
  }
  @moonmuse.object_json([
    ("id", Json::string("msg_moonmuse")),
    ("type", Json::string("message")),
    ("role", Json::string("assistant")),
    ("model", Json::string(@moonmuse.json_string_or(reply.raw, "model", ""))),
    ("content", Json::array(blocks)),
    ("stop_reason", Json::string(stop_code(reply.finish))),
    (
      "stop_sequence",
      match reply.finish {
        @moonmuse.Other(reason) => Json::string(reason)
        _ => Json::null()
      },
    ),
    ("usage", @moonmuse.object_json(usage)),
  ])
}

///|
/// The stop reason as Anthropic spells it.
pub fn stop_code(finish : @moonmuse.Finish) -> String {
  match finish {
    @moonmuse.Stop => "end_turn"
    @moonmuse.Length => "max_tokens"
    @moonmuse.Calls => "tool_use"
    @moonmuse.Filtered => "refusal"
    @moonmuse.Other(reason) => reason
  }
}

///|
/// The request a Messages body asks for.
pub fn message_parse(body : Json) -> @moonmuse.Request raise @moonmuse.LlmError {
  let model = @moonmuse.json_string_or(body, "model", "")
  if model == "" {
    raise @moonmuse.Decode("messages request has no model")
  }
  let messages = []
  match @moonmuse.json_string(body, "system") {
    Some(text) => messages.push(@moonmuse.Message::system(text))
    None => ()
  }
  for item in @moonmuse.json_array(body, "messages") {
    for message in messages_of(item) {
      messages.push(message)
    }
  }
  let tools = []
  for item in @moonmuse.json_array(body, "tools") {
    tools.push(
      @moonmuse.Tool::new(
        @moonmuse.json_string_or(item, "name", ""),
        @moonmuse.json_string_or(item, "description", ""),
        schema=@moonmuse.json_field(item, "input_schema").unwrap_or(
          Json::object(Map([])),
        ),
      ),
    )
  }
  let choice = match @moonmuse.json_field(body, "tool_choice") {
    Some(String("any")) => @moonmuse.Required
    Some(String("none")) => @moonmuse.NoTools
    Some(Object(fields)) =>
      match fields.get("name") {
        Some(String(name)) => @moonmuse.Named(name)
        _ => @moonmuse.Auto
      }
    _ => @moonmuse.Auto
  }
  let extra = Map([])
  match body {
    Object(fields) =>
      for key, value in fields {
        let mut known = false
        for name in request_keys {
          if name == key {
            known = true
          }
        }
        if !known {
          extra[key] = value
        }
      }
    _ => ()
  }
  @moonmuse.Request::new(
    model,
    messages,
    tools~,
    choice~,
    temperature?=@moonmuse.json_number(body, "temperature"),
    max_tokens?=@moonmuse.json_int(body, "max_tokens"),
    stop=@moonmuse.json_strings(
      @moonmuse.json_field(body, "stop_sequences").unwrap_or(Json::null()),
    ),
    extra~,
  )
}

///|
/// The messages a body message describes. A user message of `tool_result` blocks becomes
/// tool messages; anything else keeps its role and blocks.
pub fn messages_of(item : Json) -> Array[@moonmuse.Message] {
  let role = match @moonmuse.json_string(item, "role").unwrap_or("user") {
    "assistant" => @moonmuse.Assistant
    "system" => @moonmuse.System
    _ => @moonmuse.User
  }
  let results = []
  let parts = []
  match @moonmuse.json_field(item, "content") {
    Some(String(text)) => parts.push(@moonmuse.Part::text(text))
    Some(Array(blocks)) =>
      for block in blocks {
        match @moonmuse.json_string(block, "type") {
          Some("text") =>
            parts.push(
              @moonmuse.Part::text(@moonmuse.json_string_or(block, "text", "")),
            )
          Some("image") => {
            let data = match @moonmuse.json_object(block, "source") {
              Some(fields) => {
                let source = Json::object(fields)
                (
                  @moonmuse.json_string_or(source, "data", ""),
                  @moonmuse.json_string(source, "media_type"),
                )
              }
              None => ("", None)
            }
            parts.push(@moonmuse.Image(url=data.0, media=data.1))
          }
          Some("tool_use") =>
            parts.push(
              @moonmuse.Part::call(
                @moonmuse.json_string_or(block, "id", ""),
                @moonmuse.json_string_or(block, "name", ""),
                @moonmuse.json_field(block, "input").unwrap_or(
                  Json::object(Map([])),
                ),
              ),
            )
          Some("tool_result") => {
            let content = match @moonmuse.json_field(block, "content") {
              Some(String(text)) => text
              Some(Array(items)) =>
                items
                .filter_map(part => {
                  match @moonmuse.json_string(part, "type") {
                    Some("text") => @moonmuse.json_string(part, "text")
                    _ => None
                  }
                })
                .join("")
              _ => ""
            }
            results.push(
              @moonmuse.Message::tool(
                content,
                id=@moonmuse.json_string_or(block, "tool_use_id", ""),
                error=@moonmuse.json_bool(block, "is_error").unwrap_or(false),
              ),
            )
          }
          _ => ()
        }
      }
    _ => ()
  }
  if !results.is_empty() {
    return results
  }
  [@moonmuse.Message::new(role, parts)]
}

///|
/// The error body Anthropic sends.
pub fn error_json(error : @moonmuse.LlmError) -> (Int32, Json) {
  let (kind, message, status) = match error {
    @moonmuse.Status(code~, body~, ..) => ("api_error", body, code)
    @moonmuse.Stream(message) => ("api_error", message, 400)
    @moonmuse.Decode(message) => ("invalid_request_error", message, 400)
    @moonmuse.Unsupported(what) => ("not_found_error", what, 404)
  }
  (
    status,
    @moonmuse.object_json([
      ("type", Json::string("error")),
      (
        "error",
        @moonmuse.object_json([
          ("type", Json::string(kind)),
          ("message", Json::string(message)),
        ]),
      ),
    ]),
  )
}
