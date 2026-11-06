///|
/// Gemini's wire format. Two things make it unlike the other three: the model name is part
/// of the path rather than the body, and a function call carries no id, so one is
/// synthesized deterministically here and reused for the result that answers it.

///|
/// The Gemini wire format.
pub struct Wire {}

///|
/// The one instance; it carries no state.
pub let dialect : Wire = Wire::{ }

///|
/// The generateContent call for `request`.
pub fn generate_call(request : @moonmuse.Request) -> @moonmuse.Call {
  let names = Map([])
  for message in request.messages {
    for part in message.parts {
      match part {
        @moonmuse.Part::Call(id~, name~, ..) => names[id] = name
        _ => ()
      }
    }
  }
  let contents = []
  for message in request.messages {
    match message.role {
      @moonmuse.System => ()
      _ => contents.push(content_json(message, names))
    }
  }
  let fields : Array[(String, Json)] = [("contents", Json::array(contents))]
  let mut system = ""
  for message in request.messages {
    if message.role == @moonmuse.System {
      let text = message.text_content(separator="\n")
      if text != "" {
        if system != "" {
          system = system + "\n"
        }
        system = system + text
      }
    }
  }
  if system != "" {
    fields.push(
      (
        "systemInstruction",
        @moonmuse.object_json([("parts", Json::array([text_part(system)]))]),
      ),
    )
  }
  if !request.tools.is_empty() {
    let declarations = []
    for tool in request.tools {
      declarations.push(
        @moonmuse.object_json([
          ("name", Json::string(tool.name)),
          ("description", Json::string(tool.description)),
          ("parameters", tool.schema),
        ]),
      )
    }
    fields.push(
      (
        "tools",
        Json::array([
          @moonmuse.object_json([
            ("functionDeclarations", Json::array(declarations)),
          ]),
        ]),
      ),
    )
  }
  let generation = []
  match request.temperature {
    Some(value) => generation.push(("temperature", Json::number(value)))
    None => ()
  }
  match request.max_tokens {
    Some(value) =>
      generation.push(("maxOutputTokens", Json::number(value.to_double())))
    None => ()
  }
  if !request.stop.is_empty() {
    generation.push(("stopSequences", @moonmuse.strings_json(request.stop)))
  }
  if !generation.is_empty() {
    fields.push(("generationConfig", @moonmuse.object_json(generation)))
  }
  let mode = match request.choice {
    @moonmuse.Auto => "AUTO"
    @moonmuse.NoTools => "NONE"
    @moonmuse.Required => "ANY"
    @moonmuse.Named(_) => "ANY"
  }
  if !request.tools.is_empty() {
    fields.push(
      (
        "toolConfig",
        @moonmuse.object_json([
          (
            "functionCallingConfig",
            @moonmuse.object_json([("mode", Json::string(mode))]),
          ),
        ]),
      ),
    )
  }
  let path = "/models/" + request.model + ":generateContent"
  @moonmuse.Call::new(
    "POST",
    path,
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
/// A text part.
fn text_part(text : String) -> Json {
  @moonmuse.object_json([("text", Json::string(text))])
}

///|
/// One message as a `content` entry. Gemini's assistant role is called `model`, and a tool
/// result is a `functionResponse` part in a user turn.
fn content_json(
  message : @moonmuse.Message,
  names : Map[String, String],
) -> Json {
  let role = match message.role {
    @moonmuse.Assistant => "model"
    _ => "user"
  }
  let parts = []
  for part in message.parts {
    match part {
      @moonmuse.Part::Text(text) =>
        if text != "" {
          parts.push(text_part(text))
        }
      @moonmuse.Part::Image(url~, media~) =>
        parts.push(
          @moonmuse.object_json([
            (
              "inlineData",
              @moonmuse.object_json([
                ("mimeType", Json::string(media.unwrap_or("image/png"))),
                ("data", Json::string(url)),
              ]),
            ),
          ]),
        )
      @moonmuse.Part::Call(name~, args~, ..) =>
        parts.push(
          @moonmuse.object_json([
            (
              "functionCall",
              @moonmuse.object_json([
                ("name", Json::string(name)),
                ("args", args),
              ]),
            ),
          ]),
        )
      @moonmuse.Part::Result(id~, content~, error~) =>
        parts.push(
          @moonmuse.object_json([
            (
              "functionResponse",
              @moonmuse.object_json([
                ("name", Json::string(names.get(id).unwrap_or("tool"))),
                (
                  "response",
                  @moonmuse.object_json([
                    (
                      "content",
                      if error {
                        Json::string("error: " + content)
                      } else {
                        Json::string(content)
                      },
                    ),
                  ]),
                ),
              ]),
            ),
          ]),
        )
    }
  }
  @moonmuse.object_json([
    ("role", Json::string(role)),
    ("parts", Json::array(parts)),
  ])
}

///|
/// The usage a Gemini body reports.
pub fn usage_of(body : Json) -> @moonmuse.Usage {
  match @moonmuse.json_object(body, "usageMetadata") {
    Some(fields) => {
      let usage = Json::object(fields)
      {
        input: @moonmuse.json_int(usage, "promptTokenCount"),
        output: @moonmuse.json_int(usage, "candidatesTokenCount"),
        cached: @moonmuse.json_int(usage, "cachedContentTokenCount"),
      }
    }
    None => @moonmuse.Usage::zero()
  }
}

///|
/// The reply a generateContent body describes.
pub fn generate_reply(
  status : Int32,
  body : Json,
) -> @moonmuse.Reply raise @moonmuse.LlmError {
  if status >= 400 {
    raise @moonmuse.Status(code=status, body=body.stringify(), retry_after=None)
  }
  let candidates = @moonmuse.json_array(body, "candidates")
  if candidates.is_empty() {
    raise @moonmuse.Decode("generateContent returned no candidates")
  }
  let candidate = candidates[0]
  let parts = []
  let mut call_index = 0
  match @moonmuse.json_object(candidate, "content") {
    Some(fields) =>
      for part in @moonmuse.json_array(Json::object(fields), "parts") {
        match @moonmuse.json_field(part, "text") {
          Some(String(text)) =>
            if text != "" {
              parts.push(@moonmuse.Part::text(text))
            }
          _ => ()
        }
        match @moonmuse.json_field(part, "functionCall") {
          Some(call) => {
            let id = "call_" + call_index.to_string()
            call_index = call_index + 1
            parts.push(
              @moonmuse.Part::call(
                id,
                @moonmuse.json_string_or(call, "name", ""),
                @moonmuse.json_field(call, "args").unwrap_or(
                  Json::object(Map([])),
                ),
              ),
            )
          }
          None => ()
        }
      }
    None => ()
  }
  @moonmuse.Reply::new(
    @moonmuse.Message::new(@moonmuse.Assistant, parts),
    finish=@moonmuse.Finish::of(
      @moonmuse.json_string_or(candidate, "finishReason", "STOP"),
    ),
    usage=usage_of(body),
    raw=body,
  )
}

///|
/// The body that answers `reply`. The candidate count and model version are the fields
/// Gemini always writes, so they are written here too.
pub fn generate_answer(reply : @moonmuse.Reply) -> Json {
  let parts = []
  for part in reply.message.parts {
    match part {
      @moonmuse.Part::Text(text) =>
        if text != "" {
          parts.push(text_part(text))
        }
      @moonmuse.Part::Call(name~, args~, ..) =>
        parts.push(
          @moonmuse.object_json([
            (
              "functionCall",
              @moonmuse.object_json([
                ("name", Json::string(name)),
                ("args", args),
              ]),
            ),
          ]),
        )
      _ => ()
    }
  }
  let usage = []
  match reply.usage.input {
    Some(value) =>
      usage.push(("promptTokenCount", Json::number(value.to_double())))
    None => ()
  }
  match reply.usage.output {
    Some(value) =>
      usage.push(("candidatesTokenCount", Json::number(value.to_double())))
    None => ()
  }
  match reply.usage.cached {
    Some(value) =>
      usage.push(("cachedContentTokenCount", Json::number(value.to_double())))
    None => ()
  }
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
          ("finishReason", Json::string(finish_code(reply.finish))),
          ("index", Json::number(0.0)),
        ]),
      ]),
    ),
    ("usageMetadata", @moonmuse.object_json(usage)),
    (
      "modelVersion",
      Json::string(
        @moonmuse.json_string_or(reply.raw, "modelVersion", "moonmuse"),
      ),
    ),
  ])
}

