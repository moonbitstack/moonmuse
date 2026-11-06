///|
/// A request, its wire form, and a reply read back. Nothing here touches a network: the
/// dialect is a pure function of the request, which is what makes it testable.
fn main raise {
  let request = @moonmuse.Request::new(
    "gpt-4o-mini",
    [
      @moonmuse.Message::system("Answer in one sentence."),
      @moonmuse.Message::user("Why is the sky blue?"),
    ],
    temperature=0.2,
    max_tokens=128,
  )
  let call = @openai.chat_call(request)
  println(call.verb + " " + call.path)
  println(call.body.stringify(indent=2))

  let recorded = @moonmuse.parse_json_lossy(
    "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"Sunlight scatters off air molecules, and blue scatters most.\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":18,\"completion_tokens\":14}}",
  )
  let reply = @openai.chat_reply(200, recorded)
  println("reply: " + reply.text())
  println("tokens: " + reply.usage.total().unwrap_or(0).to_string())
}
