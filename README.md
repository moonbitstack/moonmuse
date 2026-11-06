<div align="center">

# moonmuse

**One contract for every language model: chat, streaming, tools and embeddings.**

[![mooncakes](https://img.shields.io/badge/mooncakes-moonbitstack%2Fmoonmuse-2f6f4e)](https://mooncakes.io/docs/moonbitstack/moonmuse)
[![license](https://img.shields.io/badge/license-Apache--2.0-2f6f4e)](LICENSE)

</div>

A model endpoint is a request and an answer. Which vendor answers it, whether it runs in a
data centre or on the laptop, and whether the caller speaks OpenAI's JSON or Anthropic's is a
detail of the wire — not of the code that asks. This library puts that detail in one place and
leaves one contract above it.

<!-- nocheck -->
```moonbit
let provider = @openai.Client::new(api_key="sk-...")
let reply = provider.chat(
  @moonmuse.Request::new("gpt-4o-mini", [@moonmuse.Message::user("Why is the sky blue?")]),
)
println(reply.text())
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
| `moonmuse/openai` | OpenAI's format, plus every endpoint that speaks it — DeepSeek, Kimi, Qwen, vLLM, OpenRouter, DashScope, Mistral — and the Responses, moderation, image, file, batch and fine-tuning calls |
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

## Chat

<!-- nocheck -->
```moonbit
let request = @moonmuse.Request::new(
  "claude-sonnet-4-20250514",
  [
    @moonmuse.Message::system("Answer in one sentence."),
    @moonmuse.Message::user("Why is the sky blue?"),
  ],
  temperature=0.2,
  max_tokens=256,
  stop=["\n\n"],
)
let reply = provider.chat(request)
let (text, usage) = (reply.text(), reply.usage.total())
```

`Request.extra` is merged into the body last, so a vendor's own field — `reasoning_effort`, a
beta switch — reaches the wire without this library modelling it. `Reply.raw` keeps the body
that came back for the fields the shared vocabulary does not hold.

## Streaming

<!-- nocheck -->
```moonbit
let reply = provider.stream(request, delta => {
  match delta {
    Text(chunk) => print(chunk)
    CallStart(_, name~) => println("\ncall " + name)
    CallArgs(_, chunk~) => print(chunk)
    Done(_) => println("")
  }
})
```

The returned reply is the same value `chat` would have returned, so a caller that ignores the
deltas still gets the whole answer.

## Tools

<!-- nocheck -->
```moonbit
let tools = @toolbox.Toolbox::new()
tools.add(@moonmuse.Tool::new("add", "Add two integers"), args => {
  (json_int(args, "a").unwrap_or(0) + json_int(args, "b").unwrap_or(0)).to_string()
})
let reply = @toolbox.run(provider, request, tools, limit=10)
```

`Toolbox::call` is the only place a call becomes a result, so a framework with its own loop
uses it directly and gets the same behaviour — including the rule that a failing tool produces
an error result rather than an exception.

## Layers

<!-- nocheck -->
```moonbit
let gateway = @layers.cached(
  @layers.retry(@layers.fallback([primary, secondary])),
  @layers.Memory::new(limit=512),
)
```

Every layer is a `Provider`, so they compose in any order. Retry honours `retry-after` and
only retries failures that could pass on a second try; fallback switches on the same
classification; the cache key covers every field that decides an answer.

## Structured output

<!-- nocheck -->
```moonbit
let answer = @structured.ask(
  provider,
  request,
  name="weather",
  schema=my_schema,
  decode=json => json_int(json, "celsius"),
)
```

The schema is stated in the prompt and checked against the reply with moonschema; a reply that
does not fit goes back with the reason, up to a budget, and the last failure is raised.

## Serve

<!-- nocheck -->
```moonbit
let app = @serve.serve(
  provider,
  dialects=[@openai.dialect, @anthropic.dialect, @gemini.dialect, @ollama.dialect],
  keys=@serve.StaticKeys::new(["sk-local"]),
)
```

`serve` returns an `AsgiApp`: run it with any ASGI server, or mount it under a framework. The
endpoints are the dialects' own, so a format added once is served, called and parsed by the
same code.

| Format | Endpoints |
|:--|:--|
| OpenAI | `/v1/chat/completions`, `/v1/completions`, `/v1/responses`, `/v1/embeddings`, `/v1/models` |
| Anthropic | `/v1/messages`, `/v1/messages/count_tokens`, `/v1/models` |
| Ollama | `/api/chat`, `/api/generate`, `/api/embed`, `/api/tags`, `/api/show`, `/api/version` |
| Gemini | `/v1beta/models/*:generateContent`, `:streamGenerateContent`, `:embedContent` |

Two formats claim `/v1/models`; the `anthropic-version` header decides which answers.

## Model catalogue

<!-- nocheck -->
```moonbit
let info = @models.find("gpt-4o-mini")
let cost = @models.estimate_cost("gpt-4o-mini", reply.usage)
```

Prices are US dollars per million tokens as published by each vendor, and change without
notice; the reply's own usage is what a call actually cost.

## Consistency

What is checked, and how:

- **Wire round trips.** For each of the four formats, a request goes out through the dialect,
  is parsed back, and must equal the original — and a reply becomes a body and reads back the
  same. The fixtures are the shapes the vendors document.
- **Recorded streams.** A recorded OpenAI chat stream, Anthropic event stream and Ollama
  newline stream are replayed through the reader; the assembled reply must match the
  non-streamed one. The OpenAI stream is also cut at every byte offset, to prove the reader
  never depends on where the transport splits a frame.
- **The stream writer against the reader.** The frames a gateway writes are read back by the
  client reader, and must produce the same deltas.
- **A real server.** The Ollama client is exercised against a live server in CI: chat, a tool
  declaration, and embeddings. Those tests run when `MOONMUSE_LIVE` is set, and fail loudly if
  it is set and the server is missing.
- **Transport.** `moonmuse/transport` maps a `Call` onto moonfetch, including status and
  `retry-after`; a non-JSON error body is reported as a status, not as a decode failure.

Not yet checked, and known to be missing:

- Streamed answers from a client. moonfetch has no streamed response yet, so `Provider::stream`
  on a client fetches the whole answer and replays it as deltas: the deltas are correct, the
  timing is not. The `Dialect` side — reading a real stream and writing one — is complete and
  tested.
- Audio endpoints (`/v1/audio/speech`, `/v1/audio/transcriptions`) take and return binary
  bodies, which the transport does not carry yet.
- `/v1/messages/count_tokens` answers `Unsupported`: counting tokens needs a tokenizer, and
  this library does not ship one.
- The official client SDKs (`openai-python`, `anthropic-sdk-python`, `ollama-python`) are not
  yet run against `serve` in CI, and the LangChain standard tests are not yet transcribed.

## Targets

`moonmuse` and its pure subpackages build for `wasm`, `wasm-gc`, `js` and `native`. The four
provider clients need a transport, which moonfetch provides on `native` and `wasm` only; the
other two targets still have the dialects, so a gateway can be written and tested without a
socket.

## License

Apache-2.0.
