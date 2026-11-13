///|
/// OpenAI's chat-completions shape. One value of this type serves both directions: the
/// client asks in this format, and a gateway that offers this format answers in it.

///|
/// The OpenAI wire format.
pub struct Wire {}

///|
/// The one instance; it carries no state, so a dialect can be a value.
pub let dialect : Wire = Wire::{ }

///|
/// Whether a body's `stream` field asks for a streamed answer.
pub fn is_stream(body : Json) -> Bool {
  @moonmuse.json_bool(body, "stream").unwrap_or(false)
}

///|
/// The chat-completions call for `request`, with `extra` merged in last.
pub fn chat_call(request : @moonmuse.Request) -> @moonmuse.Call {
  let messages = []
  for message in request.messages {
    for item in messages_json(message) {
      messages.push(item)
    }
  }
  let fields : Array[(String, Json)] = [
    ("model", Json::string(request.model)),
    ("messages", Json::array(messages)),
  ]
  if !request.tools.is_empty() {
    fields.push(("tools", Json::array(request.tools.map(tool_json))))
  }
  if request.choice != @moonmuse.Auto {
    fields.push(("tool_choice", tool_choice_json(request.choice)))
  }
  match request.temperature {
    Some(value) => fields.push(("temperature", Json::number(value)))
    None => ()
  }
  match request.max_tokens {
    Some(value) => fields.push(("max_tokens", Json::number(value.to_double())))
    None => ()
  }
  if !request.stop.is_empty() {
    fields.push(("stop", @moonmuse.strings_json(request.stop)))
  }
  let body = Json::object(@moonmuse.merge_json(of_pairs(fields), request.extra))
  @moonmuse.Call::new("POST", "/chat/completions", body)
}

///|
/// A map from pairs, last one winning.
fn of_pairs(fields : Array[(String, Json)]) -> Map[String, Json] {
  let map = Map([])
  for pair in fields {
    map[pair.0] = pair.1
  }
  map
}

///|
/// The reply a chat-completions body describes. A non-success status becomes an
/// `LlmError` rather than a reply with an empty message.
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
  let choices = @moonmuse.json_array(body, "choices")
  guard !choices.is_empty() else {
    raise @moonmuse.Decode(
      "chat completion has no choices: " + @json.dumps(body),
    )
  }
  let choice = choices[0]
  let message = @moonmuse.json_object(choice, "message")
  let parts = []
  match message {
    Some(fields) => {
      let wire_message = Json::object(fields)
      match @moonmuse.json_string(wire_message, "content") {
        Some(text) => if text != "" { parts.push(@moonmuse.Part::text(text)) }
        None => ()
      }
      for item in @moonmuse.json_array(wire_message, "tool_calls") {
        parts.push(call_part(item))
      }
      match @moonmuse.json_object(wire_message, "function_call") {
        Some(fields) =>
          parts.push(
            @moonmuse.Part::call(
              "",
              @moonmuse.json_string_or(Json::object(fields), "name", ""),
              parse_arguments(
                @moonmuse.json_string_or(Json::object(fields), "arguments", ""),
              ),
            ),
          )
        None => ()
      }
    }
    None => ()
  }
  let finish = @moonmuse.Finish::of(
    @moonmuse.json_string_or(choice, "finish_reason", "stop"),
  )
  let reply = @moonmuse.Reply::new(
    @moonmuse.Message::new(@moonmuse.Assistant, parts),
    finish~,
    usage=usage_of(body),
    raw=body,
  )
  reply
}

///|
/// One `tool_calls` entry as a call part.
pub fn call_part(item : Json) -> @moonmuse.Part {
  let function = match @moonmuse.json_object(item, "function") {
    Some(fields) => Json::object(fields)
    None => Json::null()
  }
  @moonmuse.Part::call(
    @moonmuse.json_string_or(item, "id", ""),
    @moonmuse.json_string_or(function, "name", ""),
    parse_arguments(@moonmuse.json_string_or(function, "arguments", "")),
  )
}

///|
/// Tool arguments arrive as a JSON string inside the JSON body, and a model can send a
/// string that is not JSON. That is the tool's problem to report, not the transport's to
/// crash on, so the unparsable case becomes an empty object.
pub fn parse_arguments(text : String) -> Json {
  @moonmuse.parse_json_lossy(text)
}

