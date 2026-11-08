///|
/// The server half of the OpenAI format: which endpoints it offers, how a served body
/// becomes a `Request`, and how an answer or an error becomes a body.

///|
/// The embeddings body, the shape OpenAI's `/v1/embeddings` returns.
pub fn embed_answer(model : String, vectors : Array[Array[Double]]) -> Json {
  let data = []
  for index, vector in vectors {
    data.push(
      @moonmuse.object_json([
        ("object", Json::string("embedding")),
        ("index", Json::number(index.to_double())),
        ("embedding", @moonmuse.numbers_json(vector)),
      ]),
    )
  }
  @moonmuse.object_json([
    ("object", Json::string("list")),
    ("data", Json::array(data)),
    ("model", Json::string(model)),
    (
      "usage",
      @moonmuse.object_json([
        ("prompt_tokens", Json::number(0.0)),
        ("total_tokens", Json::number(0.0)),
      ]),
    ),
  ])
}

///|
/// The model list body, listing what `models` reported.
pub fn models_answer(models : Array[@moonmuse.ModelInfo]) -> Json {
  let data = []
  for model in models {
    data.push(
      @moonmuse.object_json([
        ("id", Json::string(model.id)),
        ("object", Json::string("model")),
        ("owned_by", Json::string("moonmuse")),
      ]),
    )
  }
  @moonmuse.object_json([
    ("object", Json::string("list")),
    ("data", Json::array(data)),
  ])
}

///|
pub impl @moonmuse.Dialect for Wire with fn name(_self) {
  "openai"
}

///|
pub impl @moonmuse.Dialect for Wire with fn request(_self, request) {
  chat_call(request)
}

///|
pub impl @moonmuse.Dialect for Wire with fn reply(_self, status, body) {
  chat_reply(status, body)
}

///|
pub impl @moonmuse.Dialect for Wire with fn delta(_self, frame, turn) {
  stream_delta(frame, turn)
}

///|
pub impl @moonmuse.Dialect for Wire with fn routes(_self) {
  [
    @moonmuse.Route::new(@moonmuse.Chat, "POST", "/v1/chat/completions"),
    @moonmuse.Route::new(@moonmuse.Complete, "POST", "/v1/completions"),
    @moonmuse.Route::new(@moonmuse.Responses, "POST", "/v1/responses"),
    @moonmuse.Route::new(@moonmuse.Embed, "POST", "/v1/embeddings"),
    @moonmuse.Route::new(@moonmuse.Models, "GET", "/v1/models"),
  ]
}

///|
pub impl @moonmuse.Dialect for Wire with fn parse(_self, route, body) {
  match route.kind {
    @moonmuse.Chat => @moonmuse.Asked::Chat(chat_parse(body))
    @moonmuse.Complete => @moonmuse.Asked::Chat(complete_parse(body))
    @moonmuse.Responses => @moonmuse.Asked::Chat(responses_parse(body))
    @moonmuse.Embed => {
      let model = @moonmuse.json_string_or(body, "model", "")
      let inputs = match @moonmuse.json_field(body, "input") {
        Some(String(text)) => [text]
        Some(Array(items)) =>
          items.filter_map(item => @moonmuse.json_as_string(item))
        _ => []
      }
      @moonmuse.Asked::Embed(model~, inputs~)
    }
    @moonmuse.Models => @moonmuse.Asked::Models
    _ =>
      raise @moonmuse.Unsupported(
        "the OpenAI format has no " + route.path + " endpoint",
      )
  }
}

///|
pub impl @moonmuse.Dialect for Wire with fn answer(_self, reply) {
  chat_answer(reply)
}

///|
pub impl @moonmuse.Dialect for Wire with fn answer_embed(_self, model, vectors) {
  embed_answer(model, vectors)
}

///|
pub impl @moonmuse.Dialect for Wire with fn answer_count(_self, count) {
  @moonmuse.object_json([("input_tokens", Json::number(count.to_double()))])
}

///|
/// The body of `/v1/completions`.
pub fn complete_answer(reply : @moonmuse.Reply) -> Json {
  let choices = []
  for part in reply.message.parts {
    match part {
      @moonmuse.Part::Text(text) =>
        choices.push(
          @moonmuse.object_json([
            ("text", Json::string(text)),
            ("index", Json::number(0.0)),
            ("finish_reason", Json::string(finish_code(reply.finish))),
          ]),
        )
      _ => ()
    }
  }
  if choices.is_empty() {
    choices.push(
      @moonmuse.object_json([
        ("text", Json::string("")),
        ("index", Json::number(0.0)),
        ("finish_reason", Json::string(finish_code(reply.finish))),
      ]),
    )
  }
  @moonmuse.object_json([
    ("id", Json::string("cmpl-moonmuse")),
    ("object", Json::string("text_completion")),
    ("choices", Json::array(choices)),
    ("usage", usage_json(reply.usage)),
  ])
}

