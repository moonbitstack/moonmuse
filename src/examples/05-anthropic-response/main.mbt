///|
fn show_role(r : @moonmuse.Role) -> String {
  match r {
    System => "system"
    User => "user"
    Assistant => "assistant"
  }
}

///|
/// The response half of the Anthropic client, on its own: `from_anthropic_response`
/// maps a Messages API reply — mixed text and `tool_use` blocks — back into a Koog
/// assistant `Message`, the inverse of the request mapping in 01. No network: the
/// body is fixed bytes. The real `AnthropicClient` and `OpenAiCompatibleClient` are
/// then constructed to show they satisfy the `LLMClient` contract and report their
/// provider (their transport rides moonllm and is not exercised here).
///
///     moon run examples/06-anthropic-response --target native
#coverage.skip
fn main {
  let body = @json.parse(
    (
      #|{"id":"msg_233","type":"message","role":"assistant",
      #| "content":[{"type":"text","text":"let me look that up"},
      #|             {"type":"tool_use","id":"tu_1","name":"weather","input":{"city":"heke1228"}}],
      #| "stop_reason":"tool_use"}
    ),
  ) catch {
    e => {
      println("bad body: " + e.to_string())
      return
    }
  }
  let msg = @anthropic.from_anthropic_response(body)
  println("role: " + show_role(msg.role))
  let finish = match msg.finish_reason {
    Some(r) => r
    None => "(none)"
  }
  println("finish_reason: " + finish)
  println("text: " + msg.text_content())
  let calls = msg.tool_calls()
  println("tool calls: \{calls.length()}")
  for part in calls {
    if part is @moonmuse.ToolCall(tool~, args~, ..) {
      println("  -> " + tool + " " + args.stringify())
    }
  }

  // The concrete clients satisfy the agent's LLMClient contract.
  let anthropic : &@moonmuse.LLMClient = @anthropic.AnthropicClient::new(
    api_key="heke1228",
  )
  let deepseek : &@moonmuse.LLMClient = @anthropic.OpenAiCompatibleClient::new(
    api_key="heke1228",
    base_url="https://api.deepseek.com/v1",
    provider=@models.deepseek,
  )
  println("anthropic client provider: " + anthropic.provider().id)
  println("openai-compatible client provider: " + deepseek.provider().id)
}
