///|
/// Exporting a provider as an API. One provider — a remote client, a routed table, a local
/// model, a fake — becomes an ASGI application that speaks whichever formats the caller
/// listed. Nothing here knows a vendor's field names: every request and every answer goes
/// through the same `Dialect` the client uses.

///|
/// Who may call. Implement it for a key table, or for whatever an installation already has.
pub(open) trait Keys {
  fn accepts(Self, Array[(String, String)]) -> Bool
}

///|
/// A table of bearer keys.
pub struct StaticKeys {
  keys : Map[String, String]
}

///|
/// Keys from a list, each mapped to itself.
pub fn StaticKeys::new(keys : Array[String]) -> StaticKeys {
  let map = Map([])
  for key in keys {
    map[key] = key
  }
  StaticKeys::{ keys: map, }
}

///|
/// Keys from a map of key to tenant name.
pub fn StaticKeys::of(keys : Map[String, String]) -> StaticKeys {
  StaticKeys::{ keys, }
}

///|
pub impl Keys for StaticKeys with fn accepts(self, headers) {
  let presented = credentials(headers)
  match presented {
    Some(key) => self.keys.contains(key)
    None => false
  }
}

///|
pub extend StaticKeys with Keys::{accepts}

///|
/// The credential a request presents: a bearer token, or Anthropic's own header.
pub fn credentials(headers : Array[(String, String)]) -> String? {
  let mut found = None
  for pair in headers {
    let name = pair.0.to_lower()
    if name == "x-api-key" {
      found = Some(pair.1)
    } else if name == "authorization" {
      let value = pair.1
      if value.to_lower().has_prefix("bearer ") {
        found = Some(value.exact_view(start=7).to_owned())
      } else {
        found = Some(value)
      }
    }
  }
  found
}

///|
/// Limits on what a gateway accepts.
#derive(Eq, Debug)
pub(all) struct Limits {
  /// The largest request body, in bytes.
  body : Int32
  /// The largest answer, in tokens.
  max_tokens : Int32
}

///|
/// 8 MiB of request and 4096 tokens of answer.
pub fn Limits::default() -> Limits {
  { body: 8 * 1024 * 1024, max_tokens: 4096, }
}

///|
/// The path a scope asked for.
pub fn serve(
  provider : &@moonmuse.Provider,
  dialects~ : Array[&@moonmuse.Dialect],
  keys? : &Keys,
  limits~ : Limits = Limits::default(),
) -> @moonasgi.AsgiApp {
  (scope, receive, send) => {
    match scope {
      Http(hs) => {
        let buf = Buffer()
        while true {
          let event = receive()
          match event {
            HttpResponseStart(..) => break
            HttpRequest(body~, more_body~) => {
              buf.write_bytes(body[:])
              if !more_body {
                break
              }
            }
            _ => break
          }
        }
        let body = buf.to_bytes()
        let response = respond(
          provider,
          dialects,
          keys,
          limits,
          hs.http_method,
          hs.path,
          hs.query_string,
          hs.headers,
          body,
        )
        for event in response.events() {
          send(event)
        }
      }
      Lifespan(lifespan) => {
        let _ = lifespan
        let mut running = true
        while running {
          let event = receive()
          match event {
            LifespanStartup => send(LifespanStartupComplete)
            LifespanShutdown => {
              send(LifespanShutdownComplete)
              running = false
            }
            _ => running = false
          }
        }
      }
      _ => ()
    }
  }
}

///|
/// The answer to one request, as an ASGI response or a streamed one.
async fn respond(
  provider : &@moonmuse.Provider,
  dialects : Array[&@moonmuse.Dialect],
  keys : &Keys?,
  limits : Limits,
  verb : String,
  path : String,
  query : Bytes,
  headers : Array[(String, String)],
  body : Bytes,
) -> @http.StreamingResponse {
  match keys {
    Some(keys) =>
      if !keys.accepts(headers) {
        return error_response(
          @moonmuse.Status(
            code=401,
            body="missing or invalid credential",
            retry_after=None,
          ),
          first_dialect(dialects),
        )
      }
    None => ()
  }
  if body.length() > limits.body {
    return error_response(
      @moonmuse.Status(
        code=413,
        body="request body is too large",
        retry_after=None,
      ),
      first_dialect(dialects),
    )
  }
  let text = @utf8.decode(body) catch { _ => "" }
  let payload = if text.trim() == "" {
    Json::empty_object()
  } else {
    @json.parse(text) catch {
      _ =>
        return error_response(
          @moonmuse.Decode("request body is not JSON"),
          first_dialect(dialects),
        )
    }
  }
  let (dialect, route) = match find_route(dialects, verb, path, headers) {
    Some(found) => found
    None =>
      return error_response(
        @moonmuse.Unsupported("no endpoint at " + path),
        first_dialect(dialects),
      )
  }
  let asked = @moonmuse.Dialect::parse(dialect, route, payload) catch {
    error => return error_response(error, dialect)
  }
  match asked {
    @moonmuse.Asked::Chat(request) => {
      let request = clamp(request, limits)
      if wants_stream(query, payload, path) {
        let turn = @moonmuse.Turn::new()
        let frames = []
        let reply = provider.stream(request, delta => {
          for frame in @moonmuse.Dialect::frame(dialect, delta, turn) {
            frames.push(frame)
          }
        }) catch {
          error => return error_response(error, dialect)
        }
        if frames.is_empty() {
          for
            frame in @moonmuse.Dialect::frame(
              dialect,
              @moonmuse.Delta::Done(reply),
              turn,
            ) {
            frames.push(frame)
          }
        }
        stream_response(dialect, frames, path)
      } else {
        let reply = provider.chat(request) catch {
          error => return error_response(error, dialect)
        }
        json_response(@moonmuse.Dialect::answer_at(dialect, route.kind, reply))
      }
    }
    @moonmuse.Asked::Embed(model~, inputs~) => {
      let vectors = provider.embed(model, inputs) catch {
        error => return error_response(error, dialect)
      }
      json_response(@moonmuse.Dialect::answer_embed(dialect, model, vectors))
    }
    @moonmuse.Asked::Models => {
      let models = provider.models() catch {
        error => return error_response(error, dialect)
      }
      json_response(@moonmuse.Dialect::answer_models(dialect, models))
    }
    @moonmuse.Asked::Count(_) =>
      error_response(
        @moonmuse.Unsupported(
          "counting tokens needs a tokenizer, which this gateway has not",
        ),
        dialect,
      )
  }
}

