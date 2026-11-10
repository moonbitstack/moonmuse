///|
/// The gateway's endpoint table, pinned. These are the routes the formats page prints and the
/// ones a client can call; a route added, renamed or dropped here without the same change on
/// the page is the kind of drift a reader finds before a test does.

///|
/// A dialect's routes as `VERB /path`, in the order the dialect lists them.
fn route_lines(dialect : &@moonmuse.Dialect) -> Array[String] {
  let lines = []
  for route in @moonmuse.Dialect::routes(dialect) {
    lines.push(route.verb + " " + route.path)
  }
  lines
}

///|
test "serve: each dialect serves the endpoints the site documents" {
  let table : Array[(&@moonmuse.Dialect, Array[String])] = [
    (
      @openai.dialect,
      [
        "POST /v1/chat/completions", "POST /v1/completions", "POST /v1/responses",
        "POST /v1/embeddings", "GET /v1/models",
      ],
    ),
    (
      @anthropic.dialect,
      ["POST /v1/messages", "POST /v1/messages/count_tokens", "GET /v1/models"],
    ),
    (
      @ollama.dialect,
      [
        "POST /api/chat", "POST /api/generate", "POST /api/embed", "GET /api/tags",
        "POST /api/show", "GET /api/version",
      ],
    ),
    (
      @gemini.dialect,
      [
        "POST /v1beta/models/*:embedContent", "POST /v1beta/models/*:batchEmbedContents",
        "POST /v1beta/models/*:generateContent", "POST /v1beta/models/*:streamGenerateContent",
        "GET /v1beta/models",
      ],
    ),
  ]
  for row in table {
    let (dialect, want) = row
    assert_eq(route_lines(dialect), want)
  }
}

///|
test "serve: a dialect is named by the key a route is looked up under" {
  let names = [
    @moonmuse.Dialect::name(@openai.dialect),
    @moonmuse.Dialect::name(@anthropic.dialect),
    @moonmuse.Dialect::name(@gemini.dialect),
    @moonmuse.Dialect::name(@ollama.dialect),
  ]
  assert_eq(names, ["openai", "anthropic", "gemini", "ollama"])
}
