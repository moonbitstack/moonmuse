// The caching client: a call-counting client proves a repeated prompt is served from cache.

///|
struct CountingClient {
  mut calls : Int32
  reply : String
}

///|
impl @moonmuse.LLMClient for CountingClient with fn execute(
  self,
  prompt~,
  model~,
  tools~,
) {
  let _ = prompt
  let _ = model
  let _ = tools
  self.calls = self.calls + 1
  @moonmuse.Message::assistant(self.reply)
}

///|
impl @moonmuse.LLMClient for CountingClient with fn provider(self) {
  let _ = self
  @models.openai
}

///|
impl @moonmuse.LLMClient for CountingClient with fn moderate(self, prompt~, model~) {
  let _ = self
  let _ = prompt
  let _ = model
  @moonmuse.ModerationResult::safe()
}

///|
impl @moonmuse.LLMClient for CountingClient with fn execute_multiple(
  self,
  prompt~,
  model~,
  tools~,
) {
  [@moonmuse.LLMClient::execute(self, prompt~, model~, tools~)]
}

///|
async test "caching client: a repeated prompt is served from cache; a new prompt calls through" {
  @async.with_task_group(_g => {
    let counter = CountingClient::{ calls: 0, reply: "cached-reply", }
    let client = @moonmuse.CachingClient::new(counter)
    let model = @models.deepseek_v4_flash
    let p1 = @moonmuse.PromptBuilder::new().user("hello").build()
    let r1 = @moonmuse.LLMClient::execute(client, prompt=p1, model~, tools=[])
    let r2 = @moonmuse.LLMClient::execute(client, prompt=p1, model~, tools=[])
    assert_eq(r1.text_content(), "cached-reply")
    assert_eq(r2.text_content(), "cached-reply")
    assert_eq(counter.calls, 1)
    let p2 = @moonmuse.PromptBuilder::new().user("different").build()
    let _ = @moonmuse.LLMClient::execute(client, prompt=p2, model~, tools=[])
    assert_eq(counter.calls, 2)
    assert_eq(client.size(), 2)
  })
}
