///|
/// A rate limit in front of a provider. The bucket starts full; a call takes one token and
/// waits for the bucket to refill when it is empty, so a caller never sees a rate-limit error
/// from its own client — it sees latency instead.

///|
/// A token bucket. `rate` is tokens per second and `burst` is the capacity.
pub struct Limiter {
  rate : Double
  burst : Double
  mut tokens : Double
  mut at : Int64
  clock : () -> Int64
}

///|
/// A bucket that refills at `rate` tokens per second and holds `burst` of them.
pub fn Limiter::new(
  rate : Double,
  burst~ : Double = rate,
  clock~ : () -> Int64 = @async.now,
) -> Limiter {
  { rate, burst, tokens: burst, at: clock(), clock, }
}

///|
/// Take one token if there is one. Returns the wait in milliseconds when there is not.
fn Limiter::take(self : Limiter) -> Int32 {
  let now = (self.clock)()
  let elapsed = (now - self.at).to_double() / 1_000_000.0
  self.at = now
  self.tokens = if self.tokens + elapsed * self.rate > self.burst {
    self.burst
  } else {
    self.tokens + elapsed * self.rate
  }
  if self.tokens >= 1.0 {
    self.tokens = self.tokens - 1.0
    0
  } else {
    let missing = 1.0 - self.tokens
    (missing / self.rate * 1_000.0).to_int()
  }
}

///|
/// A provider behind a bucket.
pub struct Limited {
  inner : &@moonmuse.Provider
  limiter : Limiter
}

///|
/// Put `limiter` in front of `provider`.
pub fn limited(
  provider : &@moonmuse.Provider,
  limiter : Limiter,
) -> &@moonmuse.Provider {
  Limited::{ inner: provider, limiter, }
}

///|
/// Wait until a token is free.
async fn Limited::acquire(self : Limited) -> Unit noraise {
  while true {
    let wait = self.limiter.take()
    if wait <= 0 {
      return
    }
    sleep(wait)
  }
}

///|
pub impl @moonmuse.Provider for Limited with fn chat(self, request) {
  self.acquire()
  self.inner.chat(request)
}

///|
pub impl @moonmuse.Provider for Limited with fn stream(self, request, on_delta) {
  self.acquire()
  self.inner.stream(request, on_delta)
}

///|
pub impl @moonmuse.Provider for Limited with fn embed(self, model, inputs) {
  self.acquire()
  self.inner.embed(model, inputs)
}

///|
pub impl @moonmuse.Provider for Limited with fn models(self) {
  self.inner.models()
}

///|
pub extend Limited with @moonmuse.Provider::{chat, stream, embed, models}
