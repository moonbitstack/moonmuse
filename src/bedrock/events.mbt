///|
/// The `application/vnd.amazon.eventstream` framing: what `converse-stream` answers in. A
/// frame is a length, a headers block, a payload and a CRC; the payload is JSON with one
/// member whose name is the event. The decoder takes whatever pieces the network delivers,
/// so a frame split across two reads is not a frame yet.

///|
/// One decoded frame.
pub(all) struct Event {
  /// The `:event-type` header, which names the event inside the payload too.
  kind : String
  payload : Json
}

///|
/// A frame as it arrives, split into the pieces the consumer sees.
pub(all) struct Frame {
  kind : String
  payload : Bytes
}

///|
/// The decoder's buffer. `push` returns the frames that are complete.
pub struct Reader {
  mut buf : Bytes
}

///|
/// A decoder with nothing buffered.
pub fn Reader::new() -> Reader {
  { buf: Bytes::new(0), }
}

///|
/// Take one piece of the stream and return the frames it completed.
pub fn Reader::push(self : Reader, data : BytesView) -> Array[Frame] {
  let joined = if self.buf.length() == 0 &&
    data.length() == data.to_owned().length() {
    data.to_owned()
  } else {
    let buffer = Buffer()
    buffer.write_bytes(self.buf[:])
    buffer.write_bytes(data[:])
    buffer.to_bytes()
  }
  let frames = []
  let mut at = 0
  while at + 12 <= joined.length() {
    let total = read_u32(joined, at)
    if total < 16 || at + total > joined.length() {
      break
    }
    let headers_length = read_u32(joined, at + 4)
    let header_start = at + 12
    let header_end = header_start + headers_length
    let payload_end = at + total - 4
    let headers = read_headers(joined, header_start, header_end)
    frames.push(Frame::{
      kind: headers.get(":event-type").unwrap_or(""),
      payload: joined[header_start + headers_length:payload_end].to_owned(),
    })
    at = at + total
  }
  self.buf = joined[at:].to_owned()
  frames
}

///|
/// Whether anything is left over, which a well-formed stream never leaves.
pub fn Reader::is_empty(self : Reader) -> Bool {
  self.buf.length() == 0
}

///|
/// A frame's payload as the event it names.
pub fn Frame::event(self : Frame) -> Event raise @moonmuse.LlmError {
  let payload = @json.parse(@utf8.decode_lossy(self.payload[:])) catch {
    _ =>
      raise @moonmuse.Decode(
        "an event payload is not JSON: " + @utf8.decode_lossy(self.payload[:]),
      )
  }
  { kind: self.kind, payload, }
}

///|
/// A big-endian 32-bit length.
fn read_u32(data : Bytes, at : Int32) -> Int32 {
  (data[at].to_int() << 24) |
  (data[at + 1].to_int() << 16) |
  (data[at + 2].to_int() << 8) |
  data[at + 3].to_int()
}

///|
/// The headers of a frame: one byte of name length, the name, one byte of type, two bytes of
/// value length, the value. Only the string type appears in the events this reads.
fn read_headers(
  data : Bytes,
  start : Int32,
  end : Int32,
) -> Map[String, String] {
  let headers = Map([])
  let mut at = start
  while at < end {
    let name_length = data[at].to_int()
    at = at + 1
    if at + name_length + 3 > end {
      break
    }
    let name = @utf8.decode_lossy(data[at:at + name_length])
    at = at + name_length
    let kind = data[at].to_int()
    at = at + 1
    let value_length = (data[at].to_int() << 8) | data[at + 1].to_int()
    at = at + 2
    if at + value_length > end {
      break
    }
    let value = @utf8.decode_lossy(data[at:at + value_length])
    at = at + value_length
    // Type 7 is a string; the rest (bytes, numbers, timestamps) do not appear in the events
    // this reads, and reading one as text would be worse than skipping it.
    if kind == 7 {
      headers[name] = value
    }
  }
  headers
}

///|
/// The CRC-32 the framing checks, in the reflected IEEE form the protocol names.
pub fn crc32(data : BytesView) -> Int32 {
  // The shift is logical, so the register is unsigned: an arithmetic shift on a signed
  // integer would drag the sign bit down and produce a checksum that is merely wrong.
  let mut crc : UInt32 = 0xFFFF_FFFF
  for byte in data {
    crc = crc ^ byte.to_uint()
    for i = 0; i < 8; i = i + 1 {
      if (crc & 1) == 1 {
        crc = (crc >> 1) ^ 0xEDB8_8320
      } else {
        crc = crc >> 1
      }
      let _ = i
    }
  }
  (crc ^ 0xFFFF_FFFF).reinterpret_as_int()
}

///|
/// A frame for a test or a stub server: the layout the protocol writes, CRC included.
pub fn encode_frame(kind : String, payload : Bytes) -> Bytes {
  let headers = Buffer()
  write_header(headers, ":event-type", kind)
  write_header(headers, ":content-type", "application/json")
  let header_bytes = headers.to_bytes()
  let total = 12 + header_bytes.length() + payload.length() + 4
  let out = Buffer()
  write_u32(out, total)
  write_u32(out, header_bytes.length())
  let prelude = out.to_bytes()
  write_u32(out, crc32(prelude[:]))
  out.write_bytes(header_bytes[:])
  out.write_bytes(payload[:])
  let so_far = out.to_bytes()
  write_u32(out, crc32(so_far[:]))
  out.to_bytes()
}

///|
/// One string header: its name length, the name, the string type, the value length and the
/// value. A string value is at most 65535 bytes, which the two-byte length says.
fn write_header(out : Buffer, name : String, value : String) -> Unit {
  out.write_byte(name.length().to_byte())
  out.write_bytes(@utf8.encode(name)[:])
  out.write_byte(b'\x07')
  let size = value.length()
  out.write_byte(((size >> 8) & 0xFF).to_byte())
  out.write_byte((size & 0xFF).to_byte())
  out.write_bytes(@utf8.encode(value)[:])
}

///|
/// A big-endian 32-bit length written into `out`.
fn write_u32(out : Buffer, value : Int32) -> Unit {
  out.write_byte((value >> 24).to_byte())
  out.write_byte(((value >> 16) & 0xFF).to_byte())
  out.write_byte(((value >> 8) & 0xFF).to_byte())
  out.write_byte((value & 0xFF).to_byte())
}
