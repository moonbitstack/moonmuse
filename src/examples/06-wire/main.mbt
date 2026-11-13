///|
/// The body each dialect writes for one canonical chat, as JSON on stdout. `scripts/difftest`
/// compares this against what the official client libraries send for the same conversation:
/// the SDK is the oracle for the wire, so a disagreement is a defect in one of the two.
///
///     moon run src/examples/06-wire --target native

///|
/// The conversation every format is asked to encode. The model differs per vendor, so it is
/// the one thing not shared.
fn canonical(model : String) -> @moonmuse.Request {
  @moonmuse.Request::new(
    model,
    [
      @moonmuse.Message::system("Answer in one sentence."),
      @moonmuse.Message::user("Why is the sky blue?"),
    ],
    temperature=0.2,
    max_tokens=256,
  )
}

///|
/// One dialect's call as a JSON object: the path, the query and the body.
fn dump(
  dialect : &@moonmuse.Dialect,
  model : String,
) -> Json raise @moonmuse.LlmError {
  let call = @moonmuse.Dialect::request(dialect, canonical(model))
  let query = []
  for pair in call.query {
    query.push((pair.0, Json::string(pair.1)))
  }
  @moonmuse.object_json([
    ("verb", Json::string(call.verb)),
    ("path", Json::string(call.path)),
    ("query", @moonmuse.object_json(query)),
    ("body", call.body),
  ])
}

///|
fn main raise {
  let formats : Array[(String, &@moonmuse.Dialect, String)] = [
    ("openai", @openai.dialect, "gpt-4o-mini"),
    ("anthropic", @anthropic.dialect, "claude-sonnet-4-20250514"),
    ("gemini", @gemini.dialect, "gemini-2.0-flash"),
    ("ollama", @ollama.dialect, "qwen2.5"),
  ]
  let out = Map([])
  for entry in formats {
    let (name, dialect, model) = entry
    out[name] = dump(dialect, model)
  }
  println(@json.dumps(Json::object(out)))
}
