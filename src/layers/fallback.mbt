///|
/// Falling back to the next provider. The switch happens on a failure another provider
/// could avoid — a rate limit, a server fault, a capability this endpoint does not have —
/// and not on a malformed request, which every provider would refuse the same way.

///|
/// A chain of providers tried in order.
pub struct Fallback {
  providers : Array[&@moonmuse.Provider]
}

///|
/// Try each provider in turn. An empty chain answers with `Unsupported` rather than an
/// index out of bounds.
pub fn fallback(providers : Array[&@moonmuse.Provider]) -> &@moonmuse.Provider {
  Fallback::{ providers, }
}

///|
/// Whether the next provider is worth trying after `error`.
pub fn should_switch(error : @moonmuse.LlmError) -> Bool {
  match error {
    @moonmuse.Status(code~, ..) =>
      code == 408 || code == 409 || code == 429 || code >= 500
    @moonmuse.Stream(_) => true
    @moonmuse.Unsupported(_) => true
    @moonmuse.Decode(_) => false
  }
}

///|
pub impl @moonmuse.Provider for Fallback with fn chat(self, request) {
  let mut last : @moonmuse.LlmError? = None
  for provider in self.providers {
    let result = Ok(provider.chat(request)) catch { error => Err(error) }
    match result {
      Ok(reply) => return reply
      Err(error) => {
        last = Some(error)
        if !should_switch(error) {
          raise error
        }
      }
    }
  }
  match last {
    Some(error) => raise error
    None => raise @moonmuse.Unsupported("no provider in the fallback chain")
  }
}

///|
pub impl @moonmuse.Provider for Fallback with fn stream(self, request, on_delta) {
  let mut last : @moonmuse.LlmError? = None
  for provider in self.providers {
    let result = Ok(provider.stream(request, on_delta)) catch {
      error => Err(error)
    }
    match result {
      Ok(reply) => return reply
      Err(error) => {
        last = Some(error)
        if !should_switch(error) {
          raise error
        }
      }
    }
  }
  match last {
    Some(error) => raise error
    None => raise @moonmuse.Unsupported("no provider in the fallback chain")
  }
}

///|
pub impl @moonmuse.Provider for Fallback with fn embed(self, model, inputs) {
  let mut last : @moonmuse.LlmError? = None
  for provider in self.providers {
    let result = Ok(provider.embed(model, inputs)) catch { error => Err(error) }
    match result {
      Ok(vectors) => return vectors
      Err(error) => {
        last = Some(error)
        if !should_switch(error) {
          raise error
        }
      }
    }
  }
  match last {
    Some(error) => raise error
    None => raise @moonmuse.Unsupported("no provider in the fallback chain")
  }
}

///|
pub impl @moonmuse.Provider for Fallback with fn models(self) {
  let mut last : @moonmuse.LlmError? = None
  for provider in self.providers {
    let result = Ok(provider.models()) catch { error => Err(error) }
    match result {
      Ok(models) => return models
      Err(error) => {
        last = Some(error)
        if !should_switch(error) {
          raise error
        }
      }
    }
  }
  match last {
    Some(error) => raise error
    None => raise @moonmuse.Unsupported("no provider in the fallback chain")
  }
}

///|
pub extend Fallback with @moonmuse.Provider::{chat, stream, embed, models}
