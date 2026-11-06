///|
/// Bodies that are not JSON: an uploaded audio file, a generated image, a file object. They
/// share the transport with JSON calls but not the encoding, so they get their own functions
/// instead of a flag on `Call`.

///|
/// A `multipart/form-data` body and the content type that names its boundary.
pub struct Form {
  content_type : String
  body : Bytes
}

///|
/// The content type to send.
pub fn Form::content_type(self : Form) -> String {
  self.content_type
}

///|
/// The bytes to send.
pub fn Form::body(self : Form) -> Bytes {
  self.body
}

///|
/// A form of text fields and at most one file. The boundary is derived from the field names
/// and the file name, so the same form always produces the same bytes — which is what makes a
/// recorded request comparable to a fresh one.
pub fn form(
  fields : Array[(String, String)],
  file? : (String, String, Bytes),
) -> Form {
  let boundary = boundary_of(fields, file)
  let buffer = Buffer()
  for pair in fields {
    write_text(buffer, "--" + boundary + "\r\n")
    write_text(
      buffer,
      "Content-Disposition: form-data; name=\"" + pair.0 + "\"\r\n\r\n",
    )
    write_text(buffer, pair.1 + "\r\n")
  }
  match file {
    Some(entry) => {
      let (name, kind, data) = entry
      write_text(buffer, "--" + boundary + "\r\n")
      write_text(
        buffer,
        "Content-Disposition: form-data; name=\"file\"; filename=\"" +
        name +
        "\"\r\n",
      )
      write_text(buffer, "Content-Type: " + kind + "\r\n\r\n")
      buffer.write_bytes(data[:])
      write_text(buffer, "\r\n")
    }
    None => ()
  }
  write_text(buffer, "--" + boundary + "--\r\n")
  {
    content_type: "multipart/form-data; boundary=" + boundary,
    body: buffer.to_bytes(),
  }
}

///|
/// A boundary that cannot appear inside the parts: a fixed prefix and a number derived from
/// the form's own text.
fn boundary_of(
  fields : Array[(String, String)],
  file : (String, String, Bytes)?,
) -> String {
  let mut total = 0
  for pair in fields {
    for char in pair.0 {
      total = (total * 31 + char.to_int()) % 999_983
    }
    for char in pair.1 {
      total = (total * 31 + char.to_int()) % 999_983
    }
  }
  match file {
    Some(entry) =>
      for char in entry.0 {
        total = (total * 31 + char.to_int()) % 999_983
      }
    None => ()
  }
  "moonmuse-" + total.to_string()
}

///|
/// Append text as UTF-8 bytes.
fn write_text(buffer : Buffer, text : String) -> Unit {
  buffer.write_bytes(@utf8.encode(text)[:])
}
