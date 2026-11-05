// The retrying client: a client that fails a scripted number of times with a scripted message
// proves the retry re-runs `execute`, waits between attempts, gives up at `max_attempts`, and
// leaves an error the provider will answer the same way alone.

///|
suberror FlakyError {
  FlakyError(String)
}

///|
/// A caught `Error` says only its own type name, so the retry is told how to read this one.
fn describe_flaky(error : Error) -> String {
  match error {
    FlakyError(message) => message
    _ => @moonmuse.default_describe(error)
  }
}

///|
struct FlakyClient {
  mut calls : Int32
  fail_times : Int32
  message : String
}

///|
fn FlakyClient::new(
  fail_times~ : Int32,
  message~ : String = "503 service temporarily unavailable",
) -> FlakyClient {
  { calls: 0, fail_times, message, }
}

///|
impl @moonmuse.LLMClient for FlakyClient with fn execute(
  self,
  prompt~,
  model~,
  tools~,
) {
  let _ = prompt
  let _ = model
  let _ = tools
  self.calls = self.calls + 1
  if self.calls <= self.fail_times {
    raise FlakyError(self.message)
  }
  @moonmuse.Message::assistant("ok")
}

///|
impl @moonmuse.LLMClient for FlakyClient with fn provider(self) {
  let _ = self
  @models.openai
}

///|
impl @moonmuse.LLMClient for FlakyClient with fn moderate(self, prompt~, model~) {
  let _ = self
  let _ = prompt
  let _ = model
  @moonmuse.ModerationResult::safe()
}

///|
impl @moonmuse.LLMClient for FlakyClient with fn execute_multiple(
  self,
  prompt~,
  model~,
  tools~,
) {
  [@moonmuse.LLMClient::execute(self, prompt~, model~, tools~)]
}

///|
/// A config that waits the default 1s/2s/... but with the jitter switched off, so a test can
/// name the exact delays.
fn steady_config() -> @moonmuse.RetryConfig {
  { ..@moonmuse.RetryConfig::default(), jitter_factor: 0.0, }
}

///|
async test "retrying client: retries a transient failure and eventually succeeds" {
  @async.with_task_group(_g => {
    let flaky = FlakyClient::new(fail_times=2)
    let client = @moonmuse.RetryingClient::new(
      flaky,
      describe=describe_flaky,
      config=steady_config(),
      wait=_ms => (),
    )
    let prompt = @moonmuse.PromptBuilder::new().user("hi").build()
    let reply = @moonmuse.LLMClient::execute(
      client,
      prompt~,
      model=@models.deepseek_v4_flash,
      tools=[],
    )
    assert_eq(reply.text_content(), "ok")
    assert_eq(flaky.calls, 3)
  })
}

///|
async test "retrying client: gives up after max_attempts" {
  @async.with_task_group(_g => {
    let flaky = FlakyClient::new(fail_times=5)
    let client = @moonmuse.RetryingClient::new(
      flaky,
      describe=describe_flaky,
      config={ ..steady_config(), max_attempts: 2, },
      wait=_ms => (),
    )
    let prompt = @moonmuse.PromptBuilder::new().user("hi").build()
    let failed = try {
      let _ = @moonmuse.LLMClient::execute(
        client,
        prompt~,
        model=@models.deepseek_v4_flash,
        tools=[],
      )
      false
    } catch {
      _ => true
    }
    assert_eq(failed, true)
    assert_eq(flaky.calls, 2)
  })
}

///|
async test "retrying client: a retryable failure backs off exponentially" {
  @async.with_task_group(_g => {
    // The clock is injected: the test observes the waits instead of living through them.
    let waits = []
    let flaky = FlakyClient::new(fail_times=2)
    let client = @moonmuse.RetryingClient::new(
      flaky,
      describe=describe_flaky,
      config=steady_config(),
      wait=ms => waits.push(ms),
    )
    let prompt = @moonmuse.PromptBuilder::new().user("hi").build()
    let reply = @moonmuse.LLMClient::execute(
      client,
      prompt~,
      model=@models.deepseek_v4_flash,
      tools=[],
    )
    assert_eq(reply.text_content(), "ok")
    assert_eq(waits, [1000, 2000])
  })
}

