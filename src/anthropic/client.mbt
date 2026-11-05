// The Anthropic Messages API request format (POST /v1/messages) — the second wire format an
// agent framework must speak alongside OpenAI's chat completions. Anthropic differs in three
// ways this maps faithfully: the system prompt is a top-level `system` field (not a message),
// `max_tokens` is required, and tools carry an `input_schema` rather than `parameters`. This is
// the request half of a moonkoog Anthropic-compatible client.

///|
/// The role name Anthropic's Messages API uses; system messages are lifted out, so only user
/// and assistant appear in `messages`.
fn anthropic_role(r : @moonmuse.Role) -> String {
  match r {
    User => "user"
    Assistant => "assistant"
    System => "system"
  }
}

///|
/// The concatenated text of a message's `Text` parts.
fn anthropic_text(m : @moonmuse.Message) -> String {
  let sb = StringBuilder()
  for part in m.parts {
    match part {
      Text(t) => sb.write_string(t)
      _ => ()
    }
  }
  sb.to_string()
}

///|
/// Map a Koog tool descriptor to an Anthropic tool: `{name, description, input_schema}`, the
/// input_schema being the JSON Schema of the tool's parameters.
fn to_anthropic_tool(d : @toolbox.ToolDescriptor) -> Json {
  let properties : Map[String, Json] = Map([])
  let required : Array[Json] = []
  for p in d.required_parameters {
    properties[p.name] = p.ptype.to_json_schema()
    required.push(p.name.to_json())
  }
  for p in d.optional_parameters {
    properties[p.name] = p.ptype.to_json_schema()
  }
  Json::object({
    "name": Json::string(d.name),
    "description": Json::string(d.description),
    "input_schema": Json::object({
      "type": Json::string("object"),
      "properties": Json::object(properties),
      "required": Json::array(required),
    }),
  })
}

///|
/// Build an Anthropic Messages API request from a Koog prompt, model, and tools. System messages
/// are lifted to the top-level `system` field; `max_tokens` (required by Anthropic) comes from
/// the params, then the model's output limit, then a default of 4096.
pub fn to_anthropic_request(
  prompt : @moonmuse.Prompt,
  model : @models.LLModel,
  tools : Array[@toolbox.ToolDescriptor],
) -> Json {
  let mut system = ""
  let messages : Array[Json] = []
  for m in prompt.messages {
    match m.role {
      System => system = system + anthropic_text(m)
      _ =>
        messages.push(
          Json::object({
            "role": Json::string(anthropic_role(m.role)),
            "content": Json::string(anthropic_text(m)),
          }),
        )
    }
  }
  let max_tokens = match prompt.params.max_tokens {
    Some(n) => n
    None =>
      match model.max_output_tokens {
        Some(n) => n
        None => 4096
      }
  }
  let fields : Map[String, Json] = {
    "model": Json::string(model.id),
    "max_tokens": max_tokens.to_json(),
    "messages": Json::array(messages),
  }
  if system != "" {
    fields["system"] = Json::string(system)
  }
  match prompt.params.temperature {
    Some(t) => fields["temperature"] = t.to_json()
    None => ()
  }
  if tools.length() > 0 {
    let arr : Array[Json] = []
    for d in tools {
      arr.push(to_anthropic_tool(d))
    }
    fields["tools"] = Json::array(arr)
  }
  if prompt.params.tool_choice is Some(tc) {
    fields["tool_choice"] = anthropic_tool_choice(tc)
  }
  // Anthropic's Messages API has no `response_format`; structured output is coaxed via a forced
  // tool, so `params.schema` is left for that path rather than emitted here.
  Json::object(fields)
}

///|
/// Map a Koog tool-choice to Anthropic's `tool_choice` object: `{type: auto|any|tool, name?}`,
/// with `none` forbidding tools.
fn anthropic_tool_choice(tc : @moonmuse.ToolChoice) -> Json {
  match tc {
    Auto => Json::object({ "type": Json::string("auto") })
    NoTools => Json::object({ "type": Json::string("none") })
    Required => Json::object({ "type": Json::string("any") })
    Named(name) =>
      Json::object({ "type": Json::string("tool"), "name": Json::string(name) })
  }
}

