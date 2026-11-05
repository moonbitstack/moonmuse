///|
/// A deterministic in-memory client for tests: it replays a scripted list of
/// assistant replies, one per `execute` call, ignoring the prompt. This is what
/// lets the agent loop be tested without a network or a real model — the loop's
/// control flow is exercised by scripting "reply with a tool call", then "reply
/// with the final text".
pub struct MockClient {
  scripted : Array[@moonmuse.Message]
  mut next : Int32
  provider_id : @models.LLMProvider
}

///|
/// A mock that will hand back `scripted` replies in order.
pub fn MockClient::new(
  scripted : Array[@moonmuse.Message],
  provider~ : @models.LLMProvider = @models.openai,
) -> MockClient {
  { scripted, next: 0, provider_id: provider, }
}

///|
pub impl @moonmuse.LLMClient for MockClient with fn execute(self, prompt~, model~, tools~) {
  let _ = prompt
  let _ = model
  let _ = tools
  let i = self.next
  self.next = self.next + 1
  self.scripted[i]
}

///|
pub impl @moonmuse.LLMClient for MockClient with fn provider(self) {
  self.provider_id
}

///|
pub impl @moonmuse.LLMClient for MockClient with fn moderate(self, prompt~, model~) {
  let _ = self
  let _ = prompt
  let _ = model
  ModerationResult::safe()
}

///|
/// The scripted equivalent of a multi-choice request: hand back the next
/// `prompt.params.number_of_choices` scripted replies, one per candidate, the way a
/// provider returns one completion per requested choice.
pub impl @moonmuse.LLMClient for MockClient with fn execute_multiple(
  self,
  prompt~,
  model~,
  tools~,
) {
  let wanted = match prompt.params.number_of_choices {
    Some(n) => if n > 1 { n } else { 1 }
    None => 1
  }
  let choices = []
  for _ in 0..<wanted {
    choices.push(@moonmuse.LLMClient::execute(self, prompt~, model~, tools~))
  }
  choices
}

///|
pub extend MockClient with @moonmuse.LLMClient::{
  execute,
  provider,
  execute_streaming,
  moderate,
  execute_multiple,
}
