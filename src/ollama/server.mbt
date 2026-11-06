///|
/// The server half of Ollama's format: chat, generate, embed, tags, show and version.

///|
/// The model list as `/api/tags` returns it.
pub fn tags_answer(models : Array[@moonmuse.ModelInfo]) -> Json {
  let data = []
  for model in models {
    data.push(
      @moonmuse.object_json([
        ("name", Json::string(model.id)),
        ("model", Json::string(model.id)),
        ("size", Json::number(0.0)),
        (
          "details",
          @moonmuse.object_json([
            ("format", Json::string("gguf")),
            ("family", Json::string("moonmuse")),
          ]),
        ),
      ]),
    )
  }
  @moonmuse.object_json([("models", Json::array(data))])
}

///|
/// The embeddings body for `/api/embed`.
pub fn embed_answer(_model : String, vectors : Array[Array[Double]]) -> Json {
  @moonmuse.object_json([
    (
      "embeddings",
      Json::array(vectors.map(vector => @moonmuse.numbers_json(vector))),
    ),
  ])
}

///|
/// The body `/api/show` returns for a model.
pub fn show_answer(model : @moonmuse.ModelInfo) -> Json {
  @moonmuse.object_json([
    (
      "details",
      @moonmuse.object_json([
        ("format", Json::string("gguf")),
        ("family", Json::string("moonmuse")),
        ("parameter_size", Json::string("")),
        ("quantization_level", Json::string("")),
      ]),
    ),
    (
      "model_info",
      @moonmuse.object_json([
        (
          "general.context_length",
          match model.context {
            Some(value) => Json::number(value.to_double())
            None => Json::number(0.0)
          },
        ),
      ]),
    ),
    ("capabilities", @moonmuse.strings_json(["completion", "tools"])),
  ])
}

///|
pub impl @moonmuse.Dialect for Wire with fn name(_self) {
  "ollama"
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
    @moonmuse.Route::new(@moonmuse.Chat, "POST", "/api/chat"),
    @moonmuse.Route::new(@moonmuse.Generate, "POST", "/api/generate"),
    @moonmuse.Route::new(@moonmuse.Embed, "POST", "/api/embed"),
    @moonmuse.Route::new(@moonmuse.Models, "GET", "/api/tags"),
    @moonmuse.Route::new(@moonmuse.Show, "POST", "/api/show"),
    @moonmuse.Route::new(@moonmuse.Version, "GET", "/api/version"),
  ]
}

///|
pub impl @moonmuse.Dialect for Wire with fn parse(_self, route, body) {
  match route.kind {
    @moonmuse.Chat => @moonmuse.Asked::Chat(chat_parse(body))
    @moonmuse.Generate => @moonmuse.Asked::Chat(generate_parse(body))
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
    @moonmuse.Show => @moonmuse.Asked::Models
    @moonmuse.Version => @moonmuse.Asked::Models
    _ =>
      raise @moonmuse.Unsupported(
        "the Ollama format has no " + route.path + " endpoint",
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
pub impl @moonmuse.Dialect for Wire with fn answer_count(_self, reply) {
  @moonmuse.object_json([
    ("input_tokens", Json::number(reply.usage.input.unwrap_or(0).to_double())),
  ])
}

///|
pub impl @moonmuse.Dialect for Wire with fn answer_models(_self, models) {
  tags_answer(models)
}

///|
pub impl @moonmuse.Dialect for Wire with fn answer_at(_self, _kind, reply) {
  chat_answer(reply)
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
/// The request a `/api/generate` body asks for: a single prompt, not a message list.
fn generate_parse(body : Json) -> @moonmuse.Request raise @moonmuse.LlmError {
  let model = @moonmuse.json_string_or(body, "model", "")
  if model == "" {
    raise @moonmuse.Decode("generate request has no model")
  }
  let messages = []
  match @moonmuse.json_string(body, "system") {
    Some(text) => messages.push(@moonmuse.Message::system(text))
    None => ()
  }
  messages.push(
    @moonmuse.Message::user(@moonmuse.json_string_or(body, "prompt", "")),
  )
  let options = @moonmuse.json_field(body, "options").unwrap_or(Json::null())
  @moonmuse.Request::new(
    model,
    messages,
    temperature?=@moonmuse.json_number(options, "temperature"),
    max_tokens?=@moonmuse.json_int(options, "num_predict"),
    stop=@moonmuse.json_strings(
      @moonmuse.json_field(options, "stop").unwrap_or(Json::null()),
    ),
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
