name = "moonbitstack/moonmuse"

version = "0.1.1"

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
  "moonbitstack/moonfetch@0.1.8",
  "moonbitstack/moonhttp@0.15.10",
  "moonbitstack/moonasgi@0.10.8",
  "moonbitstack/moonjson@0.5.0",
  "moonbitstack/moonschema@0.2.5",
  "moonbitstack/moonpug@0.1.5",
  "moonbitstack/mooncat@0.19.8",
  "moonbitstack/mooncrypt@0.4.15",
  "moonbitstack/moonp8s@0.1.2",
  "moonbitstack/moontel@0.1.2",
  "moonbitstack/moontoken@0.1.3",
  "moonbitstack/moonnet@0.1.12",
}
