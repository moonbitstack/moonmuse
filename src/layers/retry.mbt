// A retrying LLM client (Koog `RetryingLLMClient` + `RetryConfig`): wrap a client and re-run a
// failed `execute`, but only for errors worth re-running and only after waiting. A provider that
// answers 400 gets one request, not three; a provider that answers 503 gets exponential backoff
// with jitter, so a fleet of agents does not come back in lockstep. The other calls delegate
// straight through; `execute_streaming` inherits the retry through the default, which drives
// `execute`.
//
// Koog reads the message off the exception it caught. MoonBit cannot: an `Error` erases its
// payload, and `Error::to_string` on a caught suberror yields only the constructor's qualified
// name — `moonbitstack/moonkoog/client.LLMError.ApiError`, never the status code inside it. So the
// message a pattern is matched against comes from a `describe` seam the caller owns, and a
// client package ships the describer for the errors it raises (`@client.describe_llm_error`).

///|
/// What marks an error as worth retrying (Koog `RetryablePattern`): a substring of the error's
/// described message, matched case-insensitively, or an HTTP status code appearing in it.
pub(all) enum RetryPattern {
  Substring(String)
  Status(Int32)
} derive(Eq, Debug)

///|
/// Whether `message` matches this pattern.
pub fn RetryPattern::matches(self : RetryPattern, message : String) -> Bool {
  match self {
    Substring(needle) => message.to_lower().contains(needle.to_lower().view())
    Status(code) => message.contains(code.to_string().view())
  }
}

///|
/// How a retry is paced (Koog `RetryConfig`): how many attempts in total, the wait before the
/// first retry, the ceiling that wait grows to, the factor it grows by, and how far the wait is
/// randomly spread either side of its nominal value to keep concurrent clients from retrying in
/// lockstep. `patterns` is what makes an error retryable at all.
pub(all) struct RetryConfig {
  max_attempts : Int32
  initial_delay_ms : Int32
  max_delay_ms : Int32
  backoff_multiplier : Double
  jitter_factor : Double
  patterns : Array[RetryPattern]
}

///|
/// Koog's `RetryConfig.DEFAULT`: three attempts, 1s growing by 2× to a 30s ceiling, 10% jitter,
/// retrying the transient provider failures — rate limits, 5xx, timeouts, dropped connections.
pub fn RetryConfig::default() -> RetryConfig {
  {
    max_attempts: 3,
    initial_delay_ms: 1000,
    max_delay_ms: 30000,
    backoff_multiplier: 2.0,
    jitter_factor: 0.1,
    patterns: [
      Status(429),
      Status(500),
      Status(502),
      Status(503),
      Status(504),
      Substring("rate limit"),
      Substring("timeout"),
      Substring("timed out"),
      Substring("connection reset"),
      Substring("connection refused"),
      Substring("temporarily unavailable"),
      Substring("overloaded"),
    ],
  }
}

///|
/// Koog's `RetryConfig.DISABLED`: one attempt, so nothing is ever retried.
pub fn RetryConfig::disabled() -> RetryConfig {
  { ..RetryConfig::default(), max_attempts: 1, patterns: [], }
}

///|
/// Whether any configured pattern claims `message`.
pub fn RetryConfig::matches(self : RetryConfig, message : String) -> Bool {
  for pattern in self.patterns {
    if pattern.matches(message) {
      return true
    }
  }
  false
}

///|
/// The nominal wait before retry number `attempt` (1 for the first retry): the initial delay
/// grown by `backoff_multiplier` once per earlier retry, capped at `max_delay_ms`. Jitter is
/// applied on top of this by the client, which owns the randomness.
pub fn RetryConfig::delay_ms(self : RetryConfig, attempt : Int32) -> Int32 {
  // The growth and the ceiling are moonpool's; the symmetric jitter on top is Koog's own
  // and stays with the client, which is not one of the strategies moonpool names.
  let retry = if attempt < 1 { 1 } else { attempt }
  let schedule = @moonpool.Backoff::new(
    base=@moondate.Span::new(millis=self.initial_delay_ms.to_int64()),
    factor=self.backoff_multiplier,
    cap=@moondate.Span::new(millis=self.max_delay_ms.to_int64()),
    jitter=Rigid,
  )
  (schedule.ceiling(retry).nanos / 1_000_000L).to_int()
}