///|
async test "retrying client: the backoff is capped at max_delay_ms" {
  @async.with_task_group(_g => {
    let waits = []
    let flaky = FlakyClient::new(fail_times=9)
    let client = @moonmuse.RetryingClient::new(
      flaky,
      describe=describe_flaky,
      config={
        ..steady_config(),
        max_attempts: 6,
        initial_delay_ms: 1000,
        max_delay_ms: 4000,
      },
      wait=ms => waits.push(ms),
    )
    let prompt = @moonmuse.PromptBuilder::new().user("hi").build()
    (@moonmuse.LLMClient::execute(client, prompt~, model=@models.deepseek_v4_flash, tools=[])
    |> ignore) catch {
      _ => ()
    }
    assert_eq(waits, [1000, 2000, 4000, 4000, 4000])
  })
}

///|
async test "retrying client: a non-retryable failure is not retried" {
  @async.with_task_group(_g => {
    let waits = []
    let flaky = FlakyClient::new(fail_times=9, message="400 invalid request")
    let client = @moonmuse.RetryingClient::new(
      flaky,
      describe=describe_flaky,
      config=steady_config(),
      wait=ms => waits.push(ms),
    )
    let prompt = @moonmuse.PromptBuilder::new().user("hi").build()
    let failed = try {
      let _ = @moonmuse.LLMClient::execute(
        client,
        prompt~,
        model=@models.deepseek_v4_flash,
        tools=[],
      )
      false
    } catch {
      _ => true
    }
    assert_eq(failed, true)
    // One attempt, and no wait: the provider would answer a 400 the same way every time.
    assert_eq(flaky.calls, 1)
    assert_eq(waits, [])
  })
}

///|
async test "retrying client: an explicit predicate overrides the pattern list" {
  @async.with_task_group(_g => {
    let flaky = FlakyClient::new(fail_times=1, message="400 invalid request")
    let client = @moonmuse.RetryingClient::new(
      flaky,
      describe=describe_flaky,
      config=steady_config(),
      retryable=_e => true,
      wait=_ms => (),
    )
    let prompt = @moonmuse.PromptBuilder::new().user("hi").build()
    let reply = @moonmuse.LLMClient::execute(
      client,
      prompt~,
      model=@models.deepseek_v4_flash,
      tools=[],
    )
    assert_eq(reply.text_content(), "ok")
    assert_eq(flaky.calls, 2)
  })
}

///|
test "retry config: which errors the default patterns claim" {
  let config = @moonmuse.RetryConfig::default()
  assert_eq(
    config.matches(describe_flaky(FlakyError("429 Too Many Requests"))),
    true,
  )
  assert_eq(config.matches(describe_flaky(FlakyError("503 unavailable"))), true)
  assert_eq(
    config.matches(describe_flaky(FlakyError("Read TIMEOUT after 30s"))),
    true,
  )
  assert_eq(
    config.matches(describe_flaky(FlakyError("connection reset by peer"))),
    true,
  )
  assert_eq(
    config.matches(describe_flaky(FlakyError("400 invalid request"))),
    false,
  )
  assert_eq(
    config.matches(describe_flaky(FlakyError("401 unauthorized"))),
    false,
  )
  assert_eq(
    config.matches(describe_flaky(FlakyError("context length exceeded"))),
    false,
  )
  // The disabled config claims nothing.
  assert_eq(
    @moonmuse.RetryConfig::disabled().matches(describe_flaky(FlakyError("503"))),
    false,
  )
}

///|
test "retry config: the nominal delay doubles up to its ceiling" {
  let config = @moonmuse.RetryConfig::default()
  assert_eq(config.delay_ms(1), 1000)
  assert_eq(config.delay_ms(2), 2000)
  assert_eq(config.delay_ms(3), 4000)
  assert_eq(config.delay_ms(20), 30000)
}

///|
async test "retrying client: jitter keeps each wait within a tenth of nominal" {
  @async.with_task_group(_g => {
    let waits = []
    let flaky = FlakyClient::new(fail_times=9)
    let client = @moonmuse.RetryingClient::new(
      flaky,
      describe=describe_flaky,
      config={ ..@moonmuse.RetryConfig::default(), max_attempts: 4, },
      wait=ms => waits.push(ms),
    )
    let prompt = @moonmuse.PromptBuilder::new().user("hi").build()
    (@moonmuse.LLMClient::execute(client, prompt~, model=@models.deepseek_v4_flash, tools=[])
    |> ignore) catch {
      _ => ()
    }
    assert_eq(waits.length(), 3)
    assert_eq(waits[0] >= 900 && waits[0] <= 1100, true)
    assert_eq(waits[1] >= 1800 && waits[1] <= 2200, true)
    assert_eq(waits[2] >= 3600 && waits[2] <= 4400, true)
    // Jitter means the waits are not all exactly nominal.
    assert_eq(waits == [1000, 2000, 4000], false)
  })
}
