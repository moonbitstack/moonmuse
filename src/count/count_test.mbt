///|
/// A vocabulary of the 256 single bytes, which is the floor a byte-level encoding needs.
/// Every byte is one token, so a test can state an exact count without shipping a table:
/// this is a tokenizer that is wrong about any real model and right about arithmetic.
fn single_bytes() -> @vocab.Ranks raise @refused.Refused {
  let pairs = []
  for byte = 0; byte < 256; byte = byte + 1 {
    pairs.push((Bytes::make(1, byte.to_byte()), byte))
  }
  @vocab.Ranks::from_pairs(pairs)
}

///|
/// A counter over that vocabulary: one token per byte, four per message.
fn counter(
  overhead~ : Int32 = 4,
  image~ : Int32 = 0,
) -> @count.Tokens raise @refused.Refused {
  let tokenizer = @moontoken.Tokenizer::cl100k(ranks=single_bytes())
  @count.Tokens::new(tokenizer~, overhead~, image~)
}

///|
test "count: text is counted by the vocabulary" {
  assert_eq(counter().text("hello"), 5)
  assert_eq(counter().text(""), 0)
}

///|
test "count: a request is its text plus the framing" {
  let request = @moonmuse.Request::new("m", [
    @moonmuse.Message::system("be brief"),
    @moonmuse.Message::user("hello"),
  ])
  // Thirteen characters of text and two messages' worth of framing.
  assert_eq(@moonmuse.Counter::count(counter(), request), 21)
  assert_eq(@moonmuse.Counter::count(counter(overhead=0), request), 13)
}

///|
test "count: a tool declaration is part of the request" {
  let with_tool = @moonmuse.Request::new("m", [@moonmuse.Message::user("x")], tools=[
    @moonmuse.Tool::new("add", "add two numbers", schema={
      "type": "object",
      "properties": { "a": { "type": "number" } },
    }),
  ])
  let plain = @moonmuse.Request::new("m", [@moonmuse.Message::user("x")])
  let extra = @moonmuse.Counter::count(counter(), with_tool) -
    @moonmuse.Counter::count(counter(), plain)
  assert_eq(extra > 0, true)
}

///|
test "count: an image is charged the amount the caller named" {
  let request = @moonmuse.Request::new("m", [
    @moonmuse.Message::new(@moonmuse.User, [
      @moonmuse.Part::text("what is this"),
      @moonmuse.Part::Image(url="https://example.com/a.png", media=None),
    ]),
  ])
  assert_eq(@moonmuse.Counter::count(counter(), request), 16)
  assert_eq(@moonmuse.Counter::count(counter(image=85), request), 101)
}
