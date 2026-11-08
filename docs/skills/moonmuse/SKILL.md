---
name: moonmuse
description: Talk to language model APIs from MoonBit through one contract — chat, streaming, tool calls, embeddings, retries and fallbacks, structured output, token counting, tracing, and exporting a provider as an OpenAI, Anthropic, Gemini or Ollama API. Use when calling a model from MoonBit, adding another vendor, or putting a gateway in front of a model.
---

# moonmuse

One `Provider` for every model endpoint, one `Dialect` per wire format. Which vendor answers
is a constructor argument.

## Install

```
moon add moonbitstack/moonmuse
```

```
import {
  "moonbitstack/moonmuse",
  "moonbitstack/moonmuse/openai",
}
```

## Ask a model

Every provider implements `Provider`, so only the constructor changes between vendors. A
field left out of `Request::new` is left out of the wire body rather than sent as a default;
`extra` is merged last, which is how a vendor field this library does not model gets through.

```mbt native
let provider : &@moonmuse.Provider = @openai.Client::new(
  api_key="sk-test",
  base="http://127.0.0.1:12000/v1",
)
let request = @moonmuse.Request::new(
  "gpt-4o-mini",
  [@moonmuse.Message::user("hello")],
  temperature=0.2,
  max_tokens=64,
)
let reply = provider.chat(request)
let text = reply.text()
```

## Stream, and run tools

`stream` hands each delta to the callback as it comes off the socket — a character split across
two reads is held back until it is whole — and returns the assembled reply, the same value
`chat` returns.

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

A tool is a schema plus a function. `Toolbox::call` turns a call into a result; `run` owns the
loop and stops at `limit` rounds.

```mbt native
let tools = @toolbox.Toolbox::new()
tools.add(@moonmuse.Tool::new("add", "add two integers"), args => {
  let a = @moonmuse.json_int(args, "a").unwrap_or(0)
  let b = @moonmuse.json_int(args, "b").unwrap_or(0)
  (a + b).to_string()
})
let looped = @toolbox.run(provider, request, tools, limit=4)
```

The loop sends each result back as a `Tool` message. A tool that raises, or that is not
registered, becomes a result with `error` set — the model is meant to see it.

## Wrap, cache, fall back

```mbt native
let secondary : &@moonmuse.Provider = @ollama.Client::new()
let gateway = @layers.cached(
  @layers.retry(@layers.fallback([provider, secondary])),
  @layers.Memory::new(limit=64),
)
let served = gateway.chat(request)
```

Retry and fallback only act on failures another attempt could avoid: a rate limit, a 5xx, a
dropped stream, a capability the endpoint lacks. A 400 is passed straight back.

## Serve

`serve` returns an `AsgiApp`. List the formats to offer; the endpoints come from the dialects.

```mbt native
let app = @serve.serve(
  provider,
  dialects=[@openai.dialect, @anthropic.dialect],
)
```

`/v1/models` is offered by both formats; the `anthropic-version` header picks the answer. Pass
`keys=@serve.StaticKeys::new([...])` to require a bearer token, and `counter=` to answer
`/v1/messages/count_tokens`:

```mbt native
let ranks = @vocab.Ranks::empty()
let tokenizer = @moontoken.Tokenizer::cl100k(ranks~)
let counted = @count.Tokens::new(tokenizer~)
```

## Observe

`@otel.traced` records one client span per call and `@otel.metered` records duration and tokens,
both under the OpenTelemetry GenAI names. Message bodies stay out of the trace unless
`content=true`.

```mbt native
let recorder = @trace.Recorder::new()
let tracer = @trace.Tracer::new(
  rand=width => Bytes::make(width, b'\x01'),
  sink=recorder,
  sampler=@trace.parent_based(root=@trace.always),
)
let observed = @otel.traced(provider, tracer)
```

## Rules that are easy to miss

- `Request::new`'s `temperature` and `max_tokens` are optional parameters: pass a value as
  `temperature=0.2`, and forward an existing `Double?` as `temperature?=value`.
- Tool arguments arrive as a JSON string on the wire and are parsed for you; malformed
  arguments become `{}` rather than an error.
- `Usage` fields are `Int32?`: an endpoint that reports nothing is not the same as one that
  reports zero.
- Context windows and prices in `moonmuse/models` are published figures, useful for an
  estimate, not a bill.
- The clients and the streaming transport need a socket, so they build for `native` and
  `wasm` only; the dialects are pure and build everywhere, which is what makes a gateway
  testable without a network.
- A token count from `moonmuse/count` is the vocabulary's count plus a framing amount you
  pass in. The endpoint's own number is the authority.
