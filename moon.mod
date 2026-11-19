name = "moonbitstack/moonmuse"

version = "0.2.1"

readme = "README.md"

repository = "https://github.com/moonbitstack/moonmuse"

license = "Apache-2.0"

keywords = [
  "llm",
  "ai",
  "genai",
  "provider",
  "gateway",
  "openai",
  "anthropic",
  "gemini",
  "google",
  "claude",
  "ollama",
  "deepseek",
  "kimi",
  "qwen",
  "vllm",
  "openrouter",
  "mistral",
  "dashscope",
  "chat",
  "completion",
  "chat-completions",
  "responses",
  "streaming",
  "sse",
  "server-sent-events",
  "ndjson",
  "tool-calling",
  "function-calling",
  "structured-output",
  "json-schema",
  "embeddings",
  "retry",
  "fallback",
  "rate-limit",
  "cache",
  "routing",
  "prompt",
  "template",
  "client",
  "server",
  "asgi",
  "bedrock",
  "aws",
  "sigv4",
  "opentelemetry",
  "otel",
  "tracing",
  "metrics",
  "prometheus",
  "observability",
  "tokenizer",
  "tiktoken",
  "count-tokens",
  "audio",
  "transcription",
  "moonbit",
]

description = "Talk to language models from MoonBit: one contract for chat, streaming, tools and embeddings, with a subpackage per wire format."

source = "src"

import {
  "moonbitlang/async@0.22.5",
  "moonbitstack/moonfetch@0.2.1",
  "moonbitstack/moonhttp@0.16.1",
  "moonbitstack/moonasgi@0.11.3",
  "moonbitstack/moonjson@0.5.1",
  "moonbitstack/moonschema@0.3.1",
  "moonbitstack/moonpug@0.2.1",
  "moonbitstack/mooncat@0.21.1",
  "moonbitstack/mooncrypt@0.5.2",
  "moonbitstack/moontel@0.2.3",
  "moonbitstack/moontoken@0.2.1",
  "moonbitstack/moonnet@0.2.2",
}
