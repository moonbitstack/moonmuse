///|
/// The server half of the Anthropic format: the Messages endpoint, its token counter, and
/// the model list.

///|
/// The model list in the shape Anthropic's console returns.
pub fn models_answer(models : Array[@moonmuse.ModelInfo]) -> Json {
  let data = []
  for model in models {
    data.push(
      @moonmuse.object_json([
        ("id", Json::string(model.id)),
        ("type", Json::string("model")),
        ("display_name", Json::string(model.id)),
        ("created_at", Json::string("2026-01-01T00:00:00Z")),
      ]),
    )
  }
  let first = if models.is_empty() { "" } else { models[0].id }
  let last = if models.is_empty() { "" } else { models[models.length() - 1].id }
  @moonmuse.object_json([
    ("data", Json::array(data)),
    ("has_more", Json::boolean(false)),
    ("first_id", Json::string(first)),
    ("last_id", Json::string(last)),
  ])
}

///|
pub impl @moonmuse.Dialect for Wire with fn name(_self) {
  "anthropic"
}

///|
pub impl @moonmuse.Dialect for Wire with fn request(_self, request) {
  message_call(request)
}

///|
pub impl @moonmuse.Dialect for Wire with fn reply(_self, status, body) {
  message_reply(status, body)
}

///|
pub impl @moonmuse.Dialect for Wire with fn delta(_self, frame, turn) {
  stream_delta(frame, turn)
}

///|
pub impl @moonmuse.Dialect for Wire with fn routes(_self) {
  [
    @moonmuse.Route::new(@moonmuse.Chat, "POST", "/v1/messages"),
    @moonmuse.Route::new(@moonmuse.Count, "POST", "/v1/messages/count_tokens"),
    @moonmuse.Route::new(@moonmuse.Models, "GET", "/v1/models"),
  ]
}

///|
pub impl @moonmuse.Dialect for Wire with fn parse(_self, route, body) {
  match route.kind {
    @moonmuse.Chat => @moonmuse.Asked::Chat(message_parse(body))
    @moonmuse.Count => @moonmuse.Asked::Count(message_parse(body))
    @moonmuse.Models => @moonmuse.Asked::Models
    _ =>
      raise @moonmuse.Unsupported(
        "the Anthropic format has no " + route.path + " endpoint",
      )
  }
}

///|
pub impl @moonmuse.Dialect for Wire with fn answer(_self, reply) {
  message_answer(reply)
}

///|
pub impl @moonmuse.Dialect for Wire with fn answer_embed(
  _self,
  _model,
  _vectors,
) {
  Json::empty_object()
}

///|
pub impl @moonmuse.Dialect for Wire with fn answer_count(_self, reply) {
  let input = reply.usage.input.unwrap_or(0)
  @moonmuse.object_json([("input_tokens", Json::number(input.to_double()))])
}

///|
pub impl @moonmuse.Dialect for Wire with fn answer_models(_self, models) {
  models_answer(models)
}

///|
pub impl @moonmuse.Dialect for Wire with fn answer_at(_self, _kind, reply) {
  message_answer(reply)
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
