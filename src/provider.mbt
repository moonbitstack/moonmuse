///|
/// The LLM client contract (Koog `LLMClientAPI`, collapsed for the MVP with the
/// single-LLM `PromptExecutor` — a single-provider executor is a one-line delegate
/// to its client). `execute` sends a prompt with the tool descriptors the model
/// may call and returns the assistant reply; any tool calls come back inside the
/// reply's `parts` as `ToolCall`s. `moderate` checks a prompt against the provider's safety
/// categories; its default reports nothing harmful, and a client that supports moderation
/// overrides it. `execute_multiple` returns one reply per requested choice (Koog
/// `executeMultipleChoices`, the count being `prompt.params.number_of_choices`); a provider
/// without multi-choice returns a single-element list. Streaming is deferred to the async-stream
/// layer.
/// Source: prompt/prompt-executor/prompt-executor-clients/.../LLMClientAPI.kt.
pub(open) trait LLMClient {
  async fn execute(
    Self,
    prompt~ : Prompt,
    model~ : @models.LLModel,
    tools~ : Array[@toolbox.ToolDescriptor],
  ) -> Message
  fn provider(Self) -> @models.LLMProvider
  async fn moderate(Self, prompt~ : Prompt, model~ : @models.LLModel) -> ModerationResult
  async fn execute_multiple(
    Self,
    prompt~ : Prompt,
    model~ : @models.LLModel,
    tools~ : Array[@toolbox.ToolDescriptor],
  ) -> Array[Message]
  /// Stream the assistant reply, invoking `on_chunk` for each incremental text delta as it
  /// arrives, and returning the fully assembled reply (Koog `LLMClient.executeStreaming`). The
  /// default emits the whole reply as a single chunk — a faithful fallback for a client without
  /// native streaming; a provider that streams overrides it to emit real deltas.
  async fn execute_streaming(
    Self,
    prompt~ : Prompt,
    model~ : @models.LLModel,
    tools~ : Array[@toolbox.ToolDescriptor],
    on_chunk~ : (String) -> Unit,
  ) -> Message = _
}

///|
/// The default streaming behaviour: run the non-streaming `execute` and emit its text as one
/// chunk. A client whose provider streams (OpenAI-compatible) overrides this.
impl LLMClient with fn execute_streaming(
  self,
  prompt~,
  model~,
  tools~,
  on_chunk~,
) {
  let reply = self.execute(prompt~, model~, tools~)
  let text = reply.text_content()
  if text != "" {
    on_chunk(text)
  }
  reply
}

