///|
/// The tool loop against a scripted provider: the model asks for a sum, the tool runs, the
/// answer goes back, and the model's second reply closes the turn.
async fn main {
  let provider = @fake.Fake::new([
    @moonmuse.Reply::new(
      @moonmuse.Message::new(@moonmuse.Assistant, [
        @moonmuse.Part::call(
          "c1",
          "add",
          @moonmuse.parse_json_lossy("{\"a\":2,\"b\":40}"),
        ),
      ]),
      finish=@moonmuse.Calls,
    ),
    @moonmuse.Reply::new(@moonmuse.Message::assistant("The sum is 42.")),
  ])
  let tools = @toolbox.Toolbox::new()
  tools.add(@moonmuse.Tool::new("add", "Add two integers"), args => {
    let a = @moonmuse.json_int(args, "a").unwrap_or(0)
    let b = @moonmuse.json_int(args, "b").unwrap_or(0)
    (a + b).to_string()
  })
  let reply = @toolbox.run(
    provider,
    @moonmuse.Request::new("fake", [@moonmuse.Message::user("What is 2 + 40?")]),
    tools,
  )
  println(reply.text())
  println("provider calls: " + provider.hits().to_string())
}
