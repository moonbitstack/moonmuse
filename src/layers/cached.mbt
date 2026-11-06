///|
/// Caching answers. The key is everything that decides an answer — model, messages, tools,
/// tool choice and the sampling parameters — so a cache hit is always the answer the
/// endpoint would have given. Only whole answers are cached; a streamed call fills the cache
/// for the next non-streamed one.

///|
/// A place to keep answers. A process-wide map is the default; a shared store can implement
/// the same two methods.
pub(open) trait Cache {
  fn get(Self, String) -> @moonmuse.Reply?
  fn put(Self, String, @moonmuse.Reply) -> Unit
}

///|
/// An in-memory cache with a fixed number of entries, oldest evicted first.
pub struct Memory {
  entries : Map[String, @moonmuse.Reply]
  mut order : Array[String]
  limit : Int32
}

///|
/// A cache of at most `limit` answers.
pub fn Memory::new(limit~ : Int32 = 256) -> Memory {
  { entries: Map([]), order: [], limit, }
}

///|
/// How many answers are held.
pub fn Memory::size(self : Memory) -> Int32 {
  self.order.length()
}

///|
pub impl Cache for Memory with fn get(self, key) {
  self.entries.get(key)
}

///|
pub impl Cache for Memory with fn put(self, key, reply) {
  if !self.entries.contains(key) {
    if self.order.length() >= self.limit && !self.order.is_empty() {
      let oldest = self.order[0]
      self.order = self.order.exact_view(start=1).to_owned()
      self.entries.remove(oldest)
    }
    self.order.push(key)
  }
  self.entries[key] = reply
}

///|
pub extend Memory with Cache::{get, put}

///|
/// A provider that answers from `cache` when it can.
pub struct Cached {
  inner : &@moonmuse.Provider
  cache : &Cache
}

///|
/// Put a cache in front of `provider`.
pub fn cached(
  provider : &@moonmuse.Provider,
  cache : &Cache,
) -> &@moonmuse.Provider {
  Cached::{ inner: provider, cache, }
}

///|
pub impl @moonmuse.Provider for Cached with fn chat(self, request) {
  let key = request_key(request)
  match self.cache.get(key) {
    Some(reply) => return reply
    None => ()
  }
  let reply = self.inner.chat(request)
  self.cache.put(key, reply)
  reply
}

///|
pub impl @moonmuse.Provider for Cached with fn stream(self, request, on_delta) {
  // A streamed call is not served from the cache: its deltas are the point.
  self.inner.stream(request, on_delta)
}

///|
pub impl @moonmuse.Provider for Cached with fn embed(self, model, inputs) {
  self.inner.embed(model, inputs)
}

///|
pub impl @moonmuse.Provider for Cached with fn models(self) {
  self.inner.models()
}

///|
pub extend Cached with @moonmuse.Provider::{chat, stream, embed, models}

///|
/// A canonical key for a request: every field that can change the answer, in a fixed order.
pub fn request_key(request : @moonmuse.Request) -> String {
  let messages = []
  for message in request.messages {
    let parts = []
    for part in message.parts {
      match part {
        @moonmuse.Part::Text(text) =>
          parts.push(@moonmuse.object_json([("t", Json::string(text))]))
        @moonmuse.Part::Call(id~, name~, args~) =>
          parts.push(
            @moonmuse.object_json([
              ("c", Json::string(id)),
              ("n", Json::string(name)),
              ("a", args),
            ]),
          )
        @moonmuse.Part::Result(id~, content~, error~) =>
          parts.push(
            @moonmuse.object_json([
              ("r", Json::string(id)),
              ("o", Json::string(content)),
              ("e", Json::boolean(error)),
            ]),
          )
        @moonmuse.Part::Image(url~, media~) =>
          parts.push(
            @moonmuse.object_json([
              ("i", Json::string(url)),
              ("m", Json::string(media.unwrap_or(""))),
            ]),
          )
      }
    }
    messages.push(
      @moonmuse.object_json([
        ("role", Json::string(message.role.code())),
        ("parts", Json::array(parts)),
      ]),
    )
  }
  let fields = [
    ("model", Json::string(request.model)),
    ("messages", Json::array(messages)),
    ("tools", @moonmuse.strings_json(request.tools.map(tool => tool.name))),
    (
      "choice",
      match request.choice {
        @moonmuse.Auto => Json::string("auto")
        @moonmuse.NoTools => Json::string("none")
        @moonmuse.Required => Json::string("required")
        @moonmuse.Named(name) => Json::string("named:" + name)
      },
    ),
  ]
  match request.temperature {
    Some(value) => fields.push(("temperature", Json::number(value)))
    None => ()
  }
  match request.max_tokens {
    Some(value) => fields.push(("max_tokens", Json::number(value.to_double())))
    None => ()
  }
  if !request.stop.is_empty() {
    fields.push(("stop", @moonmuse.strings_json(request.stop)))
  }
  for key, value in request.extra {
    fields.push(("extra:" + key, value))
  }
  @moonmuse.object_json(fields).stringify()
}
