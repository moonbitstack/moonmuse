///|
/// What a local model run can fail with. The two cases are the caller's two problems: the
/// engine could not produce text, or the template could not be rendered.

///|
/// A local generation failure.
pub(all) suberror LocalError {
  /// The engine failed: out of memory, a cancelled run, a model that would not load.
  Engine(String)
  /// The chat template did not render. A template is data, and bad data is a message.
  Template(String)
  /// The engine cannot do this at all, such as embeddings from a text-only model.
  Unsupported(String)
}

///|
/// The inference engine this package drives. An engine knows weights, tokens and a context
/// window; it does not know `Provider`, HTTP, or which chat format a model was trained on —
/// those are this package's job.
pub(open) trait Engine {
  /// Generate a continuation for `prompt`, stopping after `limit` tokens when the engine can
  /// honour a limit.
  async fn generate(Self, String, Int32) -> String raise LocalError
  /// Generate, handing each piece of text to `on_chunk` as it is produced, and return the
  /// whole continuation.
  async fn stream(Self, String, Int32, (String) -> Unit) -> String raise LocalError = _
  /// Vectors for `inputs`, for an engine that also serves an embedding model.
  async fn embed(Self, String, Array[String]) -> Array[Array[Double]] raise LocalError = _
  /// What this engine serves.
  fn models(Self) -> Array[@moonmuse.ModelInfo] = _
}

///|
/// The default stream: generate whole and hand it over as one piece. An engine that can do
/// better overrides it.
impl Engine with fn stream(self, prompt, limit, on_chunk) {
  let text = self.generate(prompt, limit)
  if text != "" {
    on_chunk(text)
  }
  text
}

///|
/// The default embeddings: an engine that only generates text has none, and saying so is
/// better than returning zero vectors that look like an answer.
impl Engine with fn embed(self, _model, _inputs) {
  let _ = self
  raise LocalError::Unsupported("this engine serves no embeddings")
}

///|
/// The default model list: an engine that does not say.
impl Engine with fn models(self) {
  let _ = self
  []
}
