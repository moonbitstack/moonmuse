///|
/// An OpenAI-compatible LLM client (Koog `OpenAILLMClient` and its provider
/// siblings). It implements moonkoog's `LLMClient` by mapping Koog's
/// prompt/message/tool model onto moonllm's request/response types and back;
/// moonllm carries the actual HTTPS transport. One client talks to any
/// OpenAI-compatible endpoint by its `base_url`.
/// Source: prompt/prompt-executor/prompt-executor-clients/prompt-executor-openai-client/.../OpenAILLMClient.kt.
pub struct OpenAiCompatibleClient {
  inner : @moonllm.Client
  its_provider : @models.LLMProvider
}

///|
/// Build a client for `base_url`, authenticating with a bearer `api_key`.
pub fn OpenAiCompatibleClient::new(
  api_key~ : String,
  base_url~ : String,
  provider~ : @models.LLMProvider,
  timeout_ms~ : Int32 = 60000,
) -> OpenAiCompatibleClient {
  {
    inner: @moonllm.Client::new(api_key, base_url~, timeout_ms~),
    its_provider: provider,
  }
}

///|
pub impl @moonmuse.LLMClient for OpenAiCompatibleClient with fn execute(
  self,
  prompt~,
  model~,
  tools~,
) {
  let request = to_chat_request(prompt, model, tools)
  let response = self.inner.chat(request)
  from_chat_response(response)
}

///|
/// Stream the OpenAI-compatible chat completion (Koog `OpenAILLMClient.executeStreaming`):
/// send with `stream: true`, invoke `on_chunk` for each `text_delta` off the SSE feed, and
/// assemble the full reply (text plus any streamed tool calls) once the stream ends.
pub impl @moonmuse.LLMClient for OpenAiCompatibleClient with fn execute_streaming(
  self,
  prompt~,
  model~,
  tools~,
  on_chunk~,
) {
  let request = to_chat_request(prompt, model, tools)
  let result = self.inner.chat_stream_full(request, chunk => {
    if chunk.content is Some(text) {
      on_chunk(text)
    }
  })
  let parts : Array[@moonmuse.MessagePart] = []
  if result.content != "" {
    parts.push(Text(result.content))
  }
  for tc in result.tool_calls {
    parts.push(
      ToolCall(
        id=Some(tc.id),
        tool=tc.function.name,
        args=parse_json(tc.function.arguments),
      ),
    )
  }
  // A streamed completion carries no `usage` on the SSE feed moonllm reassembles, so the
  // reply's meta stays unset rather than guessed at.
  { role: Assistant, parts, finish_reason: result.finish_reason, meta: None, }
}

///|
pub impl @moonmuse.LLMClient for OpenAiCompatibleClient with fn provider(self) {
  self.its_provider
}

///|
/// Moderate the prompt through the OpenAI-compatible `/moderations` endpoint (Koog
/// `OpenAILLMClient.moderate`): the prompt's text is sent to the moderation model and the returned
/// per-category flags and confidence scores are mapped back to a Koog `ModerationResult`.
pub impl @moonmuse.LLMClient for OpenAiCompatibleClient with fn moderate(
  self,
  prompt~,
  model~,
) {
  let request = @moonllm.ModerationRequest::of_text(moderation_input(prompt)).model(
    model.id,
  )
  let response = self.inner.moderations(request)
  from_moderation_response(response)
}

///|
/// The text a prompt contributes to moderation: every message's `Text` parts, newline-joined.
fn moderation_input(prompt : @moonmuse.Prompt) -> String {
  let sb = StringBuilder()
  let mut first = true
  for m in prompt.messages {
    for part in m.parts {
      if part is Text(t) {
        if !first {
          sb.write_string("\n")
        }
        sb.write_string(t)
        first = false
      }
    }
  }
  sb.to_string()
}

///|
/// Map a moonllm moderation response (the first result) to a Koog `ModerationResult`: the input's
/// `flagged` becomes `is_harmful`, and each category's flag pairs with its confidence score.
fn from_moderation_response(
  resp : @moonllm.ModerationResponse,
) -> @moonmuse.ModerationResult {
  guard resp.results.length() > 0 else { @moonmuse.ModerationResult::safe() }
  let r = resp.results[0]
  let categories : Map[String, @moonmuse.ModerationCategoryResult] = Map([])
  for name, detected in r.categories {
    categories[name] = {
      detected,
      confidence_score: r.category_scores.get(name),
    }
  }
  { is_harmful: r.flagged, categories, }
}