///|
/// What a bare `Error` says about itself: its constructor's qualified name, and nothing of the
/// payload. The fallback describer, and the reason a caller wants to replace it.
pub fn default_describe(error : Error) -> String {
  error.to_string()
}

///|
/// A client that retries `execute` on a retryable failure, backing off between attempts.
pub struct RetryingClient {
  inner : &LLMClient
  config : RetryConfig
  retryable : (Error) -> Bool
  // The wait, injectable so a test can observe the backoff without living through it.
  wait : async (Int32) -> Unit
  rand : @random.Rand
}

///|
/// Wrap `inner`. `config` paces the retries and holds the patterns; `describe` turns a caught
/// error into the message those patterns are matched against — the default sees only the error's
/// type name, so pass the describer for the client's own error type (`@client.describe_llm_error`
/// for the OpenAI-compatible and Anthropic clients) or nothing will look retryable. `retryable`
/// replaces that classification outright. `wait` is the sleep — the default is real time, a test
/// passes a recorder. `seed` seeds the jitter: MoonBit has no ambient entropy, so without one
/// every client jitters the same sequence.
pub fn RetryingClient::new(
  inner : &LLMClient,
  config~ : RetryConfig = RetryConfig::default(),
  describe~ : (Error) -> String = default_describe,
  retryable? : (Error) -> Bool,
  wait~ : async (Int32) -> Unit = @async.sleep,
  seed? : Bytes,
) -> RetryingClient {
  let retryable = match retryable {
    Some(classify) => classify
    None => e => config.matches(describe(e))
  }
  let rand = match seed {
    Some(bytes) => @random.Rand::chacha8(seed=bytes)
    None => @random.Rand::new()
  }
  { inner, config, retryable, wait, rand, }
}

///|
/// The wait before retry number `attempt`, spread by `jitter_factor` either side of its nominal
/// value and never negative.
fn RetryingClient::backoff_ms(self : RetryingClient, attempt : Int32) -> Int32 {
  let base = self.config.delay_ms(attempt).to_double()
  guard self.config.jitter_factor > 0.0 else { return base.to_int() }
  let spread = base * self.config.jitter_factor
  let delay = base + self.rand.double(min=-spread, max=spread)
  if delay < 0.0 {
    0
  } else {
    delay.to_int()
  }
}

///|
pub impl LLMClient for RetryingClient with fn execute(
  self,
  prompt~,
  model~,
  tools~,
) {
  let mut attempt = 1
  for ;; {
    let reply = LLMClient::execute(self.inner, prompt~, model~, tools~) catch {
      e => {
        if attempt >= self.config.max_attempts || !(self.retryable)(e) {
          raise e
        }
        (self.wait)(self.backoff_ms(attempt))
        attempt = attempt + 1
        continue
      }
    }
    return reply
  }
}

///|
pub impl LLMClient for RetryingClient with fn provider(self) {
  self.inner.provider()
}

///|
pub impl LLMClient for RetryingClient with fn moderate(self, prompt~, model~) {
  LLMClient::moderate(self.inner, prompt~, model~)
}

///|
pub impl LLMClient for RetryingClient with fn execute_multiple(
  self,
  prompt~,
  model~,
  tools~,
) {
  LLMClient::execute_multiple(self.inner, prompt~, model~, tools~)
}

///|
pub extend RetryPattern with Debug::{to_repr}

///|
pub extend RetryPattern with Eq::{not_equal, equal}

///|
pub extend RetryingClient with LLMClient::{
  execute,
  provider,
  execute_streaming,
  moderate,
  execute_multiple,
}
