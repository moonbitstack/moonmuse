///|
/// The client over a socket: the request that leaves carries a signature, and the answers —
/// a Converse body and an event stream — become a reply and a sequence of deltas.

///|
/// A server that answers one request with fixed bytes and keeps what it was asked.
priv struct Wire {
  status : String
  body : Bytes
  headers : Array[(String, String)]
  mut seen : String
}

///|
async fn answer_once(listener : @tcp.Listener, wire : Wire) -> Unit {
  let (conn, _) = listener.accept()
  wire.seen = match conn.read_until("\r\n\r\n") {
    Some(head) => head
    None => ""
  }
  conn.write(wire.status)
  for pair in wire.headers {
    conn.write(pair.0 + ": " + pair.1 + "\r\n")
  }
  conn.write("connection: close\r\n\r\n")
  conn.write(wire.body)
  conn.close()
}

///|
async fn[X] with_wire(wire : Wire, body : async (String) -> X) -> X {
  let listener = @tcp.listen(host="127.0.0.1", port=0)
  let port = listener.addr().port()
  @async.with_task_group(group => {
    group.spawn_bg(() => answer_once(listener, wire))
    let out = body("http://127.0.0.1:" + port.to_string())
    listener.close()
    out
  })
}

///|
fn client(base : String) -> Client {
  Client::new(
    credential=Credential::new(
      "AKIDEXAMPLE", "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
    ),
    base~,
  )
}

///|
/// A Converse answer, as the service writes one.
fn converse_answer() -> String {
  "{\"output\":{\"message\":{\"role\":\"assistant\",\"content\":[{\"text\":\"hello there\"}]}},\"stopReason\":\"end_turn\",\"usage\":{\"inputTokens\":5,\"outputTokens\":2}}"
}

///|
async test "bedrock: chat signs the request and reads the answer" {
  let wire = Wire::{
    status: "HTTP/1.1 200 OK\r\n",
    headers: [("content-type", "application/json")],
    body: @utf8.encode(converse_answer()),
    seen: "",
  }
  with_wire(wire, async fn(base) {
    let reply = client(base).chat(
      @moonmuse.Request::new("m", [@moonmuse.Message::user("hi")]),
    )
    assert_eq(reply.text(), "hello there")
    assert_eq(reply.usage.input, Some(5))
    assert_eq(reply.finish, @moonmuse.Stop)
  })
  // What was on the wire: the signature over the headers that went with it.
  assert_eq(
    wire.seen.contains("authorization: AWS4-HMAC-SHA256 Credential="),
    true,
  )
  assert_eq(wire.seen.contains("x-amz-date: "), true)
  assert_eq(
    wire.seen.contains("SignedHeaders=content-type;host;x-amz-date"),
    true,
  )
  assert_eq(wire.seen.contains("POST /model/m/converse "), true)
}

///|
async test "bedrock: a streamed answer arrives as events" {
  let frames = Buffer()
  frames.write_bytes(
    encode_frame("messageStart", @utf8.encode("{\"role\":\"assistant\"}"))[:],
  )
  frames.write_bytes(
    encode_frame(
      "contentBlockDelta",
      @utf8.encode("{\"contentBlockIndex\":0,\"delta\":{\"text\":\"hel\"}}"),
    )[:],
  )
  frames.write_bytes(
    encode_frame(
      "contentBlockDelta",
      @utf8.encode("{\"contentBlockIndex\":0,\"delta\":{\"text\":\"lo\"}}"),
    )[:],
  )
  frames.write_bytes(
    encode_frame("messageStop", @utf8.encode("{\"stopReason\":\"end_turn\"}"))[:],
  )
  frames.write_bytes(
    encode_frame(
      "metadata",
      @utf8.encode("{\"usage\":{\"inputTokens\":4,\"outputTokens\":2}}"),
    )[:],
  )
  let wire = Wire::{
    status: "HTTP/1.1 200 OK\r\n",
    headers: [("content-type", "application/vnd.amazon.eventstream")],
    body: frames.to_bytes(),
    seen: "",
  }
  with_wire(wire, async fn(base) {
    let seen = []
    let reply = client(base).stream(
      @moonmuse.Request::new("m", [@moonmuse.Message::user("hi")]),
      delta => seen.push(delta),
    )
    assert_eq(reply.text(), "hello")
    assert_eq(reply.usage.output, Some(2))
    let text = seen.filter_map(delta => {
      match delta {
        @moonmuse.Delta::Text(chunk) => Some(chunk)
        _ => None
      }
    })
    assert_eq(text, ["hel", "lo"])
    match seen[seen.length() - 1] {
      @moonmuse.Delta::Done(_) => ()
      _ => abort("a stream must close with its reply")
    }
  })
}

///|
async test "bedrock: a failed call raises the status and the body" {
  let wire = Wire::{
    status: "HTTP/1.1 403 Forbidden\r\n",
    headers: [("content-type", "application/json")],
    body: @utf8.encode("{\"message\":\"bad key\"}"),
    seen: "",
  }
  let outcome : Result[@moonmuse.Reply, @moonmuse.LlmError] = with_wire(wire, async fn(
    base,
  ) {
    Ok(
      client(base).chat(
        @moonmuse.Request::new("m", [@moonmuse.Message::user("hi")]),
      ),
    ) catch {
      error => Err(error)
    }
  })
  match outcome {
    Err(@moonmuse.Status(code~, body~, ..)) => {
      assert_eq(code, 403)
      assert_eq(body.contains("bad key"), true)
    }
    Ok(_) => abort("a failed call must raise")
    Err(_) => abort("expected a status")
  }
}