///|
/// Map a Koog prompt + model + tool descriptors to a moonllm chat request.
fn to_chat_request(
  prompt : @moonmuse.Prompt,
  model : @models.LLModel,
  tools : Array[@toolbox.ToolDescriptor],
) -> @moonllm.ChatRequest {
  let messages = []
  for m in prompt.messages {
    messages.push(to_llm_message(m))
  }
  let request = @moonllm.ChatRequest::new(model.id, messages)
  if !tools.is_empty() {
    let llm_tools = []
    for d in tools {
      llm_tools.push(to_llm_tool(d))
    }
    request.tools(llm_tools) |> ignore
  }
  if prompt.params.temperature is Some(t) {
    request.temperature(t) |> ignore
  }
  if prompt.params.max_tokens is Some(n) {
    request.max_tokens(n) |> ignore
  }
  if prompt.params.tool_choice is Some(tc) {
    request.tool_choice(to_llm_tool_choice(tc)) |> ignore
  }
  if prompt.params.schema is Some(s) {
    request.response_format(to_llm_response_format(s)) |> ignore
  }
  request
}

///|
/// Map a Koog tool-choice to moonllm's OpenAI `tool_choice` shape (`auto`/`none`/`required`/
/// `{type:function,function:{name}}`).
fn to_llm_tool_choice(tc : @moonmuse.ToolChoice) -> @moonllm.ToolChoice {
  match tc {
    Auto => @moonllm.Auto
    NoTools => @moonllm.NoneChoice
    Required => @moonllm.Required
    Named(name) => @moonllm.Function(name)
  }
}

///|
/// Map a Koog structured-output schema to an OpenAI `response_format` (`json_schema`); both Koog
/// dialects collapse onto OpenAI's single json_schema form.
fn to_llm_response_format(s : @moonmuse.Schema) -> @moonllm.ResponseFormat {
  match s {
    JsonBasic(name~, schema~) => @moonllm.JsonSchema(name~, schema~)
    JsonStandard(name~, schema~) => @moonllm.JsonSchema(name~, schema~)
  }
}

///|
/// Map a Koog message to a moonllm message. A message carrying a tool result
/// becomes a `tool`-role message linked by `tool_call_id`; a message carrying
/// tool calls becomes an assistant message with `tool_calls`; otherwise it is a
/// plain text message in its role.
fn to_llm_message(m : @moonmuse.Message) -> @moonllm.Message {
  let role = match m.role {
    System => @moonllm.System
    User => @moonllm.User
    Assistant => @moonllm.Assistant
  }
  let mut text = ""
  let tool_calls : Array[@moonllm.ToolCall] = []
  let mut result_id : String? = None
  let mut is_result = false
  for part in m.parts {
    match part {
      Text(t) => text = text + t
      Reasoning(_) => ()
      ToolResult(id~, output~, ..) => {
        text = output
        result_id = id
        is_result = true
      }
      ToolCall(id~, tool~, args~) =>
        tool_calls.push({
          id: id.unwrap_or(""),
          function: { name: tool, arguments: args.stringify(), },
        })
    }
  }
  if is_result {
    {
      role: @moonllm.Tool,
      content: Str(text),
      tool_calls: None,
      tool_call_id: result_id,
      name: None,
    }
  } else if !tool_calls.is_empty() {
    {
      role,
      content: Str(text),
      tool_calls: Some(tool_calls),
      tool_call_id: None,
      name: None,
    }
  } else {
    {
      role,
      content: Str(text),
      tool_calls: None,
      tool_call_id: None,
      name: None,
    }
  }
}

