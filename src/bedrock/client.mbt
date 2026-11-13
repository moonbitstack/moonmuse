///|
/// A Bedrock client: the shared vocabulary on one side, Converse on the other, and SigV4 in
/// between. The region is part of the endpoint and part of the signature, so it is part of the
/// client rather than of each call.

///|
/// A connection to one Bedrock region.
pub struct Client {
  region : String
  base : String
  credential : Credential
  headers : Array[(String, String)]
  timeout : Int32
}

///|
/// A client for `region`, signing with `credential`. `base` is for a local endpoint — a test
/// server, a proxy — and defaults to the regional runtime.
pub fn Client::new(
  region~ : String = "us-east-1",
  credential~ : Credential,
  base? : String,
  headers~ : Array[(String, String)] = [],
  timeout~ : Int32 = 180_000,
) -> Client {
  let base = match base {
    Some(text) => text
    None => "https://bedrock-runtime." + region + ".amazonaws.com"
  }
  { region, base, credential, headers, timeout, }
}

///|
/// The host a signature covers: the address without the scheme and without a trailing slash.
fn Client::host(self : Client) -> String {
  let without = if self.base.has_prefix("https://") {
    self.base.exact_view(start=8).to_owned()
  } else if self.base.has_prefix("http://") {
    self.base.exact_view(start=7).to_owned()
  } else {
    self.base
  }
  match without.find("/") {
    Some(at) => without.exact_view(start=0, end=at).to_owned()
    None => without
  }
}

///|
/// One signed call, sent, with the answer read whole.
async fn Client::call(
  self : Client,
  path : String,
  body : Json,
) -> @transport.Response raise @moonmuse.LlmError {
  let payload = @utf8.encode(@json.dumps(body))
  let headers = [("content-type", "application/json"), ..self.headers]
  let signed = sign(
    self.credential,
    region=self.region,
    service="bedrock",
    verb="POST",
    host=self.host(),
    path~,
    query="",
    headers~,
    body_hash=payload_hash(payload[:]),
    seconds=@async.now() / 1000L,
  )
  let call = @moonmuse.Call::bytes("POST", path, "application/json", payload)
  let call = { ..call, headers: signed.headers, }
  @transport.send(call, base=self.base, timeout=self.timeout)
}

///|
pub impl @moonmuse.Provider for Client with fn chat(self, request) {
  let response = self.call(
    "/model/" + request.model + "/converse",
    converse_body(request),
  )
  if response.status >= 400 {
    raise @moonmuse.Status(
      code=response.status,
      body=response.body,
      retry_after=response.retry_after(),
    )
  }
  converse_reply(response.json())
}

///|
/// A streamed answer. Converse streams in `vnd.amazon.eventstream` frames, not in server-sent
/// events, so the deltas are read here rather than through a dialect. The closing `metadata`
/// event carries the usage and arrives after `messageStop`, which is why the reply is
/// assembled at the end of the stream instead of at the stop event.
pub impl @moonmuse.Provider for Client with fn stream(self, request, on_delta) {
  let payload = @utf8.encode(@json.dumps(converse_body(request)))
  let headers = [
    ("content-type", "application/json"),
    ("accept", "application/vnd.amazon.eventstream"),
    ..self.headers,
  ]
  let signed = sign(
    self.credential,
    region=self.region,
    service="bedrock",
    verb="POST",
    host=self.host(),
    path="/model/" + request.model + "/converse-stream",
    query="",
    headers~,
    body_hash=payload_hash(payload[:]),
    seconds=@async.now() / 1000L,
  )
  let call = @moonmuse.Call::bytes(
    "POST",
    "/model/" + request.model + "/converse-stream",
    "application/json",
    payload,
  )
  let call = { ..call, headers: signed.headers, }
  let answer = @transport.open(call, base=self.base, timeout=self.timeout)
  answer.ensure_success()
  defer answer.close()
  let reader = Reader::new()
  // (id, name, arguments so far) per tool call, in the order they started.
  let calls : Array[(String, String, String)] = []
  let mut text = ""
  let mut finish = @moonmuse.Stop
  let mut usage = @moonmuse.Usage::zero()
  let mut ended = false
  while !ended {
    match answer.next_bytes() {
      None => ended = true
      Some(piece) =>
        for frame in reader.push(piece) {
          let event = frame.event()
          let payload = event.payload
          match event.kind {
            "contentBlockDelta" => {
              let delta = @moonmuse.json_field(payload, "delta").unwrap_or(
                Json::null(),
              )
              match @moonmuse.json_string(delta, "text") {
                Some(chunk) =>
                  if chunk != "" {
                    text = text + chunk
                    on_delta(@moonmuse.Delta::Text(chunk))
                  }
                None => ()
              }
              if !calls.is_empty() {
                match @moonmuse.json_object(delta, "toolUse") {
                  Some(fields) =>
                    match @moonmuse.json_string(Json::object(fields), "input") {
                      Some(chunk) =>
                        if chunk != "" {
                          let index = calls.length() - 1
                          let (id, name, so_far) = calls[index]
                          calls[index] = (id, name, so_far + chunk)
                          on_delta(@moonmuse.Delta::CallArgs(id~, chunk~))
                        }
                      None => ()
                    }
                  None => ()
                }
              }
            }
            "contentBlockStart" =>
              match @moonmuse.json_object(payload, "start") {
                Some(fields) =>
                  match @moonmuse.json_object(Json::object(fields), "toolUse") {
                    Some(found) => {
                      let spec = Json::object(found)
                      let id = @moonmuse.json_string_or(spec, "toolUseId", "")
                      let name = @moonmuse.json_string_or(spec, "name", "")
                      calls.push((id, name, ""))
                      on_delta(@moonmuse.Delta::CallStart(id~, name~))
                    }
                    None => ()
                  }
                None => ()
              }
            "messageStop" =>
              finish = @moonmuse.Finish::of(
                @moonmuse.json_string_or(payload, "stopReason", ""),
              )
            "metadata" =>
              match @moonmuse.json_field(payload, "usage") {
                Some(value) => usage = usage_of(value)
                None => ()
              }
            _ => ()
          }
        }
    }
  }
  let parts = []
  if text != "" {
    parts.push(@moonmuse.Part::text(text))
  }
  for call in calls {
    let (id, name, args) = call
    parts.push(@moonmuse.Part::call(id, name, @moonmuse.parse_json_lossy(args)))
  }
  let reply = @moonmuse.Reply::new(
    @moonmuse.Message::new(@moonmuse.Assistant, parts),
    finish~,
    usage~,
  )
  on_delta(@moonmuse.Delta::Done(reply))
  reply
}

///|
/// Bedrock has no endpoint that returns vectors for a model in the shared shape: each
/// embedding model takes its own body and answers in its own. The call that carries one is
/// `InvokeModel`, which is a model-specific body, so this refuses rather than guessing.
pub impl @moonmuse.Provider for Client with fn embed(self, _model, _inputs) {
  let _ = self
  raise @moonmuse.Unsupported(
    "Bedrock embeddings are one body per model; use InvokeModel with that model's shape",
  )
}

///|
/// The model list lives on the control-plane service, which is a different host, a different
/// signature scope and a different API. This client speaks only the runtime.
pub impl @moonmuse.Provider for Client with fn models(self) {
  let _ = self
  raise @moonmuse.Unsupported(
    "the model list is a control-plane call on a different endpoint",
  )
}

///|
pub extend Client with @moonmuse.Provider::{chat, stream, embed, models}
