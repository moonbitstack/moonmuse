///|
/// A client for OpenAI and every endpoint that speaks its shape. The wire format lives
/// in this package's dialect; this type only adds an address, credentials and a
/// transport, so DeepSeek, Kimi, Qwen, vLLM, OpenRouter, DashScope and Mistral are one
/// constructor line apart.

///|
/// A connection to an OpenAI-compatible endpoint.
pub struct Client {
  base : String
  key : String?
  headers : Array[(String, String)]
  timeout : Int32
}

///|
/// A client for `base`. `api_key` is left out for a local server that wants none;
/// `headers` adds what a gateway needs, from an organisation id to a beta switch.
pub fn Client::new(
  api_key? : String,
  base~ : String = "https://api.openai.com/v1",
  headers~ : Array[(String, String)] = [],
  timeout~ : Int32 = 60_000,
) -> Client {
  { base, key: api_key, headers, timeout, }
}

///|
/// A copy pointed at another endpoint, keeping the credentials — how a caller reaches a
/// second deployment of the same service.
pub fn Client::at(self : Client, base : String) -> Client {
  { ..self, base, }
}

///|
/// The headers this client adds to every call.
fn Client::auth(self : Client) -> Array[(String, String)] {
  let headers = [("user-agent", "moonmuse")]
  match self.key {
    Some(key) => headers.push(("authorization", "Bearer " + key))
    None => ()
  }
  [..headers, ..self.headers]
}

///|
/// The HTTP call for a request, with `stream` set when the caller wants one. A client
/// that cannot stream still sends this flag false and replays the answer as deltas.
fn Client::call(
  _self : Client,
  request : @moonmuse.Request,
  stream~ : Bool,
) -> @moonmuse.Call {
  let call = chat_call(request)
  if stream {
    call.streaming()
  } else {
    call
  }
}

///|
/// Send a call through this client's transport.
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
  let response = self.send(self.call(request, stream=false))
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
/// A streamed answer, forwarded as the endpoint produces it. The same `Turn` the gateway
/// writes with reads the stream here, so the deltas a client sees are the ones the frames
/// carried, not a replay of the finished answer.
pub impl @moonmuse.Provider for Client with fn stream(self, request, on_delta) {
  let answer = @transport.open(
    self.call(request, stream=true),
    base=self.base,
    headers=self.auth(),
    timeout=self.timeout,
  )
  answer.ensure_success()
  @transport.stream_reply(dialect, answer, on_delta~)
}

///|
pub impl @moonmuse.Provider for Client with fn embed(self, model, inputs) {
  let body = @moonmuse.object_json([
    ("model", Json::string(model)),
    ("input", @moonmuse.strings_json(inputs)),
  ])
  let response = self.send(@moonmuse.Call::new("POST", "/embeddings", body))
  if response.status >= 400 {
    raise @moonmuse.Status(
      code=response.status,
      body=response.body,
      retry_after=response.retry_after(),
    )
  }
  let payload = response.json()
  let vectors : Array[Array[Double]] = Array::make(
    inputs.length(),
    ([] : Array[Double]),
  )
  for item in @moonmuse.json_array(payload, "data") {
    let index = @moonmuse.json_int(item, "index").unwrap_or(0)
    let vector = @moonmuse.json_numbers(
      @moonmuse.json_field(item, "embedding").unwrap_or(Json::null()),
    )
    if index >= 0 && index < vectors.length() {
      vectors[index] = vector
    }
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
  let payload = response.json()
  let out = []
  for item in @moonmuse.json_array(payload, "data") {
    out.push(
      @moonmuse.ModelInfo::new(@moonmuse.json_string_or(item, "id", ""), capabilities=[
        @moonmuse.Chat,
      ]),
    )
  }
  out
}

///|
pub extend Client with @moonmuse.Provider::{chat, stream, embed, models}
