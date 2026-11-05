# Examples

| # | Example | What it shows |
|:--:|:--|:--|
| 01 | [`prompt-to-wire`](01-prompt-to-wire/) | Build a prompt (system + user), register a tool, force it with `LLMParams.tool_choice`, and map the whole request to the Anthropic Messages body — the request half of a client, `to_anthropic_request`, on its own |
| 02 | [`prompt-model`](02-prompt-model/) | The prompt/message model itself: a multi-turn `PromptBuilder`, the four `MessagePart` kinds, `text_content`/`tool_calls`, non-mutating `append`, and the `ToJson` wire form of messages and `LLMParams` |
| 03 | [`model-catalog`](03-model-catalog/) | The `LLMProvider` list and `LLModel` catalog — context windows, the per-provider `*_models()` lists, and `LLModel::supports` over the `LLMCapability` set (tools, tool-choice, vision, thinking, embed, moderation) |
| 04 | [`tool-schema`](04-tool-schema/) | The tool/registry model: every `ToolParameterType` variant (including `TObject`/`TList`/`TAnyOf`/`TEnum`) rendered by `to_json_schema`, a `ToolDescriptor` composed into one schema, and `ToolRegistry` add/descriptors/get_tool |
| 05 | [`anthropic-response`](05-anthropic-response/) | The response half of the client: `from_anthropic_response` maps a Messages reply (text + `tool_use`) back into a Koog message, and the `AnthropicClient`/`OpenAiCompatibleClient` report their provider |
| 06 | [`structured-output`](06-structured-output/) | `request_structured`: ask the model for a value matching a `StructuredSchema`, extract the JSON from prose or a code fence, parse it, and re-prompt on malformed output |
| 07 | [`client-wrappers`](07-client-wrappers/) | The `LLMClient` wrappers: `CachingClient` (served-from-cache), `RetryingClient` (transient retry), `MultiLLMClient` (provider routing + fallback), and the default `execute_streaming` single-chunk contract |
| 08 | [`moderation`](08-moderation/) | `LLMClient.moderate`: the default reports nothing harmful; a moderation-capable client returns a `ModerationResult` whose per-category flags `is_category_detected` queries |
