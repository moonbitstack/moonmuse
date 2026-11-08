///|
/// The streaming half of the library, end to end: a gateway on a real socket, read by the
/// four clients, and a request in one format converted into the other four and read back.
/// Everything here goes through bytes — an in-memory app would prove the frames and not the
/// stream.

///|
/// Start `app` on a port the system chose and run `body` against it. The port is read from a
/// listener bound to port 0, so two of these tests can run at once.
async fn[X] with_gateway(
  app : @moonasgi.AsgiApp,
  body : async (Int32) -> X,
) -> X {
  let probe = @tcp.listen(host="127.0.0.1", port=0)
  let port = probe.addr().port()
  probe.close()
  @async.with_task_group(group => {
    let running = group.spawn(() => @mooncat.serve(app, host="127.0.0.1", port~))
    let mut ready = false
    for _ in 0..<200 {
      let dial = Ok(@tcp.dial("127.0.0.1", port~)) catch { _ => Err(()) }
      match dial {
        Ok(conn) => {
          conn.close()
          ready = true
          break
        }
        Err(_) => @async.sleep(5)
      }
    }
    if !ready {
      abort("the gateway did not start")
    }
    let out = body(port)
    running.cancel()
    out
  })
}

///|
/// The text deltas of a sequence, which is what a caller sees arrive.
fn chunks(deltas : Array[@moonmuse.Delta]) -> Array[String] {
  let out = []
  for delta in deltas {
    match delta {
      Text(chunk) => out.push(chunk)
      _ => ()
    }
  }
  out
}

///|
/// Whether the sequence closed with a reply.
fn closed(deltas : Array[@moonmuse.Delta]) -> Bool {
  match deltas[deltas.length() - 1] {
    Done(_) => true
    _ => false
  }
}

///|
/// A ten-character answer, which the scripted provider sends in two pieces.
fn request() -> @moonmuse.Request {
  @moonmuse.Request::new("m", [@moonmuse.Message::user("hi")])
}

///|
async test "stream: an OpenAI client reads the answer as it is produced" {
  let app = serve(@fake.Fake::text("abcdefghij"), dialects=default_dialects())
  with_gateway(app, async fn(port) {
    let base = "http://127.0.0.1:" + port.to_string() + "/v1"
    let client = @openai.Client::new(base~)
    let seen = []
    let reply = client.stream(request(), delta => seen.push(delta))
    assert_eq(reply.text(), "abcdefghij")
    assert_eq(chunks(seen), ["abcde", "fghij"])
    assert_eq(closed(seen), true)
  })
}

///|
async test "stream: an Anthropic client reads the event sequence" {
  let app = serve(@fake.Fake::text("abcdefghij"), dialects=[@anthropic.dialect])
  with_gateway(app, async fn(port) {
    let base = "http://127.0.0.1:" + port.to_string() + "/v1"
    let client = @anthropic.Client::new(base~)
    let seen = []
    let reply = client.stream(request(), delta => seen.push(delta))
    assert_eq(reply.text(), "abcdefghij")
    assert_eq(chunks(seen), ["abcde", "fghij"])
    assert_eq(closed(seen), true)
  })
}

///|
async test "stream: a Gemini client reads the answer from its own path" {
  let app = serve(@fake.Fake::text("abcdefghij"), dialects=[@gemini.dialect])
  with_gateway(app, async fn(port) {
    let base = "http://127.0.0.1:" + port.to_string() + "/v1beta"
    let client = @gemini.Client::new(base~)
    let seen = []
    let reply = client.stream(request(), delta => seen.push(delta))
    assert_eq(reply.text(), "abcdefghij")
    assert_eq(chunks(seen), ["abcde", "fghij"])
    assert_eq(closed(seen), true)
  })
}

///|
async test "stream: an Ollama client reads the newline-delimited answer" {
  let app = serve(@fake.Fake::text("abcdefghij"), dialects=[@ollama.dialect])
  with_gateway(app, async fn(port) {
    let base = "http://127.0.0.1:" + port.to_string()
    let client = @ollama.Client::new(base~)
    let seen = []
    let reply = client.stream(request(), delta => seen.push(delta))
    assert_eq(reply.text(), "abcdefghij")
    assert_eq(chunks(seen), ["abcde", "fghij"])
    assert_eq(closed(seen), true)
  })
}

