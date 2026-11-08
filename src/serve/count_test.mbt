///|
/// `count_tokens`, from the counter to the wire: a gateway handed a vocabulary answers with
/// a number, and one without still says that it cannot rather than inventing one.

///|
/// A vocabulary of the 256 single bytes: one token per byte, no merges.
fn vocabulary() -> @vocab.Ranks raise @refused.Refused {
  let pairs = []
  for byte = 0; byte < 256; byte = byte + 1 {
    pairs.push((Bytes::make(1, byte.to_byte()), byte))
  }
  @vocab.Ranks::from_pairs(pairs)
}

///|
/// A counter over it, four tokens of framing per message.
fn counter() -> @count.Tokens raise @refused.Refused {
  let tokenizer = @moontoken.Tokenizer::cl100k(ranks=vocabulary())
  @count.Tokens::new(tokenizer~)
}

///|
async test "serve: count_tokens answers with the counter's number" {
  let app = @serve.serve(
    @fake.Fake::text("x"),
    dialects=[@openai.dialect, @anthropic.dialect],
    counter=counter(),
  )
  let client = @testing.Client::new(app)
  let response = client.post(
    "/v1/messages/count_tokens",
    body=@utf8.encode(
      "{\"model\":\"m\",\"max_tokens\":8,\"messages\":[{\"role\":\"user\",\"content\":\"hello\"}]}",
    ),
  )
  assert_eq(response.status, 200)
  // Five characters and one message's worth of framing.
  assert_eq(@moonmuse.json_int(response.json(), "input_tokens"), Some(9))
}

///|
async test "serve: without a counter the endpoint says what it lacks" {
  let app = @serve.serve(@fake.Fake::text("x"), dialects=[
    @openai.dialect, @anthropic.dialect,
  ])
  let client = @testing.Client::new(app)
  let response = client.post(
    "/v1/messages/count_tokens",
    body=@utf8.encode(
      "{\"model\":\"m\",\"max_tokens\":8,\"messages\":[{\"role\":\"user\",\"content\":\"hello\"}]}",
    ),
  )
  // The format's own shape for a capability the gateway does not have.
  assert_eq(response.status, 404)
  assert_eq(@moonmuse.json_string(response.json(), "type"), Some("error"))
}