///|
/// The finish reason as Gemini spells it.
pub fn finish_code(finish : @moonmuse.Finish) -> String {
  match finish {
    @moonmuse.Stop => "STOP"
    @moonmuse.Length => "MAX_TOKENS"
    @moonmuse.Calls => "STOP"
    @moonmuse.Filtered => "SAFETY"
    @moonmuse.Other(reason) => reason
  }
}

///|
/// The request a generateContent body asks for.
pub fn generate_parse(
  body : Json,
  model : String,
) -> @moonmuse.Request raise @moonmuse.LlmError {
  if model == "" {
    raise @moonmuse.Decode("generateContent path has no model")
  }
  let messages = []
  match @moonmuse.json_object(body, "systemInstruction") {
    Some(fields) => {
      let text = parts_text(Json::object(fields))
      if text != "" {
        messages.push(@moonmuse.Message::system(text))
      }
    }
    None => ()
  }
  for item in @moonmuse.json_array(body, "contents") {
    messages.push(content_of(item))
  }
  let tools = []
  for group in @moonmuse.json_array(body, "tools") {
    for declaration in @moonmuse.json_array(group, "functionDeclarations") {
      tools.push(
        @moonmuse.Tool::new(
          @moonmuse.json_string_or(declaration, "name", ""),
          @moonmuse.json_string_or(declaration, "description", ""),
          schema=@moonmuse.json_field(declaration, "parameters").unwrap_or(
            Json::object(Map([])),
          ),
        ),
      )
    }
  }
  let config = @moonmuse.json_field(body, "generationConfig").unwrap_or(
    Json::null(),
  )
  let choice = match @moonmuse.json_object(body, "toolConfig") {
    Some(fields) => {
      let calling = @moonmuse.json_field(
        Json::object(fields),
        "functionCallingConfig",
      ).unwrap_or(Json::null())
      match @moonmuse.json_string(calling, "mode") {
        Some("NONE") => @moonmuse.NoTools
        Some("ANY") => @moonmuse.Required
        _ => @moonmuse.Auto
      }
    }
    None => @moonmuse.Auto
  }
  @moonmuse.Request::new(
    model,
    messages,
    tools~,
    choice~,
    temperature?=@moonmuse.json_number(config, "temperature"),
    max_tokens?=@moonmuse.json_int(config, "maxOutputTokens"),
    stop=@moonmuse.json_strings(
      @moonmuse.json_field(config, "stopSequences").unwrap_or(Json::null()),
    ),
  )
}

