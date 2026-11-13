///|
/// Ollama's native wire format. A local server has no credential, a tool call has no id,
/// and generation options live in one nested object — the dialect keeps those three facts
/// out of every caller.

///|
/// The Ollama wire format.
pub struct Wire {}

///|
/// The one instance; it carries no state.
pub let dialect : Wire = Wire::{ }

///|
/// The chat call for `request`.
pub fn chat_call(request : @moonmuse.Request) -> @moonmuse.Call {
  let messages = []
  for message in request.messages {
    messages.push(message_json(message))
  }
  let fields : Array[(String, Json)] = [
    ("model", Json::string(request.model)),
    ("messages", Json::array(messages)),
    ("stream", Json::boolean(false)),
  ]
  if !request.tools.is_empty() {
    fields.push(("tools", Json::array(request.tools.map(tool_json))))
  }
  let options = options_json(request)
  if !options.is_empty() {
    fields.push(("options", Json::object(options)))
  }
  let body = Json::object(@moonmuse.merge_json(of_pairs(fields), request.extra))
  @moonmuse.Call::new("POST", "/api/chat", body)
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
/// The generation options Ollama accepts, from what the request set.
fn options_json(request : @moonmuse.Request) -> Map[String, Json] {
  let options = Map([])
  match request.temperature {
    Some(value) => options["temperature"] = Json::number(value)
    None => ()
  }
  match request.max_tokens {
    Some(value) => options["num_predict"] = Json::number(value.to_double())
    None => ()
  }
  if !request.stop.is_empty() {
    options["stop"] = @moonmuse.strings_json(request.stop)
  }
  match request.choice {
    @moonmuse.NoTools => ()
    _ => ()
  }
  options
}

///|
/// One message as Ollama writes it. Images ride beside the content as bare base64.
fn message_json(message : @moonmuse.Message) -> Json {
  let images = []
  for part in message.parts {
    match part {
      @moonmuse.Part::Image(url~, ..) => images.push(Json::string(url))
      _ => ()
    }
  }
  match message.role {
    @moonmuse.Tool => {
      let content = message.text_content(separator="")
      @moonmuse.object_json([
        ("role", Json::string("tool")),
        ("content", Json::string(content)),
      ])
    }
    role => {
      let fields = [
        ("role", Json::string(role.code())),
        ("content", Json::string(message.text_content(separator=""))),
      ]
      if !images.is_empty() {
        fields.push(("images", Json::array(images)))
      }
      let calls = message.calls()
      if !calls.is_empty() {
        let encoded = []
        for part in calls {
          match part {
            @moonmuse.Part::Call(name~, args~, ..) =>
              encoded.push(
                @moonmuse.object_json([
                  (
                    "function",
                    @moonmuse.object_json([
                      ("name", Json::string(name)),
                      ("arguments", args),
                    ]),
                  ),
                ]),
              )
            _ => ()
          }
        }
        fields.push(("tool_calls", Json::array(encoded)))
      }
      @moonmuse.object_json(fields)
    }
  }
}

///|
/// A tool as Ollama writes it — the same function shape OpenAI uses.
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
/// The reply a chat body describes.
pub fn chat_reply(
  status : Int32,
  body : Json,
) -> @moonmuse.Reply raise @moonmuse.LlmError {
  if status >= 400 {
    raise @moonmuse.Status(
      code=status,
      body=@json.dumps(body),
      retry_after=None,
    )
  }
  let parts = []
  let mut call_index = 0
  match @moonmuse.json_object(body, "message") {
    Some(fields) => {
      let message = Json::object(fields)
      let text = @moonmuse.json_string_or(message, "content", "")
      if text != "" {
        parts.push(@moonmuse.Part::text(text))
      }
      for item in @moonmuse.json_array(message, "tool_calls") {
        let function = @moonmuse.json_field(item, "function").unwrap_or(
          Json::null(),
        )
        parts.push(
          @moonmuse.Part::call(
            "call_" + call_index.to_string(),
            @moonmuse.json_string_or(function, "name", ""),
            @moonmuse.json_field(function, "arguments").unwrap_or(
              Json::object(Map([])),
            ),
          ),
        )
        call_index = call_index + 1
      }
    }
    None => ()
  }
  let usage : @moonmuse.Usage = {
    input: @moonmuse.json_int(body, "prompt_eval_count"),
    output: @moonmuse.json_int(body, "eval_count"),
    cached: None,
  }
  @moonmuse.Reply::new(
    @moonmuse.Message::new(@moonmuse.Assistant, parts),
    finish=@moonmuse.Finish::of(
      @moonmuse.json_string_or(body, "done_reason", "stop"),
    ),
    usage~,
    raw=body,
  )
}

///|
/// The body that answers `reply`.
pub fn chat_answer(reply : @moonmuse.Reply) -> Json {
  let fields = [
    (
      "model",
      Json::string(@moonmuse.json_string_or(reply.raw, "model", "moonmuse")),
    ),
    ("created_at", Json::string("2026-01-01T00:00:00Z")),
  ]
  let message = [
    ("role", Json::string("assistant")),
    ("content", Json::string(reply.message.text_content(separator=""))),
  ]
  let calls = reply.message.calls()
  if !calls.is_empty() {
    let encoded = []
    for part in calls {
      match part {
        @moonmuse.Part::Call(name~, args~, ..) =>
          encoded.push(
            @moonmuse.object_json([
              (
                "function",
                @moonmuse.object_json([
                  ("name", Json::string(name)),
                  ("arguments", args),
                ]),
              ),
            ]),
          )
        _ => ()
      }
    }
    message.push(("tool_calls", Json::array(encoded)))
  }
  fields.push(("message", @moonmuse.object_json(message)))
  fields.push(("done", Json::boolean(true)))
  fields.push(("done_reason", Json::string(finish_code(reply.finish))))
  match reply.usage.input {
    Some(value) =>
      fields.push(("prompt_eval_count", Json::number(value.to_double())))
    None => ()
  }
  match reply.usage.output {
    Some(value) => fields.push(("eval_count", Json::number(value.to_double())))
    None => ()
  }
  @moonmuse.object_json(fields)
}

///|
/// The finish reason as Ollama spells it.
pub fn finish_code(finish : @moonmuse.Finish) -> String {
  match finish {
    @moonmuse.Stop => "stop"
    @moonmuse.Length => "length"
    @moonmuse.Calls => "tool_calls"
    @moonmuse.Filtered => "content_filter"
    @moonmuse.Other(reason) => reason
  }
}

///|
/// The request a chat body asks for.
pub fn chat_parse(body : Json) -> @moonmuse.Request raise @moonmuse.LlmError {
  let model = @moonmuse.json_string_or(body, "model", "")
  if model == "" {
    raise @moonmuse.Decode("chat request has no model")
  }
  let messages = []
  for item in @moonmuse.json_array(body, "messages") {
    messages.push(message_of(item))
  }
  let tools = []
  for item in @moonmuse.json_array(body, "tools") {
    let function = @moonmuse.json_field(item, "function").unwrap_or(item)
    tools.push(
      @moonmuse.Tool::new(
        @moonmuse.json_string_or(function, "name", ""),
        @moonmuse.json_string_or(function, "description", ""),
        schema=@moonmuse.json_field(function, "parameters").unwrap_or(
          Json::object(Map([])),
        ),
      ),
    )
  }
  let options = @moonmuse.json_field(body, "options").unwrap_or(Json::null())
  @moonmuse.Request::new(
    model,
    messages,
    tools~,
    temperature?=@moonmuse.json_number(options, "temperature"),
    max_tokens?=@moonmuse.json_int(options, "num_predict"),
    stop=@moonmuse.json_strings(
      @moonmuse.json_field(options, "stop").unwrap_or(Json::null()),
    ),
  )
}

///|
/// One wire message as a message.
fn message_of(item : Json) -> @moonmuse.Message {
  let role = match @moonmuse.json_string(item, "role").unwrap_or("user") {
    "assistant" => @moonmuse.Assistant
    "system" => @moonmuse.System
    "tool" => @moonmuse.Tool
    _ => @moonmuse.User
  }
  let parts = []
  let text = @moonmuse.json_string_or(item, "content", "")
  if text != "" {
    parts.push(@moonmuse.Part::text(text))
  }
  for image in @moonmuse.json_array(item, "images") {
    match @moonmuse.json_as_string(image) {
      Some(data) => parts.push(@moonmuse.Image(url=data, media=None))
      None => ()
    }
  }
  let mut index = 0
  for call in @moonmuse.json_array(item, "tool_calls") {
    let function = @moonmuse.json_field(call, "function").unwrap_or(
      Json::null(),
    )
    parts.push(
      @moonmuse.Part::call(
        "call_" + index.to_string(),
        @moonmuse.json_string_or(function, "name", ""),
        @moonmuse.json_field(function, "arguments").unwrap_or(
          Json::object(Map([])),
        ),
      ),
    )
    index = index + 1
  }
  @moonmuse.Message::new(role, parts)
}

///|
/// The error body Ollama sends.
pub fn error_json(error : @moonmuse.LlmError) -> (Int32, Json) {
  let (status, message) = match error {
    @moonmuse.Status(code~, body~, ..) => (code, body)
    @moonmuse.Stream(message) => (500, message)
    @moonmuse.Decode(message) => (400, message)
    @moonmuse.Unsupported(what) => (404, what)
  }
  (status, @moonmuse.object_json([("error", Json::string(message))]))
}
