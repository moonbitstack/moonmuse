///|
fn or0(x : Int32?) -> Int32 {
  match x {
    Some(n) => n
    None => 0
  }
}

///|
/// The model catalog: the `LLMProvider` list, the `LLModel` entries with their
/// context windows, and the `LLMCapability` set each model advertises. `supports`
/// answers the capability question a client asks before it sends a request — can
/// this model take tools, force a tool choice, see images, or think out loud.
///
///     moon run examples/03-model-catalog --target native
#coverage.skip
fn main {
  let providers = [
    @models.openai, @models.anthropic, @models.google, @models.deepseek, @models.mistralai, @models.ollama,
    @models.openrouter,
  ]
  let names = providers.map(p => p.display)
  println("providers: " + names.join(", "))
  let sonnet = @models.claude_sonnet_4_5
  println(
    "\{sonnet.provider.id}:\{sonnet.id} ctx=\{or0(sonnet.context_length)} max_out=\{or0(sonnet.max_output_tokens)}",
  )
  println(
    "  tools=\{sonnet.supports(@models.Tools)} tool_choice=\{sonnet.supports(@models.ToolChoice)} vision=\{sonnet.supports(@models.Vision)} thinking=\{sonnet.supports(@models.Thinking)}",
  )
  let flash = @models.deepseek_v4_flash
  println(
    "\{flash.provider.id}:\{flash.id} tools=\{flash.supports(@models.Tools)} caching=\{flash.supports(@models.PromptCaching)}",
  )

  // The per-provider catalogs the client picks a model from.
  let catalogs : Array[(String, Array[@models.LLModel])] = [
    ("openai", @models.openai_models()),
    ("deepseek", @models.deepseek_models()),
    ("google", @models.google_models()),
    ("mistral", @models.mistral_models()),
  ]
  for entry in catalogs {
    let (label, models) = entry
    let embedders = models.filter(m => m.supports(@models.Embed)).length()
    println(
      "\{label}: \{models.length()} models, \{embedders} of them embedders",
    )
  }

  // Capability queries route a request to the right endpoint kind.
  println(
    "text-embedding-3-small embeds: \{@models.text_embedding_3_small.supports(@models.Embed)}",
  )
  println(
    "omni-moderation moderates: \{@models.omni_moderation.supports(@models.Moderation)}",
  )
}
