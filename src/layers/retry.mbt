///|
/// Retrying a provider call. Only failures that could plausibly succeed on the next try are
/// retried — a rate limit, a server fault, a dropped stream — and the wait the endpoint
/// asked for is honoured before the backoff is computed.

///|
/// How often and how patiently to retry.
#derive(Eq, Debug)
pub(all) struct Retry {
  /// Total attempts, including the first.
  attempts : Int32
  /// The wait before the second attempt.
  base_ms : Int32
  /// The ceiling the wait grows to.
  cap_ms : Int32
  /// What each further wait is multiplied by.
  factor : Double
}

///|
/// Three attempts, 200 ms doubling to 5 s.
pub fn Retry::default() -> Retry {
  { attempts: 3, base_ms: 200, cap_ms: 5_000, factor: 2.0, }
}

///|
/// One attempt only.
pub let once : Retry = { attempts: 1, base_ms: 0, cap_ms: 0, factor: 1.0, }

///|
/// The nominal wait before attempt number `attempt` (0 for the first retry).
pub fn Retry::delay_ms(self : Retry, attempt : Int32) -> Int32 {
  let mut wait = self.base_ms.to_double()
  for i = 0; i < attempt; i = i + 1 {
    wait = wait * self.factor
  }
  if wait > self.cap_ms.to_double() {
    self.cap_ms
  } else {
    wait.to_int()
  }
}

///|
/// A provider that retries chat and embeddings.
pub struct Retrying {
  inner : &@moonmuse.Provider
  policy : Retry
  wait : async (Int32) -> Unit noraise
}

///|
/// Wrap `inner`. `wait` is the sleep, injectable so a test observes the schedule instead of
/// living through it.
pub fn retry(
  inner : &@moonmuse.Provider,
  policy~ : Retry = Retry::default(),
  wait~ : async (Int32) -> Unit noraise = sleep,
) -> &@moonmuse.Provider {
  Retrying::{ inner, policy, wait, }
}

///|
/// A copy of this provider with another policy.
pub fn Retrying::policy(self : Retrying, policy : Retry) -> Retrying {
  { ..self, policy, }
}

///|
/// The wait before retry `attempt`, honouring a `retry-after` the endpoint sent.
fn Retrying::wait_for(
  self : Retrying,
  attempt : Int32,
  error : @moonmuse.LlmError,
) -> Int32 {
  match error.retry_after() {
    Some(seconds) =>
      if seconds > 86_400 {
        86_400_000
      } else {
        (seconds * 1_000L).to_int()
      }
    None => self.policy.delay_ms(attempt)
  }
}

///|
pub impl @moonmuse.Provider for Retrying with fn chat(self, request) {
  let mut attempt = 0
  while true {
    let reply = self.inner.chat(request) catch {
      error => {
        if attempt + 1 >= self.policy.attempts || !error.is_retryable() {
          raise error
        }
        (self.wait)(self.wait_for(attempt, error))
        attempt = attempt + 1
        continue
      }
    }
    return reply
  }
  abort("unreachable")
}

///|
pub impl @moonmuse.Provider for Retrying with fn stream(self, request, on_delta) {
  self.inner.stream(request, on_delta)
}

///|
pub impl @moonmuse.Provider for Retrying with fn embed(self, model, inputs) {
  let mut attempt = 0
  while true {
    let vectors = self.inner.embed(model, inputs) catch {
      error => {
        if attempt + 1 >= self.policy.attempts || !error.is_retryable() {
          raise error
        }
        (self.wait)(self.wait_for(attempt, error))
        attempt = attempt + 1
        continue
      }
    }
    return vectors
  }
  abort("unreachable")
}

///|
pub impl @moonmuse.Provider for Retrying with fn models(self) {
  self.inner.models()
}

///|
pub extend Retrying with @moonmuse.Provider::{chat, stream, embed, models}

///|
pub extend Retry with Eq::{not_equal, equal}

///|
pub extend Retry with Debug::{to_repr}
