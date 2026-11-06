///|
/// A gateway in front of a scripted provider, called the way an OpenAI client would call it.
/// The same app runs under any ASGI server.
async fn main {
  let provider = @fake.Fake::text("Hello from the gateway.")
  let app = @serve.serve(provider, dialects=@serve.default_dialects())
  let client = @testing.Client::new(app)
  let response = client.post(
    "/v1/chat/completions",
    body=@utf8.encode(
      "{\"model\":\"demo\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}",
    ),
  )
  println("status " + response.status.to_string())
  println(response.text())
}
