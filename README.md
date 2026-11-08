<div align="center">

# moonmuse

**One contract for every language model: chat, streaming, tools and embeddings.**

[![mooncakes](https://img.shields.io/badge/mooncakes-moonbitstack%2Fmoonmuse-2f6f4e)](https://mooncakes.io/docs/moonbitstack/moonmuse)
[![license](https://img.shields.io/badge/license-Apache--2.0-2f6f4e)](LICENSE)

</div>

**[A field-by-field comparison of the four API specs →](https://moonbitstack.github.io/moonmuse/)**
— the same request as OpenAI, Anthropic, Gemini and Ollama each put it on the wire.

A model endpoint is a request and an answer. Which vendor answers it, whether it runs in a
data centre or on the laptop, and whether the caller speaks OpenAI's JSON or Anthropic's is a
detail of the wire — not of the code that asks. This library puts that detail in one place and
leaves one contract above it.

```mbt native
let provider : &@moonmuse.Provider = @openai.Client::new(api_key="sk-test")
let request = @moonmuse.Request::new(
  "gpt-4o-mini",
  [@moonmuse.Message::user("Why is the sky blue?")],
  temperature=0.2,
  max_tokens=256,
)
let reply = provider.chat(request)
let answer = reply.text()
```

Swap the constructor for `@anthropic.Client::new(...)`, `@gemini.Client::new(...)` or
`@ollama.Client::new()` and nothing below that line changes.

## Install

```bash
moon add moonbitstack/moonmuse
```

## The two contracts

| Contract | What it is | Who implements it |
|:--|:--|:--|
| `Provider` | Ask for an answer, a stream, vectors, or the model list. | `@openai`, `@anthropic`, `@gemini`, `@ollama`, `@fake`, every layer, your own |
| `Dialect` | One vendor's wire format, read **and** written. | The four provider packages, your own |

A `Dialect` is the reason a gateway and a client cannot disagree: the same value turns a
`Request` into an HTTP call on the way out and a served body into a `Request` on the way in.

## Packages

| Package | What it adds |
|:--|:--|
| `moonmuse` | Messages, requests, replies, the two contracts, the server-sent-events reader |
| `moonmuse/openai` | OpenAI's format, plus every endpoint that speaks it — DeepSeek, Kimi, Qwen, vLLM, OpenRouter, DashScope, Mistral — and the Responses, moderation, image, file, batch, fine-tuning and audio calls |
| `moonmuse/anthropic` | The Messages API, its event stream, and its token counter |
| `moonmuse/gemini` | `generateContent`, `streamGenerateContent`, `embedContent` |
| `moonmuse/ollama` | The native `/api` endpoints, including the newline-delimited stream |
| `moonmuse/layers` | Retry, fallback, rate limiting, caching, routing — each a provider around a provider |
| `moonmuse/toolbox` | Tool execution and the tool loop |
| `moonmuse/models` | Context windows, output limits, list prices, capabilities |
| `moonmuse/structured` | Ask for a JSON answer that fits a schema, with a repair loop |
| `moonmuse/prompt` | Prompt templates, rendered by moonpug |
| `moonmuse/fake` | A scripted provider, for tests of everything above the wire |
| `moonmuse/serve` | Export any provider as an OpenAI, Anthropic, Gemini or Ollama API |
| `moonmuse/local` | A local model as a provider: chat template, tool-call parsing, an engine contract |
| `moonmuse/count` | Token counting over a moontoken vocabulary, for `count_tokens` |
| `moonmuse/otel` | Traces and metrics by the OpenTelemetry GenAI conventions |

## Chat

`Request.extra` is merged into the body last, so a vendor's own field — `reasoning_effort`, a
beta switch — reaches the wire without this library modelling it. `Reply.raw` keeps the body
that came back for the fields the shared vocabulary does not hold.

```mbt native
let with_system = @moonmuse.Request::new(
  "claude-sonnet-4-20250514",
  [
    @moonmuse.Message::system("Answer in one sentence."),
    @moonmuse.Message::user("Why is the sky blue?"),
  ],
  stop=["\n\n"],
)
let priced = @models.estimate_cost("claude-sonnet-4-20250514", reply.usage)
```

## Streaming

`stream` calls the callback for each delta as it arrives off the socket, and returns the reply
the events assemble — the same value `chat` returns, so a caller that ignores the deltas still
gets the whole answer. The text of a character split across two reads is held back until its
remaining bytes arrive, so a callback never sees half of one.

```mbt native
let streamed = provider.stream(request, delta => {
  match delta {
    @moonmuse.Text(chunk) => println(chunk)
    @moonmuse.CallStart(name~, ..) => println("call " + name)
    @moonmuse.CallArgs(chunk~, ..) => println(chunk)
    @moonmuse.Done(_) => println("")
  }
})
```

Each format streams from its own place: OpenAI's and Anthropic's bodies carry a `stream` flag,
Ollama's answer is newline-delimited, and Gemini streams from `:streamGenerateContent` with
`alt=sse`. A gateway in front of any of them passes each event on as it arrives.

## Tools

A tool is a schema plus a function. `Toolbox::call` is the only place a call becomes a result,
so a framework with its own loop uses it directly and gets the same behaviour — including the
rule that a failing tool produces an error result rather than an exception.

```mbt native
let tools = @toolbox.Toolbox::new()
tools.add(@moonmuse.Tool::new("add", "Add two integers"), args => {
  let a = @moonmuse.json_int(args, "a").unwrap_or(0)
  let b = @moonmuse.json_int(args, "b").unwrap_or(0)
  (a + b).to_string()
})
let looped = @toolbox.run(provider, request, tools, limit=10)
```

## Layers

Every layer is a `Provider`, so they compose in any order. Retry honours `retry-after` and only
retries failures that could pass on a second try; fallback switches on the same classification;
the cache key covers every field that decides an answer.

```mbt native
let secondary : &@moonmuse.Provider = @ollama.Client::new()
let gateway = @layers.cached(
  @layers.retry(@layers.fallback([provider, secondary])),
  @layers.Memory::new(limit=512),
)
let served = gateway.chat(request)
```

`@layers.routed({"claude-": provider, "local/": secondary})` picks a provider by a model-name
prefix instead, which is what a gateway over several vendors is.

## Structured output

The schema is stated in the prompt and the reply is checked against it with moonschema; a reply
that does not fit goes back with the reason, up to a budget, and the last failure is raised.

```mbt native
let weather = @moonmuse.parse_json_lossy(
  "{\"type\":\"object\",\"properties\":{\"celsius\":{\"type\":\"number\"}}}",
)
let celsius = @structured.ask(
  provider,
  request,
  name="weather",
  schema=weather,
  decode=json => @moonmuse.json_int(json, "celsius"),
)
```

## Serve

`serve` returns an `AsgiApp`: run it with any ASGI server, or mount it under a framework. The
endpoints are the dialects' own, so a format added once is served, called and parsed by the
same code.

```mbt native
let app = @serve.serve(
  provider,
  dialects=[@openai.dialect, @anthropic.dialect, @gemini.dialect, @ollama.dialect],
  keys=@serve.StaticKeys::new(["sk-local"]),
)
```

| Format | Endpoints |
|:--|:--|
| OpenAI | `/v1/chat/completions`, `/v1/completions`, `/v1/responses`, `/v1/embeddings`, `/v1/models` |
| Anthropic | `/v1/messages`, `/v1/messages/count_tokens`, `/v1/models` |
| Ollama | `/api/chat`, `/api/generate`, `/api/embed`, `/api/tags`, `/api/show`, `/api/version` |
| Gemini | `/v1beta/models/*:generateContent`, `:streamGenerateContent`, `:embedContent`, `:batchEmbedContents` |

Two formats claim `/v1/models`; the `anthropic-version` header decides which answers.
`count_tokens` needs a vocabulary, which is one argument away:

<!-- nocheck -->
```mbt native
let ranks = @vocab.Ranks::from_tiktoken(vocabulary_text)   // a tiktoken table, read once
let tokenizer = @moontoken.Tokenizer::cl100k(ranks~)
let counted = @serve.serve(provider, dialects=[@anthropic.dialect], counter=@count.Tokens::new(tokenizer~))
```

## Local models

A local model is an inference engine plus the text format it was trained on. The engine is a
contract here, so `moonmuse/local` does not know how weights are read; the format is data.

```mbt native
struct Echo {
}

impl @local.Engine for Echo with fn generate(_self, prompt, _limit) {
  prompt
}

pub extend Echo with @local.Engine::{generate}
```

```mbt native
let local : &@moonmuse.Provider = @local.Local::new(
  Echo::{},
  template=@local.llama3(),
  calls=@local.Tagged,
  model="qwen2.5-7b",
)
let answered = local.chat(request)
```

The answer is text, and a tool call is a JSON object inside it, so `@local.parse` finds the
calls, removes them from what the user sees, and numbers them. A template that does not render
is an error, not a silent empty prompt.

## Observation

`moonmuse/otel` wraps a provider: one client span per call, named after the operation and the
model, carrying what was asked and what came back, plus duration and token metrics. The
attribute and instrument names come from `moontel/semconv`, generated from a pinned upstream
commit, so a backend matches on the same keys it matches for any other client.

```mbt native
let recorder = @trace.Recorder::new()
let rand = width => Bytes::make(width, b'\x01')
let tracer = @trace.Tracer::new(
  rand~,
  sink=recorder,
  sampler=@trace.parent_based(root=@trace.always),
)
let observed = @otel.traced(provider, tracer)
let measured = @otel.metered(provider, @moonp8s.Registry::new())
```

Message bodies are not recorded unless `content=true` is passed: a trace list is a place data
leaks from, and the convention makes the same distinction.

## Binary endpoints

Speech, transcription and file upload travel as bytes or as multipart forms, not as JSON, so
they are methods on the client rather than part of `Provider`. `Call` carries a payload for the
same reason, which is how an endpoint this library has no method for is still reachable.

```mbt native
let client = @openai.Client::new(api_key="sk-test")
let audio = client.speech("Read this aloud.")
let said = client.transcribe(audio, filename="out.mp3")
```

## Consistency

What is checked, and how:

- **Wire round trips.** For each of the four formats, a request goes out through the dialect,
  is parsed back, and must equal the original — and a reply becomes a body and reads back the
  same. The fixtures are the shapes the vendors document.
- **Recorded streams.** A recorded OpenAI chat stream, Anthropic event stream and Ollama
  newline stream are replayed through the reader; the assembled reply must match the
  non-streamed one. The OpenAI stream is also cut at every byte offset, to prove the reader
  never depends on where the transport splits a frame.
- **A stream off a socket.** A server writes one frame and withholds the next until the caller
  has it, which is the only way to show that a frame arrives before the body ends; another cuts
  a character across two writes, so a decoder working per read would show the break.
- **One answer, four formats.** An Ollama-format streaming request is served in all four
  formats and each answer is read back with its own reader: the pieces must be the same pieces,
  in the same order, and a tool call split across frames must arrive as one call.
- **The stream writer against the reader.** The frames a gateway writes are read back by the
  client reader, and must produce the same deltas.
- **A real server.** The Ollama client is exercised against a live server in CI: chat, a tool
  declaration, and embeddings. Those tests run when `MOONMUSE_LIVE` is set, and fail loudly if
  it is set and the server is missing.
- **Official client libraries.** `scripts/interop` runs the gateway on port 12000 and drives it
  with `openai`, `anthropic`, `ollama` and `google-genai` — the real SDKs, not hand-written
  requests. CI runs chat, streaming, tool calls, embeddings, model lists and an error case.
- **The official field description.** `scripts/openapi/gen_fields.py` reads `openai-openapi` at
  a pinned commit and writes the field table the tests check bodies against (21 schemas, 182
  fields). A body that carries a key the description does not have fails the build, and a stale
  table fails CI before it can pass a wrong body.
- **The semantic conventions.** A span the library emits is sent over OTLP to the
  conventions project's own checker, which matches every attribute against the GenAI
  registry. An attribute that is unknown, misspelled or retired fails the build; the run is
  `scripts/otel-live-check.sh`.
- **LangChain standard tests.** The cases a provider can carry are transcribed in
  `src/serve/langchain_wbtest.mbt`, keeping the original names: conversation and double-message
  histories, usage with and without streaming, stop sequences, model override, tool calling with
  and without arguments, tool choice, tool-result and error histories, image inputs, Unicode tool
  calls, and sequential calls. The cases that test LangChain's own binding, event graph or
  timing layer are listed there with why they do not apply.

Known gaps, stated rather than hidden:

- `moonmuse/local` ships the template, the call parser and the engine contract; it does not
  ship an inference engine, so a model has to be wired in.
- Token counts are the vocabulary's count plus a framing amount the caller sets. The endpoint's
  own number is the authority; this one is for budgeting before the call.

## Targets

`moonmuse` and its pure subpackages build for `wasm`, `wasm-gc`, `js` and `native`. The four
provider clients and the streaming transport need a socket, which moonfetch provides on `native`
and `wasm` only; the other two targets still have the dialects, so a gateway can be written and
tested without one.

## License

Apache-2.0.