///|
/// The text of every text part in a content object.
fn parts_text(content : Json) -> String {
  @moonmuse.json_array(content, "parts")
  .filter_map(part => @moonmuse.json_string(part, "text"))
  .join("")
}

///|
/// One `contents` entry as a message. Function calls get ids in arrival order, the same
/// rule the reply reader uses, so a call and its result pair up.
fn content_of(item : Json) -> @moonmuse.Message {
  let role = match @moonmuse.json_string(item, "role").unwrap_or("user") {
    "model" => @moonmuse.Assistant
    "system" => @moonmuse.System
    _ => @moonmuse.User
  }
  let parts = []
  for part in @moonmuse.json_array(item, "parts") {
    match @moonmuse.json_field(part, "text") {
      Some(String(text)) => parts.push(@moonmuse.Part::text(text))
      _ => ()
    }
    match @moonmuse.json_field(part, "functionCall") {
      Some(call) =>
        parts.push(
          @moonmuse.Part::call(
            "call_" + parts.length().to_string(),
            @moonmuse.json_string_or(call, "name", ""),
            @moonmuse.json_field(call, "args").unwrap_or(Json::object(Map([]))),
          ),
        )
      None => ()
    }
    match @moonmuse.json_field(part, "functionResponse") {
      Some(response) => {
        let content = match @moonmuse.json_object(response, "response") {
          Some(fields) => {
            let inner = Json::object(fields)
            match @moonmuse.json_string(inner, "content") {
              Some(text) => (text, false)
              None => (inner.stringify(), false)
            }
          }
          None => ("", false)
        }
        parts.push(@moonmuse.Part::result("", content.0, error=content.1))
      }
      None => ()
    }
  }
  @moonmuse.Message::new(role, parts)
}

///|
/// The error body Gemini sends.
pub fn error_json(error : @moonmuse.LlmError) -> (Int32, Json) {
  let (status, message) = match error {
    @moonmuse.Status(code~, body~, ..) => (code, body)
    @moonmuse.Stream(message) => (400, message)
    @moonmuse.Decode(message) => (400, message)
    @moonmuse.Unsupported(what) => (404, what)
  }
  (
    status,
    @moonmuse.object_json([
      (
        "error",
        @moonmuse.object_json([
          ("code", Json::number(status.to_double())),
          ("message", Json::string(message)),
          ("status", Json::string("INVALID_ARGUMENT")),
        ]),
      ),
    ]),
  )
}
