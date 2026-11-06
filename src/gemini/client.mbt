///|
/// A client for Gemini's generative language API. The credential travels in
/// `x-goog-api-key`, and the model travels in the path.

///|
/// A connection to the Gemini API.
pub struct Client {
  base : String
  key : String?
  headers : Array[(String, String)]
  timeout : Int32
}

///|
/// A client for `base`, authenticating with `api_key`.
pub fn Client::new(
  api_key? : String,
  base~ : String = "https://generativelanguage.googleapis.com/v1beta",
  headers~ : Array[(String, String)] = [],
  timeout~ : Int32 = 60_000,
) -> Client {
  { base, key: api_key, headers, timeout, }
}

///|
/// The headers every call carries.
fn Client::auth(self : Client) -> Array[(String, String)] {
  let headers = [("user-agent", "moonmuse")]
  match self.key {
    Some(key) => headers.push(("x-goog-api-key", key))
    None => ()
  }
  [..headers, ..self.headers]
}

///|
/// Send one call.
async fn Client::send(
  self : Client,
  call : @moonmuse.Call,
) -> @transport.Response raise @moonmuse.LlmError {
  @transport.send(
    call,
    base=self.base,
    headers=self.auth(),
    timeout=self.timeout,
  )
}

///|
pub impl @moonmuse.Provider for Client with fn chat(self, request) {
  let response = self.send(generate_call(request))
  if response.status >= 400 {
    raise @moonmuse.Status(
      code=response.status,
      body=response.body,
      retry_after=response.retry_after(),
    )
  }
  let body = response.json()
  generate_reply(response.status, body)
}

///|
/// A streamed answer, replayed from the whole answer until moonfetch can stream.
pub impl @moonmuse.Provider for Client with fn stream(self, request, on_delta) {
  let reply = @moonmuse.Provider::chat(self, request)
  let text = reply.message.text_content(separator="")
  if text != "" {
    on_delta(@moonmuse.Delta::Text(text))
  }
  for part in reply.message.calls() {
    match part {
      @moonmuse.Part::Call(id~, name~, args~) => {
        on_delta(@moonmuse.Delta::CallStart(id~, name~))
        on_delta(@moonmuse.Delta::CallArgs(id~, chunk=args.stringify()))
      }
      _ => ()
    }
  }
  on_delta(@moonmuse.Delta::Done(reply))
  reply
}

///|
/// Vectors for a batch, through `batchEmbedContents`. One call carries every input, which
/// is what Gemini's batch endpoint is for.
pub impl @moonmuse.Provider for Client with fn embed(self, model, inputs) {
  let requests = []
  for input in inputs {
    requests.push(
      @moonmuse.object_json([
        ("model", Json::string("models/" + model)),
        (
          "content",
          @moonmuse.object_json([("parts", Json::array([text_part(input)]))]),
        ),
      ]),
    )
  }
  let body = @moonmuse.object_json([("requests", Json::array(requests))])
  let response = self.send(
    @moonmuse.Call::new(
      "POST",
      "/models/" + model + ":batchEmbedContents",
      body,
    ),
  )
  if response.status >= 400 {
    raise @moonmuse.Status(
      code=response.status,
      body=response.body,
      retry_after=response.retry_after(),
    )
  }
  let payload = response.json()
  let vectors = []
  for item in @moonmuse.json_array(payload, "embeddings") {
    vectors.push(
      @moonmuse.json_numbers(
        @moonmuse.json_field(item, "values").unwrap_or(Json::null()),
      ),
    )
  }
  @moonmuse.check_vectors(inputs, vectors)
}

///|
pub impl @moonmuse.Provider for Client with fn models(self) {
  let response = self.send(@moonmuse.Call::new("GET", "/models", Json::null()))
  if response.status >= 400 {
    raise @moonmuse.Status(
      code=response.status,
      body=response.body,
      retry_after=response.retry_after(),
    )
  }
  let body = response.json()
  let out = []
  for item in @moonmuse.json_array(body, "models") {
    let name = @moonmuse.json_string_or(item, "name", "")
    let id = if name.has_prefix("models/") {
      name.exact_view(start=7).to_owned()
    } else {
      name
    }
    out.push(
      @moonmuse.ModelInfo::new(id, capabilities=[
        @moonmuse.Chat,
        @moonmuse.Tools,
      ]),
    )
  }
  out
}

///|
pub extend Client with @moonmuse.Provider::{chat, stream, embed, models}
