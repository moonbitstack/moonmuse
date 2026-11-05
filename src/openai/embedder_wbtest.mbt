// The live-endpoint embedder (Koog `LLMEmbedder`). `diff` is deterministic (no network), so it is
// tested directly; the `/embeddings` round trip needs a live endpoint and is exercised by a smoke.

///|
test "llm embedder: diff is the cosine distance between embeddings" {
  let embedder : &@embeddings.Embedder = LLMEmbedder::new(
    api_key="test-key",
    base_url="https://api.openai.com/v1",
    model="text-embedding-3-small",
  )
  let a : @embeddings.Vector = { values: [1.0, 0.0], }
  let identical : @embeddings.Vector = { values: [1.0, 0.0], }
  let orthogonal : @embeddings.Vector = { values: [0.0, 1.0], }
  // Identical embeddings → cosine 1 → distance 0.
  assert_eq(embedder.diff(a, identical) < 1.0e-9, true)
  // Orthogonal embeddings → cosine 0 → distance 1.
  let d = embedder.diff(a, orthogonal)
  assert_eq(d > 0.99 && d < 1.01, true)
}