///|
/// The deltas one streamed answer carries, read back with the format's own reader. The turn
/// starts fresh, as a client's would.
fn read_back(
  text : String,
  dialect : &@moonmuse.Dialect,
  framing~ : Bool = true,
) -> Array[@moonmuse.Delta] raise @moonmuse.LlmError {
  let frames = if framing {
    @moonmuse.parse_sse(text)
  } else {
    @moonmuse.parse_ndjson(text)
  }
  let turn = @moonmuse.Turn::new()
  let deltas = []
  for frame in frames {
    for delta in @moonmuse.Dialect::delta(dialect, frame, turn) {
      deltas.push(delta)
    }
  }
  deltas
}

///|
/// A streaming request written in Ollama's format, which every gateway must accept.
fn ollama_request() -> Bytes {
  @utf8.encode(
    "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"stream\":true}",
  )
}

///|
/// One answer in each of the four formats, all carrying the same deltas. A gateway that
/// converted unevenly would show it here as a different number of pieces or a different
/// order, which is what "chunk for chunk" means.
async test "stream: one request converts into the four formats chunk for chunk" {
  let app = serve(@fake.Fake::text("abcdefghij"), dialects=[
    @openai.dialect, @anthropic.dialect, @gemini.dialect, @ollama.dialect,
  ])
  let client = @testing.Client::new(app)
  let openai = client.post("/v1/chat/completions", body=ollama_request())
  assert_eq(openai.status, 200)
  let from_openai = read_back(openai.text(), @openai.dialect)
  let anthropic = client.post("/v1/messages", body=ollama_request())
  assert_eq(anthropic.status, 200)
  let from_anthropic = read_back(anthropic.text(), @anthropic.dialect)
  let gemini = client.post(
    "/v1beta/models/m:streamGenerateContent",
    body=ollama_request(),
  )
  assert_eq(gemini.status, 200)
  let from_gemini = read_back(gemini.text(), @gemini.dialect)
  let ollama = client.post("/api/chat", body=ollama_request())
  assert_eq(ollama.status, 200)
  let from_ollama = read_back(ollama.text(), @ollama.dialect, framing=false)
  let expected = ["abcde", "fghij"]
  assert_eq(chunks(from_openai), expected)
  assert_eq(chunks(from_anthropic), expected)
  assert_eq(chunks(from_gemini), expected)
  assert_eq(chunks(from_ollama), expected)
  assert_eq(closed(from_openai), true)
  assert_eq(closed(from_anthropic), true)
  assert_eq(closed(from_gemini), true)
  assert_eq(closed(from_ollama), true)
}

///|
/// A tool call split across frames, in every direction: the arguments arrive in pieces and
/// have to come back as one call whose arguments are the JSON the model wrote.
async test "stream: a tool call survives every conversion" {
  let app = serve(@fake.Fake::calls("add", { "a": 2, "b": 3 }), dialects=[
    @openai.dialect, @anthropic.dialect, @gemini.dialect, @ollama.dialect,
  ])
  let client = @testing.Client::new(app)
  let bodies : Array[(String, &@moonmuse.Dialect, Bool)] = [
    ("/v1/chat/completions", @openai.dialect, true),
    ("/v1/messages", @anthropic.dialect, true),
    ("/v1beta/models/m:streamGenerateContent", @gemini.dialect, true),
    ("/api/chat", @ollama.dialect, false),
  ]
  for entry in bodies {
    let (path, dialect, framing) = entry
    let response = client.post(path, body=ollama_request())
    assert_eq(response.status, 200)
    let deltas = read_back(response.text(), dialect, framing~)
    let started = deltas.filter_map(delta => {
      match delta {
        CallStart(name~, ..) => Some(name)
        _ => None
      }
    })
    assert_eq(started, ["add"])
    let args = deltas.filter_map(delta => {
      match delta {
        CallArgs(chunk~, ..) => Some(chunk)
        _ => None
      }
    })
    let joined = args.join("")
    assert_eq(@moonmuse.parse_json_lossy(joined), { "a": 2, "b": 3 })
  }
}
