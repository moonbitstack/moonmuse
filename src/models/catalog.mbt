///|
/// The model catalogue. Prices are US dollars per million tokens as each vendor publishes
/// them, and the context and output limits are the ones printed beside them. Vendors change
/// both without notice, so this is a starting point for an estimate, not a bill: the reply's
/// own usage is what a call actually cost.

///|
/// One family's models, newest first.
fn openai_models() -> Array[@moonmuse.ModelInfo] {
  [
    @moonmuse.ModelInfo::new(
      "gpt-4.1",
      context=1_047_576,
      output=32_768,
      input_price=2.0,
      output_price=8.0,
      capabilities=[
        @moonmuse.Chat,
        @moonmuse.Tools,
        @moonmuse.Vision,
        @moonmuse.Json,
      ],
    ),
    @moonmuse.ModelInfo::new(
      "gpt-4.1-mini",
      context=1_047_576,
      output=32_768,
      input_price=0.4,
      output_price=1.6,
      capabilities=[
        @moonmuse.Chat,
        @moonmuse.Tools,
        @moonmuse.Vision,
        @moonmuse.Json,
      ],
    ),
    @moonmuse.ModelInfo::new(
      "gpt-4o",
      context=128_000,
      output=16_384,
      input_price=2.5,
      output_price=10.0,
      capabilities=[
        @moonmuse.Chat,
        @moonmuse.Tools,
        @moonmuse.Vision,
        @moonmuse.Audio,
        @moonmuse.Json,
      ],
    ),
    @moonmuse.ModelInfo::new(
      "gpt-4o-mini",
      context=128_000,
      output=16_384,
      input_price=0.15,
      output_price=0.6,
      capabilities=[
        @moonmuse.Chat,
        @moonmuse.Tools,
        @moonmuse.Vision,
        @moonmuse.Json,
      ],
    ),
    @moonmuse.ModelInfo::new(
      "o4-mini",
      context=200_000,
      output=100_000,
      input_price=1.1,
      output_price=4.4,
      capabilities=[@moonmuse.Chat, @moonmuse.Tools, @moonmuse.Reasoning],
    ),
    @moonmuse.ModelInfo::new(
      "text-embedding-3-small",
      context=8_191,
      output=1_536,
      input_price=0.02,
      output_price=0.0,
      capabilities=[@moonmuse.Embedding],
    ),
    @moonmuse.ModelInfo::new(
      "text-embedding-3-large",
      context=8_191,
      output=3_072,
      input_price=0.13,
      output_price=0.0,
      capabilities=[@moonmuse.Embedding],
    ),
  ]
}

///|
/// Anthropic's models.
fn anthropic_models() -> Array[@moonmuse.ModelInfo] {
  [
    @moonmuse.ModelInfo::new(
      "claude-opus-4-20250514",
      context=200_000,
      output=32_000,
      input_price=15.0,
      output_price=75.0,
      capabilities=[
        @moonmuse.Chat,
        @moonmuse.Tools,
        @moonmuse.Vision,
        @moonmuse.Reasoning,
      ],
    ),
    @moonmuse.ModelInfo::new(
      "claude-sonnet-4-20250514",
      context=200_000,
      output=64_000,
      input_price=3.0,
      output_price=15.0,
      capabilities=[
        @moonmuse.Chat,
        @moonmuse.Tools,
        @moonmuse.Vision,
        @moonmuse.Reasoning,
      ],
    ),
    @moonmuse.ModelInfo::new(
      "claude-3-5-haiku-20241022",
      context=200_000,
      output=8_192,
      input_price=0.8,
      output_price=4.0,
      capabilities=[@moonmuse.Chat, @moonmuse.Tools],
    ),
  ]
}