///|
/// The request with the gateway's token ceiling applied.
fn clamp(request : @moonmuse.Request, limits : Limits) -> @moonmuse.Request {
  match request.max_tokens {
    Some(value) =>
      if value <= limits.max_tokens {
        request
      } else {
        { ..request, max_tokens: Some(limits.max_tokens), }
      }
    None => { ..request, max_tokens: Some(limits.max_tokens), }
  }
}

///|
/// Whether the caller asked for a streamed answer, in the three ways the formats express it.
fn wants_stream(query : Bytes, body : Json, path : String) -> Bool {
  if path.contains("streamGenerateContent") {
    return true
  }
  let query = @utf8.decode(query) catch { _ => "" }
  if query.contains("alt=sse") {
    return true
  }
  @moonmuse.json_bool(body, "stream").unwrap_or(false)
}

///|
/// The dialect and route that answer this verb and path. Where two formats share a path —
/// both Anthropic and OpenAI list models at `/v1/models` — the presence of Anthropic's
/// version header decides.
fn find_route(
  dialects : Array[&@moonmuse.Dialect],
  verb : String,
  path : String,
  headers : Array[(String, String)],
) -> (&@moonmuse.Dialect, @moonmuse.Route)? {
  let preferred = if has_header(headers, "anthropic-version") {
    Some("anthropic")
  } else {
    None
  }
  // Two formats can claim the same path; the one whose header is present wins, and otherwise
  // the first listed does.
  match preferred {
    Some(name) =>
      for dialect in dialects {
        if @moonmuse.Dialect::name(dialect) == name {
          for route in @moonmuse.Dialect::routes(dialect) {
            if route.matches(verb, path) {
              return Some((dialect, route))
            }
          }
        }
      }
    None => ()
  }
  for dialect in dialects {
    for route in @moonmuse.Dialect::routes(dialect) {
      if route.matches(verb, path) {
        return Some((dialect, route))
      }
    }
  }
  None
}

///|
/// Whether a header is present.
fn has_header(headers : Array[(String, String)], name : String) -> Bool {
  for pair in headers {
    if pair.0.to_lower() == name {
      return true
    }
  }
  false
}

///|
/// The dialect an unroutable request is answered in.
fn first_dialect(dialects : Array[&@moonmuse.Dialect]) -> &@moonmuse.Dialect {
  let fallback : &@moonmuse.Dialect = @openai.dialect
  if dialects.is_empty() {
    fallback
  } else {
    dialects[0]
  }
}

///|
/// A JSON answer.
fn json_response(body : Json) -> @http.StreamingResponse {
  @http.StreamingResponse::new(chunks=[@utf8.encode(body.stringify())], headers=[
    ("content-type", "application/json"),
    ("x-moonmuse", "provider"),
  ])
}

///|
/// An error in the dialect's own shape.
fn error_response(
  error : @moonmuse.LlmError,
  dialect : &@moonmuse.Dialect,
) -> @http.StreamingResponse {
  let (status, body) = @moonmuse.Dialect::error(dialect, error)
  @http.StreamingResponse::new(
    status~,
    chunks=[@utf8.encode(body.stringify())],
    headers=[("content-type", "application/json")],
  )
}

///|
/// A streamed answer: one chunk per frame, so a client sees events as they were produced.
fn stream_response(
  dialect : &@moonmuse.Dialect,
  frames : Array[@moonmuse.Frame],
  path : String,
) -> @http.StreamingResponse {
  let chunks = []
  let sse = !path.contains("/api/chat") && !path.contains("/api/generate")
  for frame in frames {
    let text = if sse {
      @moonmuse.encode_sse([frame])
    } else {
      frame.data + "\n"
    }
    chunks.push(@utf8.encode(text))
  }
  let _ = dialect
  @http.StreamingResponse::new(chunks~, headers=[
    (
      "content-type",
      if sse {
        "text/event-stream"
      } else {
        "application/x-ndjson"
      },
    ),
    ("cache-control", "no-cache"),
  ])
}

///|
/// The dialect list a gateway offers when the caller does not say: the two formats every
/// client library speaks.
pub fn default_dialects() -> Array[&@moonmuse.Dialect] {
  [@openai.dialect, @anthropic.dialect]
}

///|
pub extend Limits with Eq::{not_equal, equal}

///|
pub extend Limits with Debug::{to_repr}
