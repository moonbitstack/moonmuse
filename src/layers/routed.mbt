///|
/// Routing by model name. A prefix picks the provider, and the longest matching prefix wins,
/// so `"claude-"` can send Claude models to one endpoint while `"claude-local"` sends a
/// local deployment elsewhere.

///|
/// A table of prefixes to providers.
pub struct Routed {
  routes : Map[String, &@moonmuse.Provider]
}

///|
/// A provider that picks a route by the requested model.
pub fn routed(routes : Map[String, &@moonmuse.Provider]) -> &@moonmuse.Provider {
  Routed::{ routes, }
}

///|
/// The provider this model routes to: the longest matching prefix, or `Unsupported` when
/// nothing matches. A table with an empty-string key is the catch-all.
fn Routed::pick(
  self : Routed,
  model : String,
) -> &@moonmuse.Provider raise @moonmuse.LlmError {
  let mut best : &@moonmuse.Provider? = None
  let mut best_length = -1
  for prefix, provider in self.routes {
    if model.has_prefix(prefix) && prefix.length() > best_length {
      best = Some(provider)
      best_length = prefix.length()
    }
  }
  match best {
    Some(provider) => provider
    None =>
      raise @moonmuse.Unsupported(
        "no route for model " +
        model +
        "; known prefixes: " +
        self.prefixes().join(", "),
      )
  }
}

///|
/// The prefixes this table knows, longest first.
pub fn Routed::prefixes(self : Routed) -> Array[String] {
  let out = []
  for prefix, _ in self.routes {
    out.push(prefix)
  }
  out.sort_by((a, b) => {
    if a.length() > b.length() {
      -1
    } else if a.length() < b.length() {
      1
    } else {
      0
    }
  })
  out
}

///|
pub impl @moonmuse.Provider for Routed with fn chat(self, request) {
  self.pick(request.model).chat(request)
}

///|
pub impl @moonmuse.Provider for Routed with fn stream(self, request, on_delta) {
  self.pick(request.model).stream(request, on_delta)
}

///|
pub impl @moonmuse.Provider for Routed with fn embed(self, model, inputs) {
  self.pick(model).embed(model, inputs)
}

///|
pub impl @moonmuse.Provider for Routed with fn models(self) {
  let out = []
  for _, provider in self.routes {
    let models = provider.models() catch {
      _ => ([] : Array[@moonmuse.ModelInfo])
    }
    for model in models {
      out.push(model)
    }
  }
  out
}

///|
pub extend Routed with @moonmuse.Provider::{chat, stream, embed, models}
