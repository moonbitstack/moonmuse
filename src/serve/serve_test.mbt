///|
/// A gateway is judged by what a client SDK gets out of it: the endpoint it called answers in
/// that format, a stream arrives as events, an unauthorized call is refused, and the model
/// list follows the format the caller speaks.

///|
/// A client for an app that exports one scripted provider in both default formats.
fn client(provider : @fake.Fake) -> @testing.Client {
  @testing.Client::new(
    @serve.serve(provider, dialects=@serve.default_dialects()),
  )
}

///|
async test "serve: an OpenAI chat call answers in the OpenAI shape" {
  let provider = @fake.Fake::text("hello")
  let client = client(provider)
  let response = client.post(
    "/v1/chat/completions",
    body=@utf8.encode(
      "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}",
    ),
  )
  assert_eq(response.status, 200)
  let body = response.json()
  let choices = @moonmuse.json_array(body, "choices")
  assert_eq(choices.length(), 1)
  let message = @moonmuse.json_field(choices[0], "message").unwrap_or(
    Json::null(),
  )
  assert_eq(@moonmuse.json_string(message, "content"), Some("hello"))
  assert_eq(@moonmuse.json_string(choices[0], "finish_reason"), Some("stop"))
}

///|
async test "serve: the request reaches the provider intact" {
  let provider = @fake.Fake::text("hello")
  let client = client(provider)
  let _ = client.post(
    "/v1/chat/completions",
    body=@utf8.encode(
      "{\"model\":\"gpt-test\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"temperature\":0.3}",
    ),
  )
  let seen = provider.seen()
  assert_eq(seen.length(), 1)
  assert_eq(seen[0].model, "gpt-test")
  assert_eq(seen[0].temperature, Some(0.3))
}

///|
async test "serve: a streamed call answers with server-sent events" {
  let provider = @fake.Fake::text("streamed")
  let client = client(provider)
  let response = client.post(
    "/v1/chat/completions",
    body=@utf8.encode(
      "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"stream\":true}",
    ),
  )
  assert_eq(response.status, 200)
  assert_eq(response.header("content-type"), Some("text/event-stream"))
  let text = response.text()
  assert_eq(text.contains("data: "), true)
  assert_eq(text.contains("[DONE]"), true)
  let frames = @moonmuse.parse_sse(text)
  assert_eq(frames[frames.length() - 1].data, "[DONE]")
}

///|
async test "serve: an Anthropic client gets a Messages answer" {
  let provider = @fake.Fake::text("bonjour")
  let client = client(provider)
  let response = client.post(
    "/v1/messages",
    body=@utf8.encode(
      "{\"model\":\"claude\",\"max_tokens\":64,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}",
    ),
  )
  assert_eq(response.status, 200)
  let body = response.json()
  assert_eq(@moonmuse.json_string(body, "type"), Some("message"))
  let blocks = @moonmuse.json_array(body, "content")
  assert_eq(@moonmuse.json_string(blocks[0], "text"), Some("bonjour"))
  assert_eq(@moonmuse.json_string(body, "stop_reason"), Some("end_turn"))
}

///|
async test "serve: the model list follows the header" {
  let provider = @fake.Fake::text("x")
  let client = client(provider)
  let openai = client.get("/v1/models")
  assert_eq(@moonmuse.json_string(openai.json(), "object"), Some("list"))
  let anthropic = client.get("/v1/models", headers=[
    ("anthropic-version", "2023-06-01"),
  ])
  let body = anthropic.json()
  assert_eq(@moonmuse.json_field(body, "has_more"), Some(Json::boolean(false)))
}

///|
async test "serve: embeddings are answered with vectors" {
  let provider = @fake.Fake::text("x")
  let client = client(provider)
  let response = client.post(
    "/v1/embeddings",
    body=@utf8.encode("{\"model\":\"e\",\"input\":[\"a\",\"b\"]}"),
  )
  assert_eq(response.status, 200)
  assert_eq(@moonmuse.json_array(response.json(), "data").length(), 2)
}

///|
async test "serve: a missing credential is refused" {
  let provider = @fake.Fake::text("x")
  let keys = @serve.StaticKeys::new(["secret"])
  let app = @serve.serve(provider, dialects=@serve.default_dialects(), keys~)
  let client = @testing.Client::new(app)
  let response = client.post(
    "/v1/chat/completions",
    body=@utf8.encode(
      "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}",
    ),
  )
  assert_eq(response.status, 401)
  assert_eq(provider.hits(), 0)
}

///|
async test "serve: a presented credential is accepted" {
  let provider = @fake.Fake::text("x")
  let app = @serve.serve(
    provider,
    dialects=@serve.default_dialects(),
    keys=@serve.StaticKeys::new(["secret"]),
  )
  let client = @testing.Client::new(app)
  let response = client.post(
    "/v1/chat/completions",
    body=@utf8.encode(
      "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}",
    ),
    headers=[("authorization", "Bearer secret")],
  )
  assert_eq(response.status, 200)
}

///|
async test "serve: an unknown path is a 404 in the format asked for" {
  let provider = @fake.Fake::text("x")
  let client = client(provider)
  let response = client.get("/nope")
  assert_eq(response.status, 404)
}

///|
async test "serve: a malformed body is a 400" {
  let provider = @fake.Fake::text("x")
  let client = client(provider)
  let response = client.post(
    "/v1/chat/completions",
    body=@utf8.encode("not json"),
  )
  assert_eq(response.status, 400)
}

///|
async test "serve: the gateway caps the answer length" {
  let provider = @fake.Fake::text("x")
  let client = client(provider)
  let _ = client.post(
    "/v1/chat/completions",
    body=@utf8.encode(
      "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":99999}",
    ),
  )
  assert_eq(provider.seen()[0].max_tokens, Some(4096))
}
