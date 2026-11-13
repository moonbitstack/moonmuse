///|
/// A token counter over a vocabulary from moontoken. The count a model endpoint charges for
/// a conversation is the tokens of its text plus whatever the endpoint adds around them —
/// the role marker, the turn separator, the tool schemas — so the framing is a parameter
/// here rather than a number hidden in this file: an endpoint that publishes its rule can be
/// matched, and one that does not is counted as text.
///
/// Two limits are worth stating. An image is not text, so it is charged a flat `image`
/// amount (zero by default: not counted) rather than a number this library cannot derive
/// from a picture's size. And the endpoint's own answer is the authority: a count from a
/// different vocabulary is an estimate, and is useful for budgeting before the call, not for
/// billing after it.

///|
/// A counter over one vocabulary.
pub struct Tokens {
  tokenizer : @moontoken.Tokenizer
  /// Tokens the endpoint adds per message for its own framing.
  overhead : Int32
  /// Tokens one image costs. Zero means an image is not counted.
  image : Int32
}

///|
/// A counter over `tokenizer`. `overhead` is what the endpoint adds per message; the default
/// is the four tokens the chat formats reserve for the role and the separator.
pub fn Tokens::new(
  tokenizer~ : @moontoken.Tokenizer,
  overhead~ : Int32 = 4,
  image~ : Int32 = 0,
) -> Tokens {
  { tokenizer, overhead, image, }
}

///|
/// The tokens of `text`, which is the one number a tokenizer can give exactly.
pub fn Tokens::text(
  self : Tokens,
  text : StringView,
) -> Int32 raise @moonmuse.LlmError {
  self.tokenizer.count(text) catch {
    @refused.Malformed(what, at) =>
      raise @moonmuse.Decode(
        "cannot tokenize at " + at.to_string() + ": " + what,
      )
    @refused.Absent(what) => raise @moonmuse.Decode("no token for: " + what)
    @refused.Unsupported(what) =>
      raise @moonmuse.Unsupported("this vocabulary: " + what)
    @refused.Missing(byte) =>
      raise @moonmuse.Decode(
        "the vocabulary has no token for byte " + byte.to_string(),
      )
    @refused.Disallowed(what, at) =>
      raise @moonmuse.Decode(
        "a special token is disallowed at " + at.to_string() + ": " + what,
      )
  }
}

///|
/// The tokens of a tool declaration: its name, its description and its schema, which all
/// travel in the request.
fn Tokens::tool(
  self : Tokens,
  tool : @moonmuse.Tool,
) -> Int32 raise @moonmuse.LlmError {
  self.text(tool.name) +
  self.text(tool.description) +
  self.text(@json.dumps(tool.schema))
}

///|
pub impl @moonmuse.Counter for Tokens with fn count(self, request) {
  let mut total = 0
  for message in request.messages {
    total = total + self.overhead
    for part in message.parts {
      match part {
        @moonmuse.Part::Text(text) => total = total + self.text(text)
        @moonmuse.Part::Image(..) => total = total + self.image
        @moonmuse.Part::Call(name~, args~, ..) =>
          total = total + self.text(name) + self.text(@json.dumps(args))
        @moonmuse.Part::Result(content~, ..) =>
          total = total + self.text(content)
      }
    }
  }
  for tool in request.tools {
    total = total + self.tool(tool)
  }
  total
}

///|
pub extend Tokens with @moonmuse.Counter::{count}
