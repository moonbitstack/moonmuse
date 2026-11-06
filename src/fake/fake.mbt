///|
/// A provider that answers from a script. Every reply is chosen by call order, the last
/// one repeating, so a test states exactly what the model says and can then assert on what
/// the loop did with it. The requests it saw are kept, which is how a test checks the
/// request a layer built.

///|
/// A scripted provider.
pub struct Fake {
  replies : Array[@moonmuse.Reply]
  mut next : Int32
  /// How many calls have been answered.
  mut hits : Int32
  /// Every request, in order.
  requests : Array[@moonmuse.Request]
  /// What `models` reports.
  models : Array[@moonmuse.ModelInfo]
  /// The width of the vectors `embed` produces.
  dimension : Int32
  /// When non-zero, every call fails with this status instead of answering.
  fail_code : Int32
  /// How many more calls fail before this one starts answering.
  mut fail_left : Int32
}

///|
/// A provider that answers with `replies` in order.
pub fn Fake::new(
  replies : Array[@moonmuse.Reply],
  models~ : Array[@moonmuse.ModelInfo] = [],
  dimension~ : Int32 = 8,
) -> Fake {
  {
    replies,
    next: 0,
    hits: 0,
    requests: [],
    models,
    dimension,
    fail_code: 0,
    fail_left: 0,
  }
}

///|
/// A provider that always answers with one text.
pub fn Fake::text(text : String) -> Fake {
  Fake::new([
    @moonmuse.Reply::new(
      @moonmuse.Message::new(@moonmuse.Assistant, [@moonmuse.Part::text(text)]),
    ),
  ])
}

///|
/// A provider that fails every call with `code`, for the layers that retry or fall back.
pub fn Fake::failing(code : Int32) -> Fake {
  let base = Fake::text("")
  { ..base, fail_code: code, fail_left: -1, }
}

///|
/// A provider that fails `fails` times with `code`, then answers with `reply` — the shape a
/// retry or a fallback is supposed to survive.
pub fn Fake::flaky(
  fails : Int32,
  reply : @moonmuse.Reply,
  code~ : Int32 = 503,
) -> Fake {
  { ..Fake::new([reply]), fail_code: code, fail_left: fails, }
}

///|
/// A provider that always asks for one tool call.
pub fn Fake::calls(name : String, args : Json, id~ : String = "call_1") -> Fake {
  Fake::new([
    @moonmuse.Reply::new(
      @moonmuse.Message::new(@moonmuse.Assistant, [
        @moonmuse.Part::call(id, name, args),
      ]),
      finish=@moonmuse.Calls,
    ),
  ])
}

///|
/// How many calls have been answered.
pub fn Fake::hits(self : Fake) -> Int32 {
  self.hits
}

///|
/// The requests this provider saw, in order.
pub fn Fake::seen(self : Fake) -> Array[@moonmuse.Request] {
  self.requests
}

///|
/// The reply for the next call.
fn Fake::pick(self : Fake, request : @moonmuse.Request) -> @moonmuse.Reply {
  self.requests.push(request)
  self.hits = self.hits + 1
  let index = if self.next < self.replies.length() {
    self.next
  } else {
    self.replies.length() - 1
  }
  self.next = self.next + 1
  if self.replies.is_empty() {
    return @moonmuse.Reply::new(@moonmuse.Message::new(@moonmuse.Assistant, []))
  }
  self.replies[index]
}

///|
pub impl @moonmuse.Provider for Fake with fn chat(self, request) {
  let failing = if self.fail_left < 0 { true } else { self.fail_left > 0 }
  if self.fail_code > 0 && failing {
    self.requests.push(request)
    self.hits = self.hits + 1
    if self.fail_left > 0 {
      self.fail_left = self.fail_left - 1
    }
    raise @moonmuse.Status(
      code=self.fail_code,
      body="scripted failure",
      retry_after=None,
    )
  }
  self.pick(request)
}

///|
/// Replay the reply as deltas: text in five-character slices, then each call, then `Done`.
/// A test that checks incremental handling sees more than one text delta.
pub impl @moonmuse.Provider for Fake with fn stream(self, request, on_delta) {
  let reply = self.pick(request)
  let text = reply.message.text_content(separator="")
  let mut start = 0
  while start < text.length() {
    let end = if start + 5 < text.length() { start + 5 } else { text.length() }
    on_delta(@moonmuse.Delta::Text(text.exact_view(start~, end~).to_owned()))
    start = end
  }
  for part in reply.message.calls() {
    match part {
      @moonmuse.Part::Call(id~, name~, args~) => {
        on_delta(@moonmuse.Delta::CallStart(id~, name~))
        on_delta(@moonmuse.Delta::CallArgs(id~, chunk=args.stringify()))
      }
      _ => ()
    }
  }
  on_delta(@moonmuse.Delta::Done(reply))
  reply
}

///|
/// A deterministic vector per input: the same text always yields the same numbers, and two
/// different texts almost always differ. Enough to test a retriever without a model.
pub impl @moonmuse.Provider for Fake with fn embed(self, _model, inputs) {
  let vectors = []
  for input in inputs {
    let vector = Array::makei(self.dimension, index => {
      let weight = (index + 1).to_double()
      let total = text_weight(input)
      total * weight % 17.0 / 17.0
    })
    vectors.push(vector)
  }
  @moonmuse.check_vectors(inputs, vectors)
}

///|
/// A stable sum for a string, used to derive its vector.
fn text_weight(text : String) -> Double {
  let mut total = 0
  for char in text {
    total = (total * 31 + char.to_int()) % 9973
  }
  total.to_double()
}

///|
pub impl @moonmuse.Provider for Fake with fn models(self) {
  if self.models.is_empty() {
    return [
      @moonmuse.ModelInfo::new("fake", context=8192, capabilities=[
        @moonmuse.Chat,
        @moonmuse.Tools,
        @moonmuse.Embedding,
      ]),
    ]
  }
  self.models
}

///|
pub extend Fake with @moonmuse.Provider::{chat, stream, embed, models}