///|
/// The body of `/v1/responses`.
pub fn responses_answer(reply : @moonmuse.Reply) -> Json {
  let content = []
  for part in reply.message.parts {
    match part {
      @moonmuse.Part::Text(text) =>
        content.push(
          @moonmuse.object_json([
            ("type", Json::string("output_text")),
            ("text", Json::string(text)),
          ]),
        )
      _ => ()
    }
  }
  let output = [
    @moonmuse.object_json([
      ("type", Json::string("message")),
      ("role", Json::string("assistant")),
      ("content", Json::array(content)),
    ]),
  ]
  let calls = reply.message.calls()
  for part in calls {
    match part {
      @moonmuse.Part::Call(id~, name~, args~) =>
        output.push(
          @moonmuse.object_json([
            ("type", Json::string("function_call")),
            ("id", Json::string(id)),
            ("call_id", Json::string(id)),
            ("name", Json::string(name)),
            ("arguments", Json::string(args.stringify())),
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
  @moonmuse.object_json([
    ("id", Json::string("resp_moonmuse")),
    ("object", Json::string("response")),
    ("status", Json::string("completed")),
    ("output", Json::array(output)),
    ("usage", @moonmuse.object_json(usage)),
  ])
}

///|
pub impl @moonmuse.Dialect for Wire with fn answer_models(_self, models) {
  models_answer(models)
}

///|
pub impl @moonmuse.Dialect for Wire with fn answer_at(_self, kind, reply) {
  match kind {
    @moonmuse.Complete => complete_answer(reply)
    @moonmuse.Responses => responses_answer(reply)
    _ => chat_answer(reply)
  }
}

///|
pub impl @moonmuse.Dialect for Wire with fn frame(_self, delta, turn) {
  stream_frame(delta, turn)
}

///|
pub impl @moonmuse.Dialect for Wire with fn error(_self, error) {
  error_json(error)
}

///|
/// A legacy completion body, whose prompt is a string or a list of strings. Only the
/// first prompt is answered, which is what a gateway with one model behind it can do.
fn complete_parse(body : Json) -> @moonmuse.Request raise @moonmuse.LlmError {
  let model = @moonmuse.json_string_or(body, "model", "")
  if model == "" {
    raise @moonmuse.Decode("completion request has no model")
  }
  let prompt = match @moonmuse.json_field(body, "prompt") {
    Some(String(text)) => text
    Some(Array(items)) =>
      items.filter_map(item => @moonmuse.json_as_string(item)).join("\n")
    _ => ""
  }
  @moonmuse.Request::new(
    model,
    [@moonmuse.Message::user(prompt)],
    temperature?=@moonmuse.json_number(body, "temperature"),
    max_tokens?=@moonmuse.json_int(body, "max_tokens"),
    stop=@moonmuse.json_strings(
      @moonmuse.json_field(body, "stop").unwrap_or(Json::null()),
    ),
  )
}

///|
/// A Responses API body. The newer endpoint names its input `input` and its system
/// message `instructions`; both become ordinary messages here.
fn responses_parse(body : Json) -> @moonmuse.Request raise @moonmuse.LlmError {
  let model = @moonmuse.json_string_or(body, "model", "")
  if model == "" {
    raise @moonmuse.Decode("responses request has no model")
  }
  let messages = []
  match @moonmuse.json_string(body, "instructions") {
    Some(text) => messages.push(@moonmuse.Message::system(text))
    None => ()
  }
  match @moonmuse.json_field(body, "input") {
    Some(String(text)) => messages.push(@moonmuse.Message::user(text))
    Some(Array(items)) =>
      for item in items {
        let role = @moonmuse.json_string_or(item, "role", "user")
        let text = match @moonmuse.json_field(item, "content") {
          Some(String(text)) => text
          Some(Array(parts)) =>
            parts
            .filter_map(part => {
              match @moonmuse.json_string(part, "type") {
                Some("input_text") | Some("output_text") | Some("text") =>
                  @moonmuse.json_string(part, "text")
                _ => None
              }
            })
            .join("")
          _ => ""
        }
        messages.push(
          @moonmuse.Message::new(
            if role == "assistant" {
              @moonmuse.Assistant
            } else if role == "system" || role == "developer" {
              @moonmuse.System
            } else {
              @moonmuse.User
            },
            [@moonmuse.Part::text(text)],
          ),
        )
      }
    _ => ()
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
  @moonmuse.Request::new(
    model,
    messages,
    tools~,
    temperature?=@moonmuse.json_number(body, "temperature"),
    max_tokens?=@moonmuse.json_int(body, "max_output_tokens"),
  )
}

///|
pub extend Wire with @moonmuse.Dialect::{
  name,
  request,
  reply,
  delta,
  routes,
  parse,
  answer,
  answer_embed,
  answer_count,
  answer_models,
  answer_at,
  frame,
  error,
}
