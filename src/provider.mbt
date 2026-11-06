///|
/// The one contract every model endpoint implements: a remote API, a local server, a
/// scripted fake, or a layer wrapped around another provider. Swapping providers is a
/// change to the constructor line, not to the calling code.
pub(open) trait Provider {
  /// One answer, delivered whole.
  async fn chat(Self, Request) -> Reply raise LlmError
  /// One answer, delivered as it is produced. The callback sees each delta; the
  /// returned reply is the same value `chat` would have returned.
  async fn stream(Self, Request, (Delta) -> Unit) -> Reply raise LlmError
  /// Vectors for `inputs`, one per input and in the same order.
  async fn embed(Self, String, Array[String]) -> Array[Array[Double]] raise LlmError
  /// What this provider serves, when it can say.
  async fn models(Self) -> Array[ModelInfo] raise LlmError
}

///|
/// A provider reference that can be stored in a record or an array.
pub type AnyProvider = &Provider

///|
/// The embeddings of a batch, checked against the batch length. A short answer is a
/// broken endpoint, not a partial success, because the caller indexes vectors by input
/// position.
pub fn check_vectors(
  inputs : Array[String],
  vectors : Array[Array[Double]],
) -> Array[Array[Double]] raise LlmError {
  if vectors.length() != inputs.length() {
    raise Decode(
      "expected " +
      inputs.length().to_string() +
      " vectors, got " +
      vectors.length().to_string(),
    )
  }
  vectors
}
