///|
/// A streamed answer, read as it arrives. The transport hands up whatever bytes the network
/// delivered; this file is what turns them into the text of a frame, never assuming a split
/// falls on a character boundary, and what drives a dialect's reader over the result.
///
/// Before this existed, `Provider::stream` fetched the whole answer and replayed it: the
/// deltas were right and the waiting was wrong. A gateway in front of a model has to pass
/// tokens on as they come, so the wait is the whole point.

///|
/// How the frames of a streamed answer are delimited. Server-sent events carry a name and a
/// blank line between frames; Ollama writes one JSON object per line.
pub(all) enum Framing {
  Sse
  Lines
}

///|
/// An answer whose body is read a piece at a time.
pub struct Streaming {
  status : Int32
  headers : Array[(String, String)]
  stream : @moonfetch.Stream
  client : @moonfetch.Client
  /// Trailing bytes of a character the network split. At most three, until the rest arrives.
  mut pending : Bytes
  mut over : Bool
}

///|
/// Ask for an answer and return once its head is in. A failed call is a `Stream` error, which
/// is retryable; a 4xx or 5xx head is not raised here, because the body that explains it has to
/// be read off the same stream.
pub async fn open(
  call : @moonmuse.Call,
  base~ : String,
  headers~ : Array[(String, String)] = [],
  timeout? : Int32,
) -> Streaming raise @moonmuse.LlmError {
  let url = join(base, call.path)
  let all_headers = [..headers, ..call.headers]
  let body = match call.payload {
    Some(data) => @moonfetch.Body::Bytes(data)
    None => @moonfetch.Body::Text(@json.dumps(call.body))
  }
  let query = if call.query.is_empty() { None } else { Some(call.query) }
  let client = @moonfetch.Client::new() catch {
    error => raise @moonmuse.Stream(error.to_string())
  }
  let stream = client.stream(
    method_of(call.verb),
    url,
    query?,
    headers=all_headers,
    body~,
    timeout?,
  ) catch {
    error => {
      client.close()
      raise @moonmuse.Stream(error.to_string())
    }
  }
  {
    status: stream.status(),
    headers: stream.headers(),
    stream,
    client,
    pending: Bytes::new(0),
    over: false,
  }
}

///|
/// The status of the head.
pub fn Streaming::status(self : Streaming) -> Int32 {
  self.status
}

///|
/// The last value of a header, case-insensitively.
pub fn Streaming::header(self : Streaming, name : String) -> String? {
  let wanted = name.to_lower()
  let mut found = None
  for pair in self.headers {
    if pair.0.to_lower() == wanted {
      found = Some(pair.1)
    }
  }
  found
}

///|
/// The `retry-after` header in seconds, when the endpoint sent one.
pub fn Streaming::retry_after(self : Streaming) -> Int64? {
  match self.header("retry-after") {
    Some(text) => {
      let seconds = @moonmuse.parse_int_lossy(text)
      if seconds > 0 {
        Some(seconds.to_int64())
      } else {
        None
      }
    }
    None => None
  }
}

///|
/// The next piece of the body as text, or `None` at the end. A piece ends where the network
/// ended it, except that a character split across two reads is held back until its remaining
/// bytes arrive — a caller never sees half a character.
pub async fn Streaming::next(
  self : Streaming,
) -> String? raise @moonmuse.LlmError {
  let mut piece : String? = None
  while piece is None && !self.over {
    piece = self.take()
  }
  piece
}

///|
/// One read off the network, as much whole text as it completed.
async fn Streaming::take(self : Streaming) -> String? raise @moonmuse.LlmError {
  let chunk = self.stream.next() catch {
    error => {
      self.over = true
      raise @moonmuse.Stream(error.to_string())
    }
  }
  match chunk {
    None => {
      self.over = true
      let rest = self.pending
      self.pending = Bytes::new(0)
      if rest.length() > 0 {
        Some(@utf8.decode_lossy(rest[:]))
      } else {
        None
      }
    }
    Some(@moonfetch.Chunk::End(_)) => {
      self.over = true
      None
    }
    Some(@moonfetch.Chunk::Data(data)) => {
      let joined = if self.pending.length() == 0 {
        data
      } else {
        let buf = Buffer()
        buf.write_bytes(self.pending[:])
        buf.write_bytes(data[:])
        buf.to_bytes()
      }
      let cut = complete_prefix(joined[:])
      self.pending = joined[cut:].to_owned()
      if cut == 0 {
        None
      } else {
        Some(@utf8.decode_lossy(joined.exact_view(start=0, end=cut)))
      }
    }
  }
}

///|
/// The next piece of the body as it arrived, without decoding. A binary framing — AWS's
/// event stream, a media container — is read this way; `next` is the text one.
pub async fn Streaming::next_bytes(
  self : Streaming,
) -> Bytes? raise @moonmuse.LlmError {
  if self.over {
    return None
  }
  let chunk = self.stream.next() catch {
    error => {
      self.over = true
      raise @moonmuse.Stream(error.to_string())
    }
  }
  match chunk {
    None => {
      self.over = true
      None
    }
    Some(@moonfetch.Chunk::End(_)) => {
      self.over = true
      None
    }
    Some(@moonfetch.Chunk::Data(data)) => Some(data)
  }
}

///|
/// Whether the body has been read to its end.
pub fn Streaming::is_over(self : Streaming) -> Bool {
  self.over
}