///|
/// The chat-completions body that answers `reply`.
pub fn chat_answer(reply : @moonmuse.Reply) -> Json {
  let calls = reply.message.calls()
  let text = reply.message.text_content(separator="")
  let fields = [("role", Json::string("assistant"))]
  fields.push(
    (
      "content",
      if text == "" && !calls.is_empty() {
        Json::null()
      } else {
        Json::string(text)
      },
    ),
  )
  if !calls.is_empty() {
    let encoded = []
    for part in calls {
      match part {
        @moonmuse.Call(id~, name~, args~) =>
          encoded.push(
            @moonmuse.object_json([
              ("id", Json::string(id)),
              ("type", Json::string("function")),
              (
                "function",
                @moonmuse.object_json([
                  ("name", Json::string(name)),
                  ("arguments", Json::string(@json.dumps(args))),
                ]),
              ),
            ]),
          )
        _ => ()
      }
    }
    fields.push(("tool_calls", Json::array(encoded)))
  }
  @moonmuse.object_json([
    ("id", Json::string("chatcmpl-" + reply_timestamp(reply))),
    ("object", Json::string("chat.completion")),
    (
      "choices",
      Json::array([
        @moonmuse.object_json([
          ("index", Json::number(0.0)),
          ("message", @moonmuse.object_json(fields)),
          ("finish_reason", Json::string(finish_code(reply.finish))),
        ]),
      ]),
    ),
    ("usage", usage_json(reply.usage)),
  ])
}

///|
/// A stable id for an answer this library produced. The number is the reply's text
/// length and its first token count, so replaying the same reply yields the same id.
fn reply_timestamp(reply : @moonmuse.Reply) -> String {
  (reply.message.text_content(separator="").length() +
  reply.usage.total().unwrap_or(0)).to_string()
}

///|
/// The finish reason as the wire spells it.
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
/// The request a chat-completions body asks for, with the fields this library does not
/// model kept in `extra`.
pub fn chat_parse(body : Json) -> @moonmuse.Request raise @moonmuse.LlmError {
  let model = @moonmuse.json_string_or(body, "model", "")
  if model == "" {
    raise @moonmuse.Decode("chat request has no model")
  }
  let messages = []
  for item in @moonmuse.json_array(body, "messages") {
    for one in messages_of(item) {
      messages.push(one)
    }
  }
  let tools = []
  for item in @moonmuse.json_array(body, "tools") {
    let function = match @moonmuse.json_object(item, "function") {
      Some(fields) => Json::object(fields)
      None => item
    }
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
  let choice = match @moonmuse.json_field(body, "tool_choice") {
    Some(String("auto")) => @moonmuse.Auto
    Some(String("none")) => @moonmuse.NoTools
    Some(String("required")) => @moonmuse.Required
    Some(Object(fields)) =>
      match fields.get("function") {
        Some(inner) =>
          @moonmuse.Named(@moonmuse.json_string_or(inner, "name", ""))
        None => @moonmuse.Auto
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
      @moonmuse.json_field(body, "stop").unwrap_or(Json::null()),
    ),
    extra~,
  )
}

///|
/// The messages a wire message describes. An assistant message that called tools and a
/// tool message that answers them both map back to one shared message.
pub fn messages_of(item : Json) -> Array[@moonmuse.Message] {
  let role = match @moonmuse.json_string(item, "role").unwrap_or("user") {
    "system" | "developer" => @moonmuse.System
    "assistant" => @moonmuse.Assistant
    "tool" | "function" => @moonmuse.Tool
    _ => @moonmuse.User
  }
  let parts = []
  match @moonmuse.json_field(item, "content") {
    Some(String(text)) =>
      if text != "" || role != @moonmuse.Assistant {
        parts.push(@moonmuse.Part::text(text))
      }
    Some(Array(items)) =>
      for part in items {
        match @moonmuse.json_string(part, "type") {
          Some("text") =>
            parts.push(
              @moonmuse.Part::text(@moonmuse.json_string_or(part, "text", "")),
            )
          Some("image_url") => {
            let url = match @moonmuse.json_object(part, "image_url") {
              Some(fields) =>
                @moonmuse.json_string_or(Json::object(fields), "url", "")
              None => ""
            }
            parts.push(@moonmuse.Image(url~, media=None))
          }
          _ => ()
        }
      }
    _ => ()
  }
  for entry in @moonmuse.json_array(item, "tool_calls") {
    parts.push(call_part(entry))
  }
  if role == @moonmuse.Tool {
    let id = @moonmuse.json_string_or(item, "tool_call_id", "")
    let content = parts.map(part => part.text_of()).join("")
    return [@moonmuse.Message::tool(content, id~)]
  }
  [@moonmuse.Message::new(role, parts)]
}
