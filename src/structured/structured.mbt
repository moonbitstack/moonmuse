///|
/// Structured LLM output: constrain the model to reply with a JSON object that
/// matches a schema, parse it into a value, and re-prompt to fix a malformed
/// reply. Koog's `requestLLMStructured` + `StructureFixingParser`. Koog derives
/// the schema and deserializer from the Kotlin type via kotlinx.serialization;
/// MoonBit has no reflection, so the caller states the schema (a
/// `@toolbox.ToolParameterType`, usually a `TObject`) and supplies the `parse` that
/// turns the model's JSON into `T` — the same explicit shape a tool takes for its
/// descriptor plus `decodeArgs`.
/// Source: prompt/prompt-structure/.../StructuredRequest.kt and
/// agents/.../StructureFixingParser.kt.

///|
/// A structured-response request: the schema the reply must match and the parser
/// that turns its JSON into a `T`.
pub(all) struct StructuredSchema[T] {
  name : String
  description : String
  schema : @toolbox.ToolParameterType
  parse : (Json) -> T?
}

///|
/// A structured request's result: the parsed value and the raw model text it came
/// from.
pub(all) struct StructuredResponse[T] {
  value : T
  raw : String
}

///|
/// Pull the first brace-balanced JSON object out of `text`, tolerating code fences
/// or surrounding prose (models rarely emit a bare object). Scans respecting string
/// literals and escapes; `None` if there is no balanced `{...}`.
fn extract_json_object(text : String) -> String? {
  let n = text.length()
  let mut start = -1
  for i = 0; i < n; i = i + 1 {
    if text[i].to_int() == '{'.to_int() {
      start = i
      break
    }
  }
  guard start >= 0 else { return None }
  let mut depth = 0
  let mut in_string = false
  let mut escaped = false
  for i = start; i < n; i = i + 1 {
    let c = text[i].to_int()
    if in_string {
      if escaped {
        escaped = false
      } else if c == '\\'.to_int() {
        escaped = true
      } else if c == '"'.to_int() {
        in_string = false
      }
    } else if c == '"'.to_int() {
      in_string = true
    } else if c == '{'.to_int() {
      depth = depth + 1
    } else if c == '}'.to_int() {
      depth = depth - 1
      if depth == 0 {
        return Some(text[start:i + 1].to_owned())
      }
    }
  }
  None
}

///|
/// The instruction that pins a reply to `schema`'s JSON shape — shared by the agent-level
/// request and by the graph's structured node.
fn[T] schema_instruction(schema : StructuredSchema[T]) -> String {
  "Respond with a single JSON object and nothing else — no prose, no code fences. It must match this JSON schema for \"" +
  schema.name +
  "\" (" +
  schema.description +
  "): " +
  schema.schema.to_json_schema().stringify()
}

///|
/// What a malformed reply is answered with before asking again (Koog's
/// `StructureFixingParser`).
let fix_instruction : String = "That was not a valid JSON object matching the schema. Respond again with only the JSON object."

///|
/// `params` with `schema` set as the provider's own structured-output format, in the richest
/// dialect the model declares — Koog's native structured output, which a client turns into an
/// OpenAI `response_format` (see `to_llm_response_format`). A model declaring neither JSON-schema
/// capability is left alone: for it the schema instruction in the prompt is the whole mechanism,
/// which is Koog's manual mode.
fn[T] with_schema(
  params : @moonmuse.LLMParams,
  model : @models.LLModel,
  schema : StructuredSchema[T],
) -> @moonmuse.LLMParams {
  let json = schema.schema.to_json_schema()
  if model.supports(SchemaJsonStandard) {
    { ..params, schema: Some(JsonStandard(name=schema.name, schema=json)), }
  } else if model.supports(SchemaJsonBasic) {
    { ..params, schema: Some(JsonBasic(name=schema.name, schema=json)), }
  } else {
    params
  }
}

///|
/// Request a structured response to `input`, retrying up to `max_fixes` times when
/// the reply does not parse. Asks through the provider's own structured-output format when
/// the model declares a JSON-schema capability, and states the schema in the prompt as well,
/// so a provider that ignores `response_format` still has the shape in front of it. On each
/// malformed reply it appends the bad output and a fixing instruction and asks again — Koog's
/// `StructureFixingParser`. Raises `AgentError` if no reply parses within the budget.
pub async fn[T] AIAgent::request_structured(
  self : AIAgent,
  input : String,
  schema : StructuredSchema[T],
  max_fixes~ : Int32 = 2,
) -> StructuredResponse[T] {
  let builder = @moonmuse.PromptBuilder::new(
    params=with_schema(self.params, self.model, schema),
  )
  if self.system_prompt is Some(sp) {
    builder.system(sp) |> ignore
  }
  builder.system(schema_instruction(schema)).user(input) |> ignore
  let mut prompt = builder.build()
  let descriptors = self.tool_registry.descriptors()
  for _attempt = 0; _attempt <= max_fixes; _attempt = _attempt + 1 {
    let reply = self.executor.execute(
      prompt~,
      model=self.model,
      tools=descriptors,
    )
    let text = reply.text_content()
    let parsed = if extract_json_object(text) is Some(js) {
      (schema.parse)(@json.parse(js) catch { _ => Json::null() })
    } else {
      None
    }
    if parsed is Some(value) {
      return { value, raw: text, }
    }
    prompt = prompt.append(reply)
    prompt = prompt.append(@moonmuse.Message::user(fix_instruction))
  }
  raise AgentError(
    "no valid structured response after " +
    (max_fixes + 1).to_string() +
    " attempts",
  )
}