///|
/// Read the rest of the body as text. Used for the body of a failure, which is small.
pub async fn Streaming::text(
  self : Streaming,
  limit? : Int32,
) -> String raise @moonmuse.LlmError {
  let cap = limit.unwrap_or(1_048_576)
  let out = StringBuilder()
  let mut total = 0
  while total < cap {
    match self.next() {
      None => break
      Some(piece) => {
        out.write_string(piece)
        total = total + piece.length()
      }
    }
  }
  out.to_string()
}

///|
/// Give up the rest of the body and close the connection. Safe to call twice.
pub fn Streaming::close(self : Streaming) -> Unit {
  self.stream.close()
  self.client.close()
}

///|
/// Raise the status of a failed answer, after reading the body that explains it.
pub async fn Streaming::ensure_success(
  self : Streaming,
) -> Unit raise @moonmuse.LlmError {
  if self.status >= 400 {
    let body = self.text()
    raise @moonmuse.Status(
      code=self.status,
      body~,
      retry_after=self.retry_after(),
    )
  }
}

///|
/// Drive a dialect's reader over an open answer, calling `on_delta` for each event as it
/// arrives, and return the reply those events assemble. A stream that ends without a closing
/// event still yields a reply: the events it did carry are the answer.
pub async fn stream_reply(
  dialect : &@moonmuse.Dialect,
  answer : Streaming,
  framing~ : Framing = Sse,
  on_delta~ : (@moonmuse.Delta) -> Unit,
) -> @moonmuse.Reply raise @moonmuse.LlmError {
  defer answer.close()
  let turn = @moonmuse.Turn::new()
  let assembly = @moonmuse.Assembly::new()
  let sse = @moonmuse.Sse::new()
  let lines = Lines::new()
  let mut ended = false
  while !ended {
    match answer.next() {
      None => {
        emit(
          dialect,
          if framing is Sse {
            sse.finish()
          } else {
            lines.finish()
          },
          turn,
          assembly,
          on_delta,
        )
        ended = true
      }
      Some(piece) => {
        emit(
          dialect,
          if framing is Sse {
            sse.feed(piece)
          } else {
            lines.feed(piece)
          },
          turn,
          assembly,
          on_delta,
        )
        ended = assembly.is_done()
      }
    }
  }
  let reply = assembly.reply()
  if !assembly.is_done() {
    on_delta(@moonmuse.Delta::Done(reply))
  }
  reply
}

///|
/// One batch of frames through the dialect, and on to the caller.
fn emit(
  dialect : &@moonmuse.Dialect,
  frames : Array[@moonmuse.Frame],
  turn : @moonmuse.Turn,
  assembly : @moonmuse.Assembly,
  on_delta : (@moonmuse.Delta) -> Unit,
) -> Unit raise @moonmuse.LlmError {
  for frame in frames {
    for delta in @moonmuse.Dialect::delta(dialect, frame, turn) {
      assembly.push(delta)
      on_delta(delta)
    }
  }
}

///|
/// How many leading bytes of `data` form whole characters. Anything after that is an
/// incomplete character, or one too malformed to complete: it waits for the next read.
fn complete_prefix(data : BytesView) -> Int32 {
  let n = data.length()
  let mut start = n
  let mut back = 0
  while start > 0 {
    let byte = data[start - 1].to_int()
    if (byte & 0xC0) == 0x80 {
      if back == 3 {
        // Four continuation bytes with no lead byte in front: not a sequence this can wait
        // for, so let the lossy decoder say what it makes of it.
        return n
      }
      start = start - 1
      back = back + 1
      continue
    }
    break
  }
  if start == 0 {
    return n
  }
  let lead = data[start - 1].to_int()
  let want = if lead >= 0xF0 {
    4
  } else if lead >= 0xE0 {
    3
  } else if lead >= 0xC0 {
    2
  } else {
    1
  }
  if n - (start - 1) < want {
    start - 1
  } else {
    n
  }
}

///|
/// Newline-delimited JSON, read in whatever pieces arrive. One line is one frame.
priv struct Lines {
  mut buf : String
}

///|
fn Lines::new() -> Lines {
  { buf: "", }
}

///|
fn Lines::feed(self : Lines, piece : String) -> Array[@moonmuse.Frame] {
  self.buf = self.buf + piece
  let frames = []
  while true {
    match self.buf.find("\n") {
      None => break
      Some(at) => {
        let line = self.buf.exact_view(start=0, end=at).to_owned()
        self.buf = self.buf.exact_view(start=at + 1).to_owned()
        push_line(line, frames)
      }
    }
  }
  frames
}

///|
fn Lines::finish(self : Lines) -> Array[@moonmuse.Frame] {
  let frames = []
  let rest = self.buf
  self.buf = ""
  push_line(rest, frames)
  frames
}

///|
fn push_line(line : String, frames : Array[@moonmuse.Frame]) -> Unit {
  let mut text = line
  if text.has_suffix("\r") {
    text = text.exact_view(start=0, end=text.length() - 1).to_owned()
  }
  let text = text.trim().to_owned()
  if text != "" {
    frames.push(@moonmuse.Frame::new(text))
  }
}

///|
/// The HTTP method a call's verb names.
fn method_of(verb : String) -> @method.Method raise @moonmuse.LlmError {
  match verb {
    "GET" => @method.Method::Get
    "POST" => @method.Method::Post
    "PUT" => @method.Method::Put
    "PATCH" => @method.Method::Patch
    "DELETE" => @method.Method::Delete
    "HEAD" => @method.Method::Head
    "OPTIONS" => @method.Method::Options
    other => raise @moonmuse.Decode("unknown HTTP verb: " + other)
  }
}
