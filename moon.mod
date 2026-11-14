name = "moonbitstack/moonmuse"

version = "0.2.0"

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
  "moonbitstack/moonfetch@0.2.0",
  "moonbitstack/moonhttp@0.16.0",
  "moonbitstack/moonasgi@0.11.2",
  "moonbitstack/moonjson@0.5.0",
  "moonbitstack/moonschema@0.2.5",
  "moonbitstack/moonpug@0.2.0",
  "moonbitstack/mooncat@0.20.0",
  "moonbitstack/mooncrypt@0.5.0",
  "moonbitstack/moontel@0.2.1",
  "moonbitstack/moontoken@0.2.0",
  "moonbitstack/moonnet@0.2.0",
}
