name = "moonbitstack/moonmuse"

version = "0.1.0"

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
  "moonbit",
]

description = "Talk to language models from MoonBit: one contract for chat, streaming, tools and embeddings, with a subpackage per wire format."

source = "src"

import {
  "moonbitlang/async@0.22.5",
  "moonbitstack/moonfetch@0.1.5",
  "moonbitstack/moonasgi@0.10.6",
  "moonbitstack/moonschema@0.2.4",
  "moonbitstack/moonpug@0.1.4",
}
