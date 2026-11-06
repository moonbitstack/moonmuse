///|
/// Structured output is a repair loop, so the tests are about what happens to a reply that
/// does not fit: it is sent back with the reason, and the budget is finite.

///|
fn schema() -> Json {
  @moonmuse.parse_json_lossy(
    "{\"type\":\"object\",\"properties\":{\"answer\":{\"type\":\"integer\"}},\"required\":[\"answer\"],\"additionalProperties\":false}",
  )
}

///|
/// Decode the one field the schema names.
fn decode(json : Json) -> Int32? {
  @moonmuse.json_int(json, "answer")
}

///|
test "extract: a bare object is found" {
  assert_eq(@structured.extract_object("{\"a\":1}"), Some("{\"a\":1}"))
}

///|
test "extract: an object inside prose and a fence is found" {
  assert_eq(
    @structured.extract_object(
      "Here you go:/n```json\n{\"a\":{\"b\":2}}\n```\nthanks",
    ),
    Some("{\"a\":{\"b\":2}}"),
  )
}

///|
test "extract: a brace inside a string does not end the object" {
  assert_eq(@structured.extract_object("{\"a\":\"}\"}"), Some("{\"a\":\"}\"}"))
}

///|
test "extract: no object is None" {
  assert_eq(@structured.extract_object("no json here"), None)
}

///|
async test "ask: a valid first reply is returned" {
  let provider = @fake.Fake::text("{\"answer\":42}")
  let value = @structured.ask(
    provider,
    @moonmuse.Request::new("m", [@moonmuse.Message::user("the answer?")]),
    name="answer",
    schema=schema(),
    decode~,
  )
  assert_eq(value, 42)
  assert_eq(provider.hits(), 1)
}

///|
async test "ask: a malformed reply is repaired on the next ask" {
  let provider = @fake.Fake::new([
    @moonmuse.Reply::new(
      @moonmuse.Message::assistant("the answer is forty-two"),
    ),
    @moonmuse.Reply::new(@moonmuse.Message::assistant("{\"answer\":42}")),
  ])
  let value = @structured.ask(
    provider,
    @moonmuse.Request::new("m", [@moonmuse.Message::user("the answer?")]),
    name="answer",
    schema=schema(),
    decode~,
  )
  assert_eq(value, 42)
  assert_eq(provider.hits(), 2)
  let repair = provider.seen()[1].messages
  assert_eq(
    repair[repair.length() - 1].text_content().contains("rejected"),
    true,
  )
}

///|
async test "ask: a schema violation names the field" {
  let provider = @fake.Fake::new([
    @moonmuse.Reply::new(
      @moonmuse.Message::assistant("{\"answer\":\"forty-two\"}"),
    ),
    @moonmuse.Reply::new(@moonmuse.Message::assistant("{\"answer\":42}")),
  ])
  let value = @structured.ask(
    provider,
    @moonmuse.Request::new("m", [@moonmuse.Message::user("the answer?")]),
    name="answer",
    schema=schema(),
    decode~,
  )
  assert_eq(value, 42)
  assert_eq(provider.hits(), 2)
}

///|
async test "ask: the repair budget is finite and the failure is explained" {
  let provider = @fake.Fake::text("never json")
  let failed = try {
    let _ = @structured.ask(
      provider,
      @moonmuse.Request::new("m", [@moonmuse.Message::user("the answer?")]),
      name="answer",
      schema=schema(),
      decode~,
      fixes=1,
    )
    false
  } catch {
    @moonmuse.Decode(message) => message.contains("2 attempts")
    _ => false
  }
  assert_eq(failed, true)
  assert_eq(provider.hits(), 2)
}
