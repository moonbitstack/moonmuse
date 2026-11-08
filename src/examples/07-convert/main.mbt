///|
/// The converter behind the site's four panes. A reader edits one body; this reads it with that
/// format's own reader and writes the other three with their own writers, so the page shows what
/// the library does rather than a transcription of it.
///
/// The result is JSON — `{ok: true, verb, path, headers, body}`, or `{ok: false, error}` — since
/// the whole surface is one string in and one string out.

///|
/// A dialect by the name the page uses for it.
fn dialect_of(name : String) -> &@moonmuse.Dialect raise @moonmuse.LlmError {
  // Each return is coerced to the trait object on its own, which a `match` arm is not.
  if name == "openai" {
    return @openai.dialect
  } else if name == "anthropic" {
    return @anthropic.dialect
  } else if name == "gemini" {
    return @gemini.dialect
  } else if name == "ollama" {
    return @ollama.dialect
  }
  raise @moonmuse.Unsupported("no format is called " + name)
}

///|
/// The headers as a JSON object, since the page shows them beside the path.
fn headers_json(call : @moonmuse.Call) -> Json {
  let pairs = []
  for header in call.headers {
    pairs.push((header.0, Json::string(header.1)))
  }
  @moonmuse.object_json(pairs)
}

///|
/// One body read with `source`'s reader, written with `target`'s writer. `path` is the endpoint
/// the body was sent to, because a format may carry part of the request in the URL — Gemini
/// names the model there and nowhere else.
fn rewrite(
  source : String,
  target : String,
  path : String,
  body : String,
) -> Json raise @moonmuse.LlmError {
  let from = dialect_of(source)
  let to = dialect_of(target)
  let route = @moonmuse.Route::new(@moonmuse.Chat, "POST", path)
  let asked = @moonmuse.Dialect::parse(
    from,
    route,
    @moonmuse.parse_json_lossy(body),
  )
  let request = match asked {
    @moonmuse.Asked::Chat(request) => request
    _ => raise @moonmuse.Unsupported("that body is not a chat request")
  }
  let call = @moonmuse.Dialect::request(to, request)
  @moonmuse.object_json([
    ("ok", Json::boolean(true)),
    ("verb", Json::string(call.verb)),
    ("path", Json::string(call.path)),
    ("headers", headers_json(call)),
    ("body", call.body),
  ])
}

///|
/// The entry point the page calls. Never raises: a body the format cannot read comes back as
/// `{ok: false, error}`, which is the shape the page shows under the pane that was edited.
pub fn convert(
  source : String,
  target : String,
  path : String,
  body : String,
) -> String {
  let answer = rewrite(source, target, path, body) catch {
    error =>
      @moonmuse.object_json([
        ("ok", Json::boolean(false)),
        ("error", Json::string(error.describe())),
      ])
  }
  answer.stringify()
}
