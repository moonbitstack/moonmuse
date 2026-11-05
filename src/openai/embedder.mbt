// A real text embedder backed by an OpenAI-compatible `/embeddings` endpoint (Koog `embeddings-llm`
// `LLMEmbedder`): it implements moonkoog's `@embeddings.Embedder` by calling moonllm's embeddings API
// and wrapping the returned floats in a `Vector`, so the RAG stack (VectorStore + ranking) can run
// against a live embedding model instead of the deterministic mock.
// Source: embeddings/embeddings-llm/.../local/LLMEmbedder.kt.

///|
/// An embedder that calls an OpenAI-compatible `/embeddings` endpoint. `model` is the embedding
/// model id (e.g. `text-embedding-3-small`); moonllm carries the HTTPS transport.
pub struct LLMEmbedder {
  inner : @moonllm.Client
  model : String
}

///|
/// Build an embedder for `base_url`, authenticating with a bearer `api_key` and requesting `model`.
pub fn LLMEmbedder::new(
  api_key~ : String,
  base_url~ : String,
  model~ : String,
  timeout_ms~ : Int32 = 60000,
) -> LLMEmbedder {
  { inner: @moonllm.Client::new(api_key, base_url~, timeout_ms~), model, }
}

///|
pub impl @embeddings.Embedder for LLMEmbedder with fn embed(self, text) {
  let request = @moonllm.EmbeddingRequest::of_text(self.model, text)
  let response = self.inner.embeddings(request)
  { values: response.vector(), }
}

///|
pub impl @embeddings.Embedder for LLMEmbedder with fn diff(
  self,
  embedding1,
  embedding2,
) {
  let _ = self
  // Cosine distance; a dimension mismatch counts as fully different.
  1.0 - (embedding1.cosine_similarity(embedding2) catch { _ => 0.0 })
}

///|
pub extend LLMEmbedder with @embeddings.Embedder::{embed, diff}
