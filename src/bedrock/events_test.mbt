///|
/// The event stream, judged by the layout the protocol defines: a length, a header block, a
/// payload and a CRC. The reference for the checksum is zlib's, which every implementation of
/// CRC-32 agrees with.

///|
test "bedrock: the checksum is the one zlib computes" {
  // The standard check value: CRC-32 of "123456789" is 0xcbf43926, which as a signed 32-bit
  // number is what this returns.
  assert_eq(@bedrock.crc32(@utf8.encode("123456789")[:]), -873_187_034)
  assert_eq(@bedrock.crc32(Bytes::new(0)[:]), 0)
}

///|
test "bedrock: a frame decodes to the event it carries" {
  let frame = @bedrock.encode_frame(
    "contentBlockDelta",
    @utf8.encode("{\"delta\":{\"text\":\"hi\"}}"),
  )
  let reader = @bedrock.Reader::new()
  let frames = reader.push(frame)
  assert_eq(frames.length(), 1)
  assert_eq(frames[0].kind, "contentBlockDelta")
  assert_eq(reader.is_empty(), true)
  let event = frames[0].event()
  assert_eq(event.kind, "contentBlockDelta")
  assert_eq(
    @json.parse("{\"delta\":{\"text\":\"hi\"}}") catch {
      _ => Json::null()
    },
    event.payload,
  )
}

///|
/// A frame split anywhere is not a frame until its last byte arrives, which is what a stream
/// over a network does to it.
test "bedrock: a frame split across two reads is one frame" {
  let frame = @bedrock.encode_frame(
    "messageStop",
    @utf8.encode("{\"stopReason\":\"end_turn\"}"),
  )
  let size = frame.length()
  let reader = @bedrock.Reader::new()
  let first = Bytes::new(0)
  let head = Buffer()
  head.write_bytes(frame[0:7])
  assert_eq(reader.push(head.to_bytes()).length(), 0)
  let tail = Buffer()
  tail.write_bytes(frame[7:size])
  let frames = reader.push(tail.to_bytes())
  assert_eq(frames.length(), 1)
  assert_eq(frames[0].kind, "messageStop")
  let _ = first
}

///|
test "bedrock: two frames in one read are two frames" {
  let first = @bedrock.encode_frame("messageStart", @utf8.encode("{}"))
  let second = @bedrock.encode_frame(
    "metadata",
    @utf8.encode("{\"usage\":{\"inputTokens\":3}}"),
  )
  let joined = Buffer()
  joined.write_bytes(first[:])
  joined.write_bytes(second[:])
  let frames = @bedrock.Reader::new().push(joined.to_bytes())
  assert_eq(frames.length(), 2)
  assert_eq(frames[0].kind, "messageStart")
  assert_eq(frames[1].kind, "metadata")
}

///|
test "bedrock: a truncated frame is kept until the rest arrives" {
  let frame = @bedrock.encode_frame("messageStart", @utf8.encode("{}"))
  let reader = @bedrock.Reader::new()
  assert_eq(reader.push(frame[0:frame.length() - 4]).length(), 0)
  assert_eq(reader.is_empty(), false)
  assert_eq(reader.push(frame[frame.length() - 4:frame.length()]).length(), 1)
}
