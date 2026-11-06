///|
/// The tool loop: what the model asks for runs, its result goes back, and the round count
/// stops a model that keeps asking.

///|
/// An adder, the smallest tool that can be checked.
fn adder() -> @toolbox.Toolbox {
  let box = @toolbox.Toolbox::new()
  box.add(@moonmuse.Tool::new("add", "add two numbers"), args => {
    let a = @moonmuse.json_int(args, "a").unwrap_or(0)
    let b = @moonmuse.json_int(args, "b").unwrap_or(0)
    (a + b).to_string()
  })
  box
}

///|
async test "toolbox: a call runs and returns its result" {
  let box = adder()
  let part = box.call(@moonmuse.Part::call("c1", "add", { "a": 2, "b": 3 }))
  assert_eq(part, @moonmuse.Part::result("c1", "5"))
}

///|
async test "toolbox: an unknown tool is a result, not an exception" {
  let box = adder()
  let part = box.call(@moonmuse.Part::call("c1", "multiply", { "a": 2 }))
  assert_eq(
    part,
    @moonmuse.Part::result("c1", "error: no tool named multiply", error=true),
  )
}

///|
async test "toolbox: a tool that raises becomes an error result" {
  let box = @toolbox.Toolbox::new()
  box.add(@moonmuse.Tool::new("boom", "always fails"), _args => {
    raise @moonmuse.Unsupported("boom")
  })
  let part = box.call(@moonmuse.Part::call("c1", "boom", {}))
  assert_eq(part.text_of().has_prefix("error: "), true)
}

///|
async test "toolbox: run feeds results back and stops on a text reply" {
  let provider = @fake.Fake::new([
    @moonmuse.Reply::new(
      @moonmuse.Message::new(@moonmuse.Assistant, [
        @moonmuse.Part::call("c1", "add", { "a": 2, "b": 3 }),
      ]),
      finish=@moonmuse.Calls,
    ),
    @moonmuse.Reply::new(@moonmuse.Message::assistant("the answer is 5")),
  ])
  let box = adder()
  let reply = @toolbox.run(
    provider,
    @moonmuse.Request::new("m", [@moonmuse.Message::user("2+3?")]),
    box,
  )
  assert_eq(reply.text(), "the answer is 5")
  assert_eq(provider.hits(), 2)
  let second = provider.seen()[1]
  assert_eq(second.messages.length(), 3)
  assert_eq(
    second.messages[1].calls()[0],
    @moonmuse.Part::call("c1", "add", { "a": 2, "b": 3 }),
  )
  assert_eq(second.messages[2].results()[0], @moonmuse.Part::result("c1", "5"))
}

///|
async test "toolbox: the round limit stops a model that always asks" {
  let always = @moonmuse.Reply::new(
    @moonmuse.Message::new(@moonmuse.Assistant, [
      @moonmuse.Part::call("c1", "add", { "a": 1, "b": 1 }),
    ]),
    finish=@moonmuse.Calls,
  )
  let provider = @fake.Fake::new([always])
  let reply = @toolbox.run(
    provider,
    @moonmuse.Request::new("m", [@moonmuse.Message::user("go")]),
    adder(),
    limit=2,
  )
  assert_eq(provider.hits(), 3)
  assert_eq(reply.calls().length(), 1)
}

///|
async test "toolbox: zero rounds means one ask and no tool run" {
  let provider = @fake.Fake::calls("add", { "a": 1, "b": 1 })
  let reply = @toolbox.run(
    provider,
    @moonmuse.Request::new("m", [@moonmuse.Message::user("go")]),
    adder(),
    limit=0,
  )
  assert_eq(provider.hits(), 1)
  assert_eq(reply.calls().length(), 1)
}
