---
name: moonmuse
description: Talk to language model APIs from MoonBit through one contract — chat, streaming, tool calls, embeddings, retries and fallbacks, structured output, and exporting a provider as an OpenAI, Anthropic, Gemini or Ollama API. Use when calling a model from MoonBit, adding another vendor, or putting a gateway in front of a model.
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

Every provider implements `Provider`, so only the constructor changes between vendors.

```
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
println(reply.text())
```

`Request::new` takes `tools`, `choice`, `temperature`, `max_tokens`, `stop` and `extra`; a field
left out is left out of the wire body rather than sent as a default. `extra` is merged into the
body last, which is how a vendor field this library does not model gets through.

## Stream, and run tools

`stream` calls the callback for each delta and returns the assembled reply — the same value
`chat` returns.

```
let reply = provider.stream(request, delta => {
  match delta {
    Text(chunk) => print(chunk)
    CallStart(_, name~) => println("\ncall " + name)
    CallArgs(_, chunk~) => print(chunk)
    Done(_) => println("")
  }
})
```

A tool is a schema plus a function. `Toolbox::call` turns a call into a result; `run` owns the
loop and stops at `limit` rounds.

```
let tools = @toolbox.Toolbox::new()
tools.add(@moonmuse.Tool::new("add", "add two integers"), args => {
  let a = @moonmuse.json_int(args, "a").unwrap_or(0)
  (a + 1).to_string()
})
let reply = @toolbox.run(provider, request, tools, limit=4)
```

The loop sends each result back as a `Tool` message. A tool that raises, or that is not
registered, becomes a result with `error` set — the model is meant to see it.

## Wrap, cache, fall back

```
let gateway = @layers.cached(
  @layers.retry(@layers.fallback([primary, secondary])),
  @layers.Memory::new(limit=64),
)
let reply = gateway.chat(request)
```

Retry and fallback only act on failures another attempt could avoid: a rate limit, a 5xx, a
dropped stream, a capability the endpoint lacks. A 400 is passed straight back.

## Serve

`serve` returns an `AsgiApp`. List the formats to offer; the endpoints come from the dialects.

```
let app = @serve.serve(
  @fake.Fake::text("hi"),
  dialects=[@openai.dialect, @anthropic.dialect],
)
```

`/v1/models` is offered by both formats; the `anthropic-version` header picks the answer. Pass
`keys=@serve.StaticKeys::new([...])` to require a bearer token.

## Rules that are easy to miss

- `Request::new`'s `temperature` and `max_tokens` are optional parameters: pass a value as
  `temperature=0.2`, and forward an existing `Double?` as `temperature?=value`.
- A client's `stream` fetches the whole answer and replays it: the deltas are right, the
  arrival times are not, until moonfetch grows a streamed response.
- Tool arguments arrive as a JSON string on the wire and are parsed for you; malformed
  arguments become `{}` rather than an error.
- `Usage` fields are `Int32?`: an endpoint that reports nothing is not the same as one that
  reports zero.
- Context windows and prices in `moonmuse/models` are published figures, useful for an
  estimate, not a bill.
