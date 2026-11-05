///|
struct Weather {}

///|
impl @toolbox.Tool for Weather with fn descriptor(_) {
  {
    name: "weather",
    description: "current weather for a city",
    required_parameters: [
      {
        name: "city",
        description: "city to look up, e.g. heke1228",
        ptype: @toolbox.TString,
      },
    ],
    optional_parameters: [
      {
        name: "unit",
        description: "temperature unit",
        ptype: @toolbox.TEnum(["celsius", "fahrenheit"]),
      },
    ],
  }
}

///|
impl @toolbox.Tool for Weather with fn execute_raw(_, _args) {
  "{\"temp_c\": 23, \"sky\": \"clear\"}"
}

///|
/// Prompt to wire. Build a Koog prompt — a system instruction, a user turn, one
/// registered tool, and `LLMParams` that force that tool — then map it to the
/// Anthropic Messages request body and print the JSON that goes on the wire. No
/// LLM is called; this is the request half of a client, on its own.
///
///     moon run examples/01-prompt-to-wire --target native
#coverage.skip
fn main {
  let registry = @toolbox.ToolRegistry::new().add(Weather::{ })
  let params : @moonmuse.LLMParams = {
    ..@moonmuse.LLMParams::default(),
    temperature: Some(0.2),
    max_tokens: Some(1024),
    tool_choice: Some(@moonmuse.Named("weather")),
  }
  let prompt = @moonmuse.PromptBuilder::new()
    .system("You are a terse weather bot. Answer in one short sentence.")
    .user("what's the weather in heke1228 today?")
    .params(params)
    .build()
  let model = @models.claude_sonnet_4_5
  let wire = @anthropic.to_anthropic_request(prompt, model, registry.descriptors())
  println(
    "model \{model.id} - ToolChoice capable: \{model.supports(@models.ToolChoice)}",
  )
  println(wire.stringify())
}
