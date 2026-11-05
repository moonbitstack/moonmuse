///|
/// The prompt/message model on its own: a multi-turn conversation built with the
/// fluent `PromptBuilder`, the four `MessagePart` kinds, and the `ToJson` wire form
/// of a message and of `LLMParams`. No client, no model — just the value types the
/// rest of the library is threaded through.
///
///     moon run examples/02-prompt-model --target native
#coverage.skip
fn main {
  // A four-turn conversation: system, user, assistant, then a tool result fed back.
  let prompt = @moonmuse.PromptBuilder::new(id="conv-233")
    .system("You are qwq, a terse assistant.")
    .user("look up the weather in heke1228")
    .assistant("checking now")
    .tool_result(tool="weather", output="{\"temp_c\": 23}", id="call_233")
    .build()
  println("id \{prompt.id}, \{prompt.messages.length()} messages")
  for m in prompt.messages {
    println(m.to_json().stringify())
  }

  // An assistant reply carrying all the mixed part kinds: a reasoning trace, text,
  // and a tool call. `text_content` sees only the text; `tool_calls` sees only the
  // calls; the reasoning rides alongside as its own `MessagePart`.
  let reply : @moonmuse.Message = {
    role: Assistant,
    parts: [
      Reasoning(["recall the city", "then call the lookup tool"]),
      Text("let me look that up"),
      ToolCall(id=Some("call_66666"), tool="lookup", args={ "q": "hhh" }),
    ],
    finish_reason: Some("tool_calls"),
    meta: None,
  }
  println("reply parts: \{reply.parts.length()}")
  println("reply text: \{reply.text_content()}")
  println("reply tool calls: \{reply.tool_calls().length()}")

  // `append` is non-mutating — it returns a new prompt with the message added.
  let grown = prompt.append(reply)
  println("after append: \{grown.messages.length()} messages")

  // Full `LLMParams`, including a structured-output schema and a forced tool choice,
  // rendered to the JSON a request would carry.
  let params : @moonmuse.LLMParams = {
    ..@moonmuse.LLMParams::default(),
    temperature: Some(0.2),
    max_tokens: Some(23333),
    number_of_choices: Some(3),
    schema: Some(JsonStandard(name="profile", schema={ "type": "object" })),
    tool_choice: Some(Required),
  }
  println(params.to_json().stringify())
}