///|
/// Parse an Anthropic Messages API response into a Koog assistant message: each `text` content
/// block becomes a `Text` part, each `tool_use` block a `ToolCall` (its `input` the arguments),
/// `stop_reason` the finish reason, and `usage` the reply's token counts.
pub fn from_anthropic_response(response : Json) -> @moonmuse.Message {
  let parts : Array[@moonmuse.MessagePart] = []
  let mut finish : String? = None
  let mut meta = @moonmuse.ResponseMetaInfo::empty()
  match response {
    Object(obj) => {
      match obj.get("content") {
        Some(Array(blocks)) =>
          for block in blocks {
            match block {
              Object(b) => {
                let btype = match b.get("type") {
                  Some(String(t)) => t
                  _ => ""
                }
                if btype == "text" {
                  match b.get("text") {
                    Some(String(t)) => parts.push(Text(t))
                    _ => ()
                  }
                } else if btype == "tool_use" {
                  let id = match b.get("id") {
                    Some(String(i)) => Some(i)
                    _ => None
                  }
                  let name = match b.get("name") {
                    Some(String(n)) => n
                    _ => ""
                  }
                  let input = match b.get("input") {
                    Some(v) => v
                    None => Json::object({})
                  }
                  parts.push(ToolCall(id~, tool=name, args=input))
                }
              }
              _ => ()
            }
          }
        _ => ()
      }
      match obj.get("stop_reason") {
        Some(String(s)) => finish = Some(s)
        _ => ()
      }
      meta = anthropic_meta(obj)
    }
    _ => ()
  }
  { role: Assistant, parts, finish_reason: finish, meta: Some(meta), }
}

///|
/// The tokens an Anthropic response reports. Its `usage` names the two counts separately and
/// gives no total, so the total is their sum — and only when both were reported, since a
/// half-known total would be read as the whole cost.
fn anthropic_meta(obj : Map[String, Json]) -> @moonmuse.ResponseMetaInfo {
  let model = match obj.get("model") {
    Some(String(m)) => Some(m)
    _ => None
  }
  let usage = match obj.get("usage") {
    Some(Object(u)) => u
    _ => return { ..@moonmuse.ResponseMetaInfo::empty(), model, }
  }
  let count = key => {
    match usage.get(key) {
      Some(Number(n, ..)) => Some(n.to_int())
      _ => None
    }
  }
  let input_tokens = count("input_tokens")
  let output_tokens = count("output_tokens")
  let total_tokens = match (input_tokens, output_tokens) {
    (Some(i), Some(o)) => Some(i + o)
    _ => None
  }
  { total_tokens, input_tokens, output_tokens, model, }
}

///|
/// An Anthropic Messages API client (Koog `AnthropicLLMClient`) — the second wire format alongside
/// the OpenAI-compatible client. It implements moonkoog's `LLMClient` by mapping Koog's
/// prompt/message/tool model onto the Anthropic request/response JSON (`to_anthropic_request` /
/// `from_anthropic_response`) and POSTing to `/messages`; moonllm carries the HTTPS transport,
/// configured for Anthropic's `x-api-key` auth and required `anthropic-version` header.
/// Source: prompt/.../clients/anthropic/AnthropicLLMClient.kt.
pub struct AnthropicClient {
  inner : @moonllm.Client
}

///|
/// Build a client for the Anthropic Messages API, authenticating with `api_key` via `x-api-key`
/// and sending the `anthropic-version`. `base_url` defaults to Anthropic's public API; point it at
/// a compatible gateway to override.
pub fn AnthropicClient::new(
  api_key~ : String,
  base_url~ : String = "https://api.anthropic.com/v1",
  version~ : String = "2023-06-01",
  timeout_ms~ : Int32 = 60000,
) -> AnthropicClient {
  let inner = @moonllm.ClientBuilder::new()
    .api_key(api_key)
    .base_url(base_url)
    .anthropic(version~)
    .timeout_ms(timeout_ms)
    .build()
  { inner, }
}

///|
pub impl @moonmuse.LLMClient for AnthropicClient with fn execute(
  self,
  prompt~,
  model~,
  tools~,
) {
  let body = to_anthropic_request(prompt, model, tools)
  let response = self.inner.post_json("/messages", body)
  from_anthropic_response(response)
}

///|
pub impl @moonmuse.LLMClient for AnthropicClient with fn provider(self) {
  let _ = self
  @models.anthropic
}

///|
/// Anthropic exposes no standalone moderation endpoint (unlike OpenAI's `/moderations`), so this
/// honours the moderation contract by reporting nothing harmful; callers needing real moderation
/// route it through a provider that offers it.
pub impl @moonmuse.LLMClient for AnthropicClient with fn moderate(
  self,
  prompt~,
  model~,
) {
  let _ = self
  let _ = prompt
  let _ = model
  @moonmuse.ModerationResult::safe()
}

///|
/// The Anthropic Messages API returns a single completion (there is no `n`), so multiple choices
/// collapse to a single-element list.
pub impl @moonmuse.LLMClient for AnthropicClient with fn execute_multiple(
  self,
  prompt~,
  model~,
  tools~,
) {
  [self.execute(prompt~, model~, tools~)]
}

///|
pub extend AnthropicClient with @moonmuse.LLMClient::{
  execute,
  provider,
  execute_streaming,
  moderate,
  execute_multiple,
}
