///|
fn model_for(p : @models.LLMProvider) -> @models.LLModel {
  {
    provider: p,
    id: "test-model",
    capabilities: [],
    context_length: None,
    max_output_tokens: None,
  }
}

///|
fn one_prompt() -> @moonmuse.Prompt {
  @moonmuse.PromptBuilder::new().user("hi").build()
}

///|
/// A client that counts how many times it is actually called through.
struct Counting {
  mut calls : Int32
}

///|
impl @moonmuse.LLMClient for Counting with fn execute(
  self,
  prompt~,
  model~,
  tools~,
) {
  let _ = prompt
  let _ = model
  let _ = tools
  self.calls = self.calls + 1
  @moonmuse.Message::assistant("computed-233")
}

///|
impl @moonmuse.LLMClient for Counting with fn provider(_self) {
  @models.openai
}

///|
impl @moonmuse.LLMClient for Counting with fn moderate(_self, prompt~, model~) {
  let _ = prompt
  let _ = model
  @moonmuse.ModerationResult::safe()
}

///|
impl @moonmuse.LLMClient for Counting with fn execute_multiple(
  self,
  prompt~,
  model~,
  tools~,
) {
  [@moonmuse.LLMClient::execute(self, prompt~, model~, tools~)]
}

///|
suberror Transient {
  Transient(String)
}

///|
/// A caught `Error` says only its own type name, so the retry is told how to read this one.
fn describe_transient(error : Error) -> String {
  match error {
    Transient(message) => message
    _ => @moonmuse.default_describe(error)
  }
}

///|
/// A client that fails its first `fail_times` calls with `message`, then succeeds.
struct Flaky {
  mut calls : Int32
  fail_times : Int32
  message : String
}

///|
impl @moonmuse.LLMClient for Flaky with fn execute(self, prompt~, model~, tools~) {
  let _ = prompt
  let _ = model
  let _ = tools
  self.calls = self.calls + 1
  if self.calls <= self.fail_times {
    raise Transient(self.message)
  }
  @moonmuse.Message::assistant("ok after retries")
}

///|
impl @moonmuse.LLMClient for Flaky with fn provider(_self) {
  @models.openai
}

///|
impl @moonmuse.LLMClient for Flaky with fn moderate(_self, prompt~, model~) {
  let _ = prompt
  let _ = model
  @moonmuse.ModerationResult::safe()
}

///|
impl @moonmuse.LLMClient for Flaky with fn execute_multiple(
  self,
  prompt~,
  model~,
  tools~,
) {
  [@moonmuse.LLMClient::execute(self, prompt~, model~, tools~)]
}

///|
/// The client wrappers over the `LLMClient` contract: `CachingClient` serves a
/// repeated prompt from memory, `RetryingClient` re-runs a transient failure,
/// `MultiLLMClient` routes each request to its provider's client (or a fallback),
/// and the default `execute_streaming` emits any reply as a single chunk so every
/// client supports the streaming API. Deterministic scripted clients throughout.
///
///     moon run examples/11-client-wrappers --target native
#coverage.skip
async fn main {
  @async.with_task_group(_g => {
    let model = @models.deepseek_v4_flash

    // Caching: the second identical prompt does not reach the inner client.
    let counter = Counting::{ calls: 0, }
    let cached = @moonmuse.CachingClient::new(counter)
    let p = one_prompt()
    let _ = @moonmuse.LLMClient::execute(cached, prompt=p, model~, tools=[])
    let _ = @moonmuse.LLMClient::execute(cached, prompt=p, model~, tools=[])
    println(
      "caching: inner calls=\{counter.calls}, cache size=\{cached.size()}",
    )

    // Retry: two 503s, then success — each retry waited for, growing 1s -> 2s.
    let waits = []
    let flaky = Flaky::{
      calls: 0,
      fail_times: 2,
      message: "503 service temporarily unavailable",
    }
    let retrying = @moonmuse.RetryingClient::new(
      flaky,
      describe=describe_transient,
      config={ ..@moonmuse.RetryConfig::default(), jitter_factor: 0.0, },
      wait=ms => waits.push(ms),
    )
    let reply = @moonmuse.LLMClient::execute(
      retrying,
      prompt=one_prompt(),
      model~,
      tools=[],
    ) catch {
      e => @moonmuse.Message::assistant("gave up: " + e.to_string())
    }
    println(
      "retry: attempts=\{flaky.calls}, backoff=" +
      waits.map(ms => ms.to_string()).join("+") +
      ", reply=" +
      reply.text_content(),
    )

    // A 400 is the client's fault, not the provider's: asked again it fails the same way,
    // so it is not retried at all.
    let refused = Flaky::{
      calls: 0,
      fail_times: 9,
      message: "400 invalid request",
    }
    let strict = @moonmuse.RetryingClient::new(
      refused,
      describe=describe_transient,
      wait=_ms => (),
    )
    let _ = @moonmuse.LLMClient::execute(strict, prompt=one_prompt(), model~, tools=[]) catch {
      e => @moonmuse.Message::assistant(e.to_string())
    }
    println("retry: a 400 took \{refused.calls} attempt(s)")

    // Routing: each provider's model reaches its registered client; else the fallback.
    let multi = @moonmuse.MultiLLMClient::new()
      .register(
        @models.openai,
        @moonmuse.MockClient::new([@moonmuse.Message::assistant("from openai")]),
      )
      .register(
        @models.anthropic,
        @moonmuse.MockClient::new([@moonmuse.Message::assistant("from anthropic")]),
      )
      .with_fallback(
        @moonmuse.MockClient::new([@moonmuse.Message::assistant("from fallback")]),
      )
    let r_o = multi.execute(prompt=one_prompt(), model=model_for(@models.openai), tools=[])
    let r_a = multi.execute(
      prompt=one_prompt(),
      model=model_for(@models.anthropic),
      tools=[],
    )
    let r_g = multi.execute(prompt=one_prompt(), model=model_for(@models.google), tools=[])
    println(
      "routing: openai=" +
      r_o.text_content() +
      ", anthropic=" +
      r_a.text_content() +
      ", google->" +
      r_g.text_content(),
    )

    // Streaming: the default emits the whole reply as one chunk.
    let stream_src = @moonmuse.MockClient::new([
      @moonmuse.Message::assistant("streamed body"),
    ])
    let chunks : Array[String] = []
    let whole = @moonmuse.LLMClient::execute_streaming(
      stream_src,
      prompt=one_prompt(),
      model~,
      tools=[],
      on_chunk=c => chunks.push(c),
    )
    println(
      "streaming: chunks=\{chunks.length()}, joined=" +
      chunks.join("|") +
      ", final=" +
      whole.text_content(),
    )
  })
}