///|
/// Google's models.
fn google_models() -> Array[@moonmuse.ModelInfo] {
  [
    @moonmuse.ModelInfo::new(
      "gemini-2.5-pro",
      context=1_048_576,
      output=65_536,
      input_price=1.25,
      output_price=10.0,
      capabilities=[
        @moonmuse.Chat,
        @moonmuse.Tools,
        @moonmuse.Vision,
        @moonmuse.Reasoning,
        @moonmuse.Json,
      ],
    ),
    @moonmuse.ModelInfo::new(
      "gemini-2.5-flash",
      context=1_048_576,
      output=65_536,
      input_price=0.3,
      output_price=2.5,
      capabilities=[
        @moonmuse.Chat,
        @moonmuse.Tools,
        @moonmuse.Vision,
        @moonmuse.Json,
      ],
    ),
    @moonmuse.ModelInfo::new(
      "text-embedding-004",
      context=2_048,
      output=768,
      input_price=0.0,
      output_price=0.0,
      capabilities=[@moonmuse.Embedding],
    ),
  ]
}

///|
/// DeepSeek's models, served over the OpenAI-compatible endpoint.
fn deepseek_models() -> Array[@moonmuse.ModelInfo] {
  [
    @moonmuse.ModelInfo::new(
      "deepseek-chat",
      context=65_536,
      output=8_192,
      input_price=0.27,
      output_price=1.1,
      capabilities=[@moonmuse.Chat, @moonmuse.Tools, @moonmuse.Json],
    ),
    @moonmuse.ModelInfo::new(
      "deepseek-reasoner",
      context=65_536,
      output=8_192,
      input_price=0.55,
      output_price=2.19,
      capabilities=[@moonmuse.Chat, @moonmuse.Reasoning],
    ),
  ]
}

///|
/// Models a local Ollama server commonly carries. Their prices are zero: the cost is the
/// machine they run on.
fn ollama_models() -> Array[@moonmuse.ModelInfo] {
  [
    @moonmuse.ModelInfo::new(
      "llama3.2",
      context=131_072,
      output=4_096,
      input_price=0.0,
      output_price=0.0,
      capabilities=[@moonmuse.Chat, @moonmuse.Tools],
    ),
    @moonmuse.ModelInfo::new(
      "qwen2.5",
      context=32_768,
      output=4_096,
      input_price=0.0,
      output_price=0.0,
      capabilities=[@moonmuse.Chat, @moonmuse.Tools, @moonmuse.Json],
    ),
    @moonmuse.ModelInfo::new(
      "nomic-embed-text",
      context=8_192,
      output=768,
      input_price=0.0,
      output_price=0.0,
      capabilities=[@moonmuse.Embedding],
    ),
  ]
}

///|
/// Every model this catalogue knows, grouped by vendor in the order above.
pub fn catalog() -> Array[@moonmuse.ModelInfo] {
  [
    ..openai_models(),
    ..anthropic_models(),
    ..google_models(),
    ..deepseek_models(),
    ..ollama_models(),
  ]
}

///|
/// The model with this id, when the catalogue knows it.
pub fn find(id : String) -> @moonmuse.ModelInfo? {
  for model in catalog() {
    if model.id == id {
      return Some(model)
    }
  }
  None
}

///|
/// What one call would cost at list prices, from the usage the endpoint reported. `None`
/// when the model is unknown or the usage did not report both counts, because a partial
/// estimate reads as a cheaper call than it was.
pub fn estimate_cost(id : String, usage : @moonmuse.Usage) -> Double? {
  match (find(id), usage.input, usage.output) {
    (Some(model), Some(input), Some(output)) =>
      match (model.input_price, model.output_price) {
        (Some(input_price), Some(output_price)) =>
          Some(
            (
              input.to_double() * input_price +
              output.to_double() * output_price
            ) /
            1_000_000.0,
          )
        _ => None
      }
    _ => None
  }
}

///|
/// The models that declare `capability`.
pub fn with_capability(
  capability : @moonmuse.Capability,
) -> Array[@moonmuse.ModelInfo] {
  catalog().filter(model => model.supports(capability))
}
