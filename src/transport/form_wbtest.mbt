///|
/// The form a multipart endpoint receives. The framing is byte-exact — CRLF line endings, a
/// blank line before a part's data — because a server that sees anything else rejects the whole
/// upload, and no amount of correct JSON elsewhere makes up for it.

///|
test "form: the content type names the boundary it used" {
  let body = form([("model", "whisper-1")])
  let content_type = body.content_type()
  assert_eq(content_type.has_prefix("multipart/form-data; boundary="), true)
  let boundary = content_type.exact_view(start=30).to_owned()
  assert_eq(body.body().length() > 0, true)
  assert_eq(boundary.has_prefix("moonmuse-"), true)
}

///|
test "form: fields are framed with CRLF and a blank line" {
  let body = form([("model", "whisper-1"), ("language", "en")])
  let text = @utf8.decode_lossy(body.body()[:])
  assert_eq(
    text.contains("Content-Disposition: form-data; name=\"model\"\r\n\r\n"),
    true,
  )
  assert_eq(text.contains("whisper-1\r\n"), true)
  assert_eq(
    text.contains("Content-Disposition: form-data; name=\"language\"\r\n\r\n"),
    true,
  )
  assert_eq(text.has_suffix("--\r\n"), true)
}

///|
test "form: a file part carries its name, type and bytes" {
  let body = form(
    [("purpose", "batch")],
    file=("data.jsonl", "application/jsonl", b"{\"a\":1}\n"),
  )
  let text = @utf8.decode_lossy(body.body()[:])
  assert_eq(
    text.contains(
      "Content-Disposition: form-data; name=\"file\"; filename=\"data.jsonl\"\r\n",
    ),
    true,
  )
  assert_eq(text.contains("Content-Type: application/jsonl\r\n\r\n"), true)
  assert_eq(text.contains("{\"a\":1}\n"), true)
}

///|
test "form: the same form produces the same bytes" {
  let first = form(
    [("model", "whisper-1")],
    file=("a.mp3", "audio/mpeg", b"abc"),
  )
  let second = form(
    [("model", "whisper-1")],
    file=("a.mp3", "audio/mpeg", b"abc"),
  )
  assert_eq(first.content_type(), second.content_type())
  assert_eq(first.body(), second.body())
}

///|
test "form: a different file name yields a different boundary" {
  let first = form([("model", "m")], file=("a.mp3", "audio/mpeg", b"x"))
  let second = form([("model", "m")], file=("b.mp3", "audio/mpeg", b"x"))
  assert_eq(first.content_type() != second.content_type(), true)
}