///|
/// Map a Koog tool descriptor to a moonllm tool: a JSON-schema `parameters`
/// object built from the required / optional parameter lists.
fn to_llm_tool(d : @toolbox.ToolDescriptor) -> @moonllm.Tool {
  let properties : Map[String, Json] = Map([])
  let required : Array[Json] = []
  for p in d.required_parameters {
    properties[p.name] = param_schema(p.ptype)
    required.push(p.name.to_json())
  }
  for p in d.optional_parameters {
    properties[p.name] = param_schema(p.ptype)
  }
  {
    name: d.name,
    description: d.description,
    parameters: Json::object({
      "type": Json::string("object"),
      "properties": Json::object(properties),
      "required": Json::array(required),
    }),
  }
}

///|
/// The JSON Schema for one tool-parameter type — rendered by `@tools`, the shared
/// home for the schema model.
fn param_schema(t : @toolbox.ToolParameterType) -> Json {
  t.to_json_schema()
}

///|
/// Request `number_of_choices` completions (Koog `executeMultipleChoices`) and map each returned
/// choice to a Koog message. The count comes from the prompt's params (default 1); OpenAI-compatible
/// endpoints carry it as the `n` field.
pub impl @moonmuse.LLMClient for OpenAiCompatibleClient with fn execute_multiple(
  self,
  prompt~,
  model~,
  tools~,
) {
  let request = to_chat_request(prompt, model, tools)
  let count = prompt.params.number_of_choices.unwrap_or(1)
  if count > 1 {
    request.n(count) |> ignore
  }
  from_chat_response_all(self.inner.chat(request))
}

///|
/// What the provider reported about the call: the `usage` object an OpenAI-compatible
/// endpoint returns beside the choices, and the model id that served the request. A
/// response without `usage` leaves the counts unset — zero would claim the call was free.
fn response_meta(resp : @moonllm.ChatResponse) -> @moonmuse.ResponseMetaInfo {
  let model = if resp.model == "" { None } else { Some(resp.model) }
  match resp.usage {
    Some(u) =>
      {
        total_tokens: Some(u.total_tokens),
        input_tokens: Some(u.prompt_tokens),
        output_tokens: Some(u.completion_tokens),
        model,
      }
    None => { ..@moonmuse.ResponseMetaInfo::empty(), model, }
  }
}

///|
/// Map every choice of a moonllm chat response to a Koog assistant message (Koog
/// `executeMultipleChoices` returns one per choice). The usage is reported per response,
/// not per choice, so every candidate carries the same meta.
fn from_chat_response_all(
  resp : @moonllm.ChatResponse,
) -> Array[@moonmuse.Message] {
  let meta = response_meta(resp)
  let out : Array[@moonmuse.Message] = []
  for choice in resp.choices {
    out.push(
      from_llm_message(choice.message, choice.finish_reason).with_meta(meta),
    )
  }
  out
}

///|
/// Map a moonllm chat response to a Koog assistant message (the first choice), carrying the
/// tokens the provider charged.
fn from_chat_response(resp : @moonllm.ChatResponse) -> @moonmuse.Message {
  let meta = response_meta(resp)
  guard resp.choices.length() > 0 else {
    { role: Assistant, parts: [], finish_reason: None, meta: Some(meta), }
  }
  let choice = resp.choices[0]
  from_llm_message(choice.message, choice.finish_reason).with_meta(meta)
}

///|
/// Map a moonllm message to a Koog message: its text becomes a `Text` part, each
/// returned tool call becomes a `ToolCall` part (its JSON arguments re-parsed).
fn from_llm_message(
  msg : @moonllm.Message,
  finish_reason : String?,
) -> @moonmuse.Message {
  let parts : Array[@moonmuse.MessagePart] = []
  let text = msg.content.to_text()
  if text != "" {
    parts.push(Text(text))
  }
  if msg.tool_calls is Some(tcs) {
    for tc in tcs {
      parts.push(
        ToolCall(
          id=Some(tc.id),
          tool=tc.function.name,
          args=parse_json(tc.function.arguments),
        ),
      )
    }
  }
  { role: Assistant, parts, finish_reason, meta: None, }
}

///|
/// Parse a JSON string, or an empty object if it does not parse.
fn parse_json(s : String) -> Json {
  @json.parse(s) catch {
    _ => Json::object({})
  }
}

///|
pub extend OpenAiCompatibleClient with @moonmuse.LLMClient::{
  execute,
  provider,
  execute_streaming,
  moderate,
  execute_multiple,
}
