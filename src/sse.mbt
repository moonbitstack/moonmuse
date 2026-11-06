///|
/// A server-sent-events reader that takes the stream in whatever pieces the network
/// delivers. A frame's fields may be split across two reads, and one read may carry
/// several frames; the reader only dispatches at the blank line that ends a frame, so
/// the boundaries of the transport never leak into the dialect.
pub struct Sse {
  mut buf : String
  mut event : String?
  mut data : Array[String]
  mut started : Bool
}

///|
/// A reader with nothing buffered.
pub fn Sse::new() -> Sse {
  { buf: "", event: None, data: [], started: false, }
}

///|
/// Take one piece of the stream and return the frames it completed.
pub fn Sse::feed(self : Sse, chunk : StringView) -> Array[Frame] {
  self.buf = self.buf + chunk.to_owned()
  let frames = []
  while true {
    match self.buf.find("\n") {
      None => break
      Some(at) => {
        let line = self.buf.exact_view(start=0, end=at).to_owned()
        self.buf = self.buf.exact_view(start=at + 1).to_owned()
        let line = strip_cr(line)
        self.line(line, frames)
      }
    }
  }
  frames
}

///|
/// Dispatch whatever a truncated stream left behind. A server that closes without the
/// final blank line has still sent a complete frame.
pub fn Sse::finish(self : Sse) -> Array[Frame] {
  let frames = []
  if self.buf != "" {
    let line = strip_cr(self.buf)
    self.buf = ""
    self.line(line, frames)
  }
  self.dispatch(frames)
  frames
}

///|
/// Whether a frame is in progress.
pub fn Sse::is_idle(self : Sse) -> Bool {
  !self.started && self.event is None && self.data.is_empty() && self.buf == ""
}

///|
/// One line of the stream.
fn Sse::line(self : Sse, line : String, frames : Array[Frame]) -> Unit {
  if line == "" {
    self.dispatch(frames)
    return
  }
  if line.has_prefix(":") {
    // A comment, which is also the keep-alive most servers send.
    return
  }
  let (field, value) = match line.find(":") {
    None => (line, "")
    Some(at) => {
      let rest = line.exact_view(start=at + 1).to_owned()
      let value = if rest.has_prefix(" ") {
        rest.exact_view(start=1).to_owned()
      } else {
        rest
      }
      (line.exact_view(start=0, end=at).to_owned(), value)
    }
  }
  match field {
    "event" => {
      self.event = Some(value)
      self.started = true
    }
    "data" => {
      self.data.push(value)
      self.started = true
    }
    _ =>
      // `id` and `retry` do not change what a model stream means.
      self.started = true
  }
}

///|
/// Emit the frame the accumulated fields describe, if any.
fn Sse::dispatch(self : Sse, frames : Array[Frame]) -> Unit {
  if self.event is None && self.data.is_empty() {
    self.started = false
    return
  }
  let data = self.data.join("\n")
  frames.push({ event: self.event, data, })
  self.event = None
  self.data = []
  self.started = false
}

///|
/// A carriage return left by a CRLF stream is not part of the line.
fn strip_cr(line : String) -> String {
  if line.has_suffix("\r") {
    line.exact_view(start=0, end=line.length() - 1).to_owned()
  } else {
    line
  }
}

///|
/// Read a whole server-sent-events body at once.
pub fn parse_sse(text : StringView) -> Array[Frame] {
  let reader = Sse::new()
  let frames = reader.feed(text)
  let tail = reader.finish()
  frames + tail
}

///|
/// Read a whole newline-delimited JSON body — Ollama's streaming shape and the
/// fallback for endpoints that stream bare objects.
pub fn parse_ndjson(text : StringView) -> Array[Frame] {
  let frames = []
  for line in text.split("\n") {
    let line = strip_cr(line.to_owned()).trim()
    if line != "" {
      frames.push({ event: None, data: line.to_owned(), })
    }
  }
  frames
}

///|
/// Encode frames as a server-sent-events body, with the event name when there is one.
pub fn encode_sse(frames : Array[Frame]) -> String {
  let out = StringBuilder()
  for frame in frames {
    match frame.event {
      Some(event) => {
        out.write_string("event: ")
        out.write_string(event)
        out.write_string("\n")
      }
      None => ()
    }
    for line in frame.data.split("\n") {
      out.write_string("data: ")
      out.write_string(line.to_owned())
      out.write_string("\n")
    }
    out.write_string("\n")
  }
  out.to_string()
}
