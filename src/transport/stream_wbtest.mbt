///|
/// What a streaming transport promises is that a frame reaches the caller before the body
/// ends, and that a character split by the network arrives whole. Only a server that writes
/// the bytes it is told, when it is told, can show either: a client that buffered the body
/// cannot come back from `next` while this server is still holding the rest.

///|
/// A scripted answer: the head, then the body in as many pieces as the test wants, with a
/// stop after `hold` of them until the test says to go on.
priv struct Wire {
  head : String
  pieces : Array[Bytes]
  hold : Int32
  mut released : Bool
}

///|
/// Answer one request with the script.
async fn answer_once(listener : @tcp.Listener, wire : Wire) -> Unit {
  let (conn, _) = listener.accept()
  let _ = conn.read_until("\r\n\r\n")
  conn.write(wire.head)
  let mut index = 0
  for piece in wire.pieces {
    if index == wire.hold {
      while !wire.released {
        @async.sleep(2)
      }
    }
    conn.write(piece)
    index = index + 1
  }
  conn.close()
}

///|
/// Run `body` against a server that answers with `wire`, on a port the system chose.
async fn[X] with_wire(wire : Wire, body : async (Int32) -> X) -> X {
  let listener = @tcp.listen(host="127.0.0.1", port=0)
  let port = listener.addr().port()
  @async.with_task_group(group => {
    group.spawn_bg(() => answer_once(listener, wire))
    let out = body(port)
    listener.close()
    out
  })
}

///|
/// A head that announces a stream and never says how long it is.
fn stream_head() -> String {
  "HTTP/1.1 200 OK\r\ncontent-type: text/event-stream\r\nconnection: close\r\n\r\n"
}

///|
/// A streamed answer: the first frame reaches the caller while the server still holds the
/// second. The assertion is causal rather than timed — the read cannot return before the
/// server writes, and the server does not write until the caller has the first frame.
async test "stream: a frame arrives before the body ends" {
  let wire = Wire::{
    head: stream_head(),
    pieces: [@utf8.encode("data: one\n\n"), @utf8.encode("data: two\n\n")],
    hold: 1,
    released: false,
  }
  with_wire(wire, async fn(port) {
    let call = @moonmuse.Call::new("POST", "/stream", Json::object(Map([])))
    let answer = open(call, base="http://127.0.0.1:" + port.to_string())
    let first = answer.next()
    assert_eq(first, Some("data: one\n\n"))
    // The server is still holding the second frame: nothing else has arrived.
    assert_eq(answer.is_over(), false)
    wire.released = true
    let second = answer.next()
    assert_eq(second, Some("data: two\n\n"))
    assert_eq(answer.next(), None)
    answer.close()
  })
}

///|
/// A byte range as its own array, for a piece the transport has to send separately.
fn slice(data : Bytes, start : Int32, end : Int32) -> Bytes {
  let buf = Buffer()
  buf.write_bytes(data[start:end])
  buf.to_bytes()
}

///|
/// The network splits a multi-byte character across two reads. The caller must never see the
/// half, whichever byte the transport happened to stop at.
async test "stream: a character split by the network arrives whole" {
  let wire = Wire::{
    head: stream_head(),
    pieces: [@utf8.encode("data: \u{3042}"), @utf8.encode("data: \u{3044}\n\n")],
    hold: 0,
    released: true,
  }
  with_wire(wire, async fn(port) {
    let call = @moonmuse.Call::new("POST", "/stream", Json::object(Map([])))
    let answer = open(call, base="http://127.0.0.1:" + port.to_string())
    let out = answer.text()
    answer.close()
    assert_eq(out, "data: あdata: い\n\n")
  })
}

///|
/// A byte-level split: the pieces are the exact bytes of one frame, cut inside a character,
/// not aligned to chunks. This is the case that a decoder working per read would corrupt.
async test "stream: bytes cut inside a character are rejoined" {
  let whole = @utf8.encode("data: あい\n\n")
  let length = whole.length().to_string()
  let head = "HTTP/1.1 200 OK\r\ncontent-length: " + length + "\r\n\r\n"
  let wire = Wire::{
    head,
    pieces: [slice(whole, 0, 8), slice(whole, 8, whole.length())],
    // The first piece ends inside a character and is all the caller gets until it says so;
    // without the hold the two writes arrive as one read and there is nothing to test.
    hold: 1,
    released: false,
  }
  with_wire(wire, async fn(port) {
    let call = @moonmuse.Call::new("POST", "/stream", Json::object(Map([])))
    let answer = open(call, base="http://127.0.0.1:" + port.to_string())
    let mut seen = ""
    // The first read ends inside the character, so what it may hand up ends before it.
    match answer.next() {
      Some(piece) => {
        assert_eq(piece, "data: ")
        seen = seen + piece
      }
      None => abort("the first piece must arrive")
    }
    wire.released = true
    while true {
      match answer.next() {
        None => break
        Some(piece) => seen = seen + piece
      }
    }
    answer.close()
    assert_eq(seen, "data: あい\n\n")
  })
}

///|
/// A failure arrives as a head plus a body, and the body is what explains it.
async test "stream: a failed call raises its status with the body" {
  let payload = "{\"error\":{\"message\":\"no key\"}}"
  let length = payload.length().to_string()
  let head = "HTTP/1.1 401 Unauthorized\r\ncontent-type: application/json\r\n" +
    "content-length: " +
    length +
    "\r\n\r\n"
  let wire = Wire::{
    head,
    pieces: [@utf8.encode(payload)],
    hold: 0,
    released: true,
  }
  with_wire(wire, async fn(port) {
    let call = @moonmuse.Call::new("POST", "/stream", Json::object(Map([])))
    let answer = open(call, base="http://127.0.0.1:" + port.to_string())
    assert_eq(answer.status(), 401)
    let outcome = Ok(answer.ensure_success()) catch { error => Err(error) }
    answer.close()
    match outcome {
      Err(@moonmuse.Status(code~, body~, ..)) => {
        assert_eq(code, 401)
        assert_eq(body, payload)
      }
      Ok(_) => abort("a failed call must raise")
      Err(_) => abort("expected a status")
    }
  })
}
