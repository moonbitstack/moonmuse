///|
/// The server half of the Gemini format: generateContent, its streaming twin, embedContent,
/// and the model list. The model name is read out of the path, which is where Gemini puts
/// it.

///|
/// The model named in a Gemini path, with the `/models/` prefix and the method suffix
/// removed.
pub fn model_of(path : String) -> String {
  let start = match path.find("/models/") {
    Some(at) => at + 8
    None => return ""
  }
  let rest = path.exact_view(start~).to_owned()
  match rest.find(":") {
    Some(at) => rest.exact_view(start=0, end=at).to_owned()
    None => rest
  }
}

///|
/// The model list as Gemini's API returns it.
pub fn models_answer(models : Array[@moonmuse.ModelInfo]) -> Json {
  let data = []
  for model in models {
    data.push(
      @moonmuse.object_json([
        ("name", Json::string("models/" + model.id)),
        ("displayName", Json::string(model.id)),
        ("description", Json::string("")),
        (
          "supportedGenerationMethods",
          @moonmuse.strings_json(["generateContent", "embedContent"]),
        ),
      ]),
    )
  }
  @moonmuse.object_json([("models", Json::array(data))])
}

///|
/// The embeddings body for one input, in Gemini's shape.
pub fn embed_answer(_model : String, vectors : Array[Array[Double]]) -> Json {
  let data = []
  for vector in vectors {
    data.push(
      @moonmuse.object_json([("values", @moonmuse.numbers_json(vector))]),
    )
  }
  @moonmuse.object_json([("embeddings", Json::array(data))])
}

///|
pub impl @moonmuse.Dialect for Wire with fn name(_self) {
  "gemini"
}

///|
pub impl @moonmuse.Dialect for Wire with fn request(_self, request) {
  generate_call(request)
}

///|
pub impl @moonmuse.Dialect for Wire with fn reply(_self, status, body) {
  generate_reply(status, body)
}

///|
pub impl @moonmuse.Dialect for Wire with fn delta(_self, frame, turn) {
  stream_delta(frame, turn)
}

///|
pub impl @moonmuse.Dialect for Wire with fn routes(_self) {
  [
    @moonmuse.Route::new(
      @moonmuse.Embed,
      "POST",
      "/v1beta/models/*:embedContent",
    ),
    @moonmuse.Route::new(
      @moonmuse.Embed,
      "POST",
      "/v1beta/models/*:batchEmbedContents",
    ),
    @moonmuse.Route::new(
      @moonmuse.Chat,
      "POST",
      "/v1beta/models/*:generateContent",
    ),
    @moonmuse.Route::new(
      @moonmuse.Chat,
      "POST",
      "/v1beta/models/*:streamGenerateContent",
    ),
    @moonmuse.Route::new(@moonmuse.Models, "GET", "/v1beta/models"),
  ]
}

///|
pub impl @moonmuse.Dialect for Wire with fn parse(_self, route, body) {
  match route.kind {
    @moonmuse.Chat =>
      @moonmuse.Asked::Chat(generate_parse(body, model_of(route.path)))
    @moonmuse.Embed => {
      let model = model_of(route.path)
      let inputs = match @moonmuse.json_object(body, "requests") {
        Some(_) =>
          @moonmuse.json_array(body, "requests").map(request => {
            part_text(request)
          })
        None => [part_text(body)]
      }
      @moonmuse.Asked::Embed(model~, inputs~)
    }
    @moonmuse.Models => @moonmuse.Asked::Models
    _ =>
      raise @moonmuse.Unsupported(
        "the Gemini format has no " + route.path + " endpoint",
      )
  }
}

///|
/// The text of one embedContent request.
fn part_text(body : Json) -> String {
  match @moonmuse.json_object(body, "content") {
    Some(fields) =>
      @moonmuse.json_array(Json::object(fields), "parts")
      .filter_map(part => @moonmuse.json_string(part, "text"))
      .join("")
    None => ""
  }
}

///|
pub impl @moonmuse.Dialect for Wire with fn answer(_self, reply) {
  generate_answer(reply)
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
  models_answer(models)
}

///|
pub impl @moonmuse.Dialect for Wire with fn answer_at(_self, _kind, reply) {
  generate_answer(reply)
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
