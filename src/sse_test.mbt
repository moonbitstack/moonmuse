///|
/// The reader has to survive the transport splitting a frame anywhere, because that is
/// what a socket does. These cases replay one recorded OpenAI stream cut at every byte,
/// then at every other byte, and require the same frames every time.

///|
/// One recorded chat-completions stream, as it arrived.
let openai_stream : String = [
  "data: {\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":\"Hel\"},\"finish_reason\":null}]}",
  "", "data: {\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"lo\"},\"finish_reason\":null}]}",
  "", "data: {\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}",
  "", "data: [DONE]", "", "",
].join("\n")

///|
test "sse: one frame per blank line" {
  let frames = @moonmuse.parse_sse(openai_stream)
  assert_eq(frames.length(), 4)
  assert_eq(frames[0].data.contains("\"Hel\""), true)
  assert_eq(frames[3].data, "[DONE]")
}

///|
test "sse: a frame split at every offset still reads as one frame" {
  let whole = @moonmuse.parse_sse(openai_stream)
  for cut = 0; cut <= openai_stream.length(); cut = cut + 1 {
    let reader = @moonmuse.Sse::new()
    let frames = reader.feed(openai_stream.exact_view(start=0, end=cut))
    let rest = reader.feed(openai_stream.exact_view(start=cut))
    let frames = frames + rest + reader.finish()
    assert_eq(frames.length(), whole.length())
    for i = 0; i < frames.length(); i = i + 1 {
      assert_eq(frames[i].data, whole[i].data)
    }
  }
}

///|
test "sse: a frame cut into single characters" {
  let reader = @moonmuse.Sse::new()
  let frames = []
  for i = 0; i < openai_stream.length(); i = i + 1 {
    frames.push(reader.feed(openai_stream.exact_view(start=i, end=i + 1)))
  }
  frames.push(reader.finish())
  let flat = []
  for batch in frames {
    for frame in batch {
      flat.push(frame)
    }
  }
  assert_eq(flat.length(), 4)
  assert_eq(flat[3].data, "[DONE]")
}

///|
test "sse: multi-line data joins with a newline" {
  let frames = @moonmuse.parse_sse("data: one\ndata: two\n\n")
  assert_eq(frames.length(), 1)
  assert_eq(frames[0].data, "one\ntwo")
}

///|
test "sse: a named event keeps its name" {
  let frames = @moonmuse.parse_sse(
    "event: content_block_delta\ndata: {\"a\":1}\n\n",
  )
  assert_eq(frames[0].event, Some("content_block_delta"))
  assert_eq(frames[0].data, "{\"a\":1}")
}

///|
test "sse: comments and keep-alives are dropped" {
  let frames = @moonmuse.parse_sse(": ping\n\ndata: kept\n\n")
  assert_eq(frames.length(), 1)
  assert_eq(frames[0].data, "kept")
}

///|
test "sse: a CRLF stream reads the same as LF" {
  let frames = @moonmuse.parse_sse("event: message\r\ndata: {\"a\":1}\r\n\r\n")
  assert_eq(frames.length(), 1)
  assert_eq(frames[0].event, Some("message"))
  assert_eq(frames[0].data, "{\"a\":1}")
}

///|
test "sse: a stream that ends without its blank line still yields the frame" {
  let reader = @moonmuse.Sse::new()
  let frames = reader.feed("data: last")
  assert_eq(frames.length(), 0)
  let tail = reader.finish()
  assert_eq(tail.length(), 1)
  assert_eq(tail[0].data, "last")
}

///|
test "sse: a field without a colon is a field with an empty value" {
  let frames = @moonmuse.parse_sse("data\n\n")
  assert_eq(frames.length(), 1)
  assert_eq(frames[0].data, "")
}

///|
test "sse: encoding round-trips through the reader" {
  let frames = [
    @moonmuse.Frame::named("delta", "{\"x\":1}"),
    @moonmuse.Frame::new("plain"),
  ]
  let encoded = @moonmuse.encode_sse(frames)
  let back = @moonmuse.parse_sse(encoded)
  assert_eq(back.length(), 2)
  assert_eq(back[0], frames[0])
  assert_eq(back[1], frames[1])
}

///|
test "ndjson: one object per line, blank lines skipped" {
  let frames = @moonmuse.parse_ndjson("{\"a\":1}\n\n{\"b\":2}\n")
  assert_eq(frames.length(), 2)
  assert_eq(frames[1].data, "{\"b\":2}")
}
