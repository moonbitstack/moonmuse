///|
/// The layers, each checked on what decides the difference between it and a bare provider:
/// when a retry happens, when a fallback switches, which route a model picks, whether a
/// second identical request reaches the endpoint.

///|
/// A scripted reply, so a comparison is about the layer and not about the text.
fn reply(text : String) -> @moonmuse.Reply {
  @moonmuse.Reply::new(@moonmuse.Message::assistant(text))
}

///|
/// A request with one user message.
fn ask(model : String) -> @moonmuse.Request {
  @moonmuse.Request::new(model, [@moonmuse.Message::user("hi")])
}

///|
async test "retry: a rate limit is retried and the answer is returned" {
  let provider = @fake.Fake::flaky(2, reply("ok"), code=429)
  let waits = []
  let retried = @layers.retry(
    provider,
    policy=@layers.Retry::{
      attempts: 3,
      base_ms: 100,
      cap_ms: 1_000,
      factor: 2.0,
    },
    wait=ms => waits.push(ms),
  )
  let answer = retried.chat(ask("m"))
  assert_eq(answer.text(), "ok")
  assert_eq(provider.hits(), 3)
  assert_eq(waits, [100, 200])
}

///|
async test "retry: a bad request is not retried" {
  let provider = @fake.Fake::failing(400)
  let retried = @layers.retry(provider)
  let failed = try {
    let _ = retried.chat(ask("m"))
    false
  } catch {
    @moonmuse.Status(code~, ..) => code == 400
    _ => false
  }
  assert_eq(failed, true)
  assert_eq(provider.hits(), 1)
}

///|
async test "retry: the budget stops the attempts" {
  let provider = @fake.Fake::failing(503)
  let retried = @layers.retry(
    provider,
    policy=@layers.Retry::{ attempts: 3, base_ms: 1, cap_ms: 2, factor: 1.0, },
    wait=_ms => (),
  )
  let failed = try {
    let _ = retried.chat(ask("m"))
    false
  } catch {
    @moonmuse.Status(..) => true
    _ => false
  }
  assert_eq(failed, true)
  assert_eq(provider.hits(), 3)
}

///|
async test "fallback: a server fault switches to the next provider" {
  let first = @fake.Fake::failing(503)
  let second = @fake.Fake::text("second")
  let chain = @layers.fallback([first, second])
  assert_eq(chain.chat(ask("m")).text(), "second")
  assert_eq(first.hits(), 1)
}

///|
async test "fallback: a bad request does not switch" {
  let first = @fake.Fake::failing(400)
  let second = @fake.Fake::text("second")
  let chain = @layers.fallback([first, second])
  let failed = try {
    let _ = chain.chat(ask("m"))
    false
  } catch {
    @moonmuse.Status(code~, ..) => code == 400
    _ => false
  }
  assert_eq(failed, true)
  assert_eq(second.hits(), 0)
}

///|
async test "fallback: an empty chain refuses instead of crashing" {
  let chain = @layers.fallback([])
  let refused = try {
    let _ = chain.chat(ask("m"))
    false
  } catch {
    @moonmuse.Unsupported(_) => true
    _ => false
  }
  assert_eq(refused, true)
}

///|
async test "routed: the longest prefix wins" {
  let claude = @fake.Fake::text("claude")
  let nearby = @fake.Fake::text("local")
  let routes = Map([])
  routes["claude-"] = (claude : &@moonmuse.Provider)
  routes["claude-local"] = (nearby : &@moonmuse.Provider)
  let routed = @layers.routed(routes)
  assert_eq(routed.chat(ask("claude-local-v1")).text(), "local")
  assert_eq(routed.chat(ask("claude-sonnet")).text(), "claude")
}

///|
async test "routed: an unknown model is unsupported" {
  let routes = Map([])
  routes["claude-"] = (@fake.Fake::text("x") : &@moonmuse.Provider)
  let routed = @layers.routed(routes)
  let refused = try {
    let _ = routed.chat(ask("gpt-4o"))
    false
  } catch {
    @moonmuse.Unsupported(_) => true
    _ => false
  }
  assert_eq(refused, true)
}

///|
async test "cached: the same request reaches the endpoint once" {
  let provider = @fake.Fake::text("ok")
  let cache = @layers.Memory::new(limit=4)
  let cached = @layers.cached(provider, cache)
  assert_eq(cached.chat(ask("m")).text(), "ok")
  assert_eq(cached.chat(ask("m")).text(), "ok")
  assert_eq(provider.hits(), 1)
  assert_eq(cache.size(), 1)
}

///|
async test "cached: a different temperature is a different key" {
  let provider = @fake.Fake::text("ok")
  let cached = @layers.cached(provider, @layers.Memory::new(limit=4))
  let _ = cached.chat(
    @moonmuse.Request::new(
      "m",
      [@moonmuse.Message::user("hi")],
      temperature=0.1,
    ),
  )
  let _ = cached.chat(
    @moonmuse.Request::new(
      "m",
      [@moonmuse.Message::user("hi")],
      temperature=0.9,
    ),
  )
  assert_eq(provider.hits(), 2)
}

///|
async test "cached: the oldest entry is evicted at the limit" {
  let cache = @layers.Memory::new(limit=1)
  cache.put("a", reply("a"))
  cache.put("b", reply("b"))
  assert_eq(cache.size(), 1)
  assert_eq(cache.get("a"), None)
  assert_eq(cache.get("b") is Some(_), true)
}

///|
async test "limited: the bucket lets the burst through without waiting" {
  let provider = @fake.Fake::text("ok")
  let limited = @layers.limited(
    provider,
    @layers.Limiter::new(1_000.0, burst=2.0, clock=() => 0L),
  )
  for i = 0; i < 2; i = i + 1 {
    let _ = limited.chat(ask("m"))
  }
  assert_eq(provider.hits(), 2)
}

///|
/// A provider that always fails with a decode error, which no fallback can fix.
struct Broken {}

///|
impl @moonmuse.Provider for Broken with fn chat(_self, _request) {
  raise @moonmuse.Decode("the body was not the shape promised")
}

///|
impl @moonmuse.Provider for Broken with fn stream(_self, _request, _on_delta) {
  raise @moonmuse.Decode("the body was not the shape promised")
}

///|
impl @moonmuse.Provider for Broken with fn embed(_self, _model, _inputs) {
  raise @moonmuse.Decode("the body was not the shape promised")
}

///|
impl @moonmuse.Provider for Broken with fn models(_self) {
  raise @moonmuse.Decode("the body was not the shape promised")
}

///|
pub extend Broken with @moonmuse.Provider::{chat, stream, embed, models}

///|
async test "fallback: a decode failure does not switch" {
  let second = @fake.Fake::text("second")
  let broken : &@moonmuse.Provider = Broken::{ }
  let chain = @layers.fallback([broken, second])
  let failed = try {
    let _ = chain.chat(ask("m"))
    false
  } catch {
    @moonmuse.Decode(_) => true
    _ => false
  }
  assert_eq(failed, true)
  assert_eq(second.hits(), 0)
}
