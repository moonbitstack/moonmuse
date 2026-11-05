// A caching LLM client (Koog `prompt-cache` / `CachedPromptExecutor`): remember each
// `execute` reply keyed by the prompt and model, so a repeated identical request is served
// from memory instead of calling the provider again. The other calls delegate straight
// through; moderation and multi-choice are not cached (they are not idempotent reads the way
// a single completion is).

///|
/// A client that caches `execute` replies by prompt + model.
pub struct CachingClient {
  inner : &LLMClient
  cache : Map[String, @moonmuse.Message]
}

///|
/// Wrap `inner` with an in-memory reply cache.
pub fn CachingClient::new(inner : &LLMClient) -> CachingClient {
  { inner, cache: Map([]), }
}

///|
/// The number of distinct prompts currently cached.
pub fn CachingClient::size(self : CachingClient) -> Int32 {
  self.cache.length()
}

///|
/// A cache key that captures the request: the model id followed by each message's role tag
/// and text, so different prompts (or the same prompt to a different model) miss.
fn caching_key(prompt : @moonmuse.Prompt, model : @models.LLModel) -> String {
  let sb = StringBuilder()
  sb.write_string(model.id)
  for m in prompt.messages {
    sb.write_string("\n")
    match m.role {
      System => sb.write_string("s:")
      User => sb.write_string("u:")
      Assistant => sb.write_string("a:")
    }
    for part in m.parts {
      if part is Text(t) {
        sb.write_string(t)
      }
    }
  }
  sb.to_string()
}

///|
pub impl LLMClient for CachingClient with fn execute(
  self,
  prompt~,
  model~,
  tools~,
) {
  let key = caching_key(prompt, model)
  if self.cache.get(key) is Some(cached) {
    return cached
  }
  let reply = LLMClient::execute(self.inner, prompt~, model~, tools~)
  self.cache[key] = reply
  reply
}

///|
pub impl LLMClient for CachingClient with fn provider(self) {
  self.inner.provider()
}

///|
pub impl LLMClient for CachingClient with fn moderate(self, prompt~, model~) {
  LLMClient::moderate(self.inner, prompt~, model~)
}

///|
pub impl LLMClient for CachingClient with fn execute_multiple(
  self,
  prompt~,
  model~,
  tools~,
) {
  LLMClient::execute_multiple(self.inner, prompt~, model~, tools~)
}

///|
pub extend CachingClient with LLMClient::{
  execute,
  provider,
  execute_streaming,
  moderate,
  execute_multiple,
}
