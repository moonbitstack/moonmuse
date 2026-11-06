///|
/// A client for Anthropic's Messages API. Two headers carry the protocol: `x-api-key` for
/// the credential and `anthropic-version` for the shape of the messages.

///|
/// A connection to the Messages API.
pub struct Client {
  base : String
  key : String?
  version : String
  headers : Array[(String, String)]
  timeout : Int32
}

///|
/// A client for `base`, authenticating with `api_key`. `version` is the API version the
/// endpoint expects; the default is the one this dialect implements.
pub fn Client::new(
  api_key? : String,
  base~ : String = "https://api.anthropic.com/v1",
  version~ : String = version,
  headers~ : Array[(String, String)] = [],
  timeout~ : Int32 = 60_000,
) -> Client {
  { base, key: api_key, version, headers, timeout, }
}

///|
/// The headers every call carries.
fn Client::auth(self : Client) -> Array[(String, String)] {
  let headers = [
    ("user-agent", "moonmuse"),
    ("anthropic-version", self.version),
  ]
  match self.key {
    Some(key) => headers.push(("x-api-key", key))
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
  let response = self.send(message_call(request))
  if response.status >= 400 {
    raise @moonmuse.Status(
      code=response.status,
      body=response.body,
      retry_after=response.retry_after(),
    )
  }
  let body = response.json()
  message_reply(response.status, body)
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
/// The Messages API has no embeddings endpoint.
pub impl @moonmuse.Provider for Client with fn embed(self, _model, _inputs) {
  let _ = self
  raise @moonmuse.Unsupported("Anthropic serves no embeddings")
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
  for item in @moonmuse.json_array(body, "data") {
    out.push(
      @moonmuse.ModelInfo::new(@moonmuse.json_string_or(item, "id", ""), capabilities=[
        @moonmuse.Chat,
        @moonmuse.Tools,
      ]),
    )
  }
  out
}

///|
/// Count the tokens a request would cost, without asking the model to answer it.
pub async fn Client::count_tokens(
  self : Client,
  request : @moonmuse.Request,
) -> Int32 raise @moonmuse.LlmError {
  let call = message_call(request)
  let count = { ..call, path: "/messages/count_tokens", }
  let response = self.send(count)
  if response.status >= 400 {
    raise @moonmuse.Status(
      code=response.status,
      body=response.body,
      retry_after=response.retry_after(),
    )
  }
  let body = response.json()
  @moonmuse.json_int(body, "input_tokens").unwrap_or(0)
}

///|
pub extend Client with @moonmuse.Provider::{chat, stream, embed, models}
