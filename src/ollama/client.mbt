///|
/// A client for a local Ollama server. No credential is needed by default, and the server
/// answers in its own format rather than the OpenAI one.

///|
/// A connection to an Ollama server.
pub struct Client {
  base : String
  headers : Array[(String, String)]
  timeout : Int32
}

///|
/// A client for `base`, which defaults to the port Ollama listens on.
pub fn Client::new(
  base~ : String = "http://127.0.0.1:11434",
  headers~ : Array[(String, String)] = [],
  timeout~ : Int32 = 120_000,
) -> Client {
  { base, headers, timeout, }
}

///|
/// The headers every call carries.
fn Client::auth(self : Client) -> Array[(String, String)] {
  [("user-agent", "moonmuse"), ..self.headers]
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
  let response = self.send(chat_call(request))
  if response.status >= 400 {
    raise @moonmuse.Status(
      code=response.status,
      body=response.body,
      retry_after=response.retry_after(),
    )
  }
  let body = response.json()
  chat_reply(response.status, body)
}

///|
/// A streamed answer, forwarded as the endpoint produces it. Ollama delimits its stream with
/// newlines rather than server-sent events, which is the only difference here.
pub impl @moonmuse.Provider for Client with fn stream(self, request, on_delta) {
  let answer = @transport.open(
    chat_call(request).streaming(),
    base=self.base,
    headers=self.auth(),
    timeout=self.timeout,
  )
  answer.ensure_success()
  @transport.stream_reply(dialect, answer, framing=Lines, on_delta~)
}

///|
pub impl @moonmuse.Provider for Client with fn embed(self, model, inputs) {
  let body = @moonmuse.object_json([
    ("model", Json::string(model)),
    ("input", @moonmuse.strings_json(inputs)),
  ])
  let response = self.send(@moonmuse.Call::new("POST", "/api/embed", body))
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
    vectors.push(@moonmuse.json_numbers(item))
  }
  @moonmuse.check_vectors(inputs, vectors)
}

///|
pub impl @moonmuse.Provider for Client with fn models(self) {
  let response = self.send(
    @moonmuse.Call::new("GET", "/api/tags", Json::null()),
  )
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
    out.push(
      @moonmuse.ModelInfo::new(@moonmuse.json_string_or(item, "name", ""), capabilities=[
        @moonmuse.Chat,
        @moonmuse.Tools,
        @moonmuse.Embedding,
      ]),
    )
  }
  out
}

///|
/// The version a server reports.
pub async fn Client::version(self : Client) -> String raise @moonmuse.LlmError {
  let response = self.send(
    @moonmuse.Call::new("GET", "/api/version", Json::null()),
  )
  if response.status >= 400 {
    raise @moonmuse.Status(
      code=response.status,
      body=response.body,
      retry_after=response.retry_after(),
    )
  }
  let body = response.json()
  @moonmuse.json_string_or(body, "version", "")
}

///|
pub extend Client with @moonmuse.Provider::{chat, stream, embed, models}
