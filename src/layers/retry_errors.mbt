// Wiring `@moonmuse.RetryingClient` to the errors these clients actually raise.
//
// A caught `Error` in MoonBit carries no payload: `Error::to_string` on one yields the
// constructor's qualified name, so a retry classifying by message needs the error narrowed back
// to its own type first. Every error out of an OpenAI-compatible or Anthropic client comes from
// moonllm's transport, so that narrowing lives here rather than in `agent`, which cannot see
// moonllm at all.

///|
/// The message behind a caught error: the full text of a moonllm `LLMError` — the status code
/// and body of an API error, the reason of a transport failure — or, for anything else, the
/// error's type name, which is all a bare `Error` will say. Pass it as a `RetryingClient`'s
/// `describe` so `RetryConfig`'s patterns have something to match.
pub fn describe_llm_error(error : Error) -> String {
  match error {
    @moonllm.Transport(_) as e => e.to_string()
    @moonllm.ApiError(..) as e => e.to_string()
    @moonllm.Decode(_) as e => e.to_string()
    @moonllm.Stream(_) as e => e.to_string()
    _ => @moonmuse.default_describe(error)
  }
}

///|
/// `inner` wrapped in a retry that already knows how to read its errors — the OpenAI-compatible
/// and Anthropic clients' usual pairing, since `RetryingClient::new` on its own cannot see past
/// an `Error`'s type name.
pub fn retrying(
  inner : &@moonmuse.LLMClient,
  config~ : @moonmuse.RetryConfig = @moonmuse.RetryConfig::default(),
) -> @moonmuse.RetryingClient {
  @moonmuse.RetryingClient::new(inner, config~, describe=describe_llm_error)
}
