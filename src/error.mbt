///|
/// Everything a provider call can fail with. The four cases are the only distinctions
/// a caller can act on: retry, parse differently, or stop asking.
#derive(Eq, Debug)
pub(all) suberror LlmError {
  /// The endpoint answered with a non-success status. `retry_after` is the seconds the
  /// endpoint asked to be left alone for, when it said.
  Status(code~ : Int32, body~ : String, retry_after~ : Int64?)
  /// The stream broke: a frame that could not be read, or one that arrived out of order.
  Stream(String)
  /// The body was not the shape this dialect promised.
  Decode(String)
  /// The endpoint does not offer this capability at all, such as a chat-only server
  /// asked for embeddings.
  Unsupported(String)
}

///|
/// A one-line description, for logs and for retry classification.
pub fn LlmError::describe(self : LlmError) -> String {
  match self {
    Status(code~, body~, ..) => "http " + code.to_string() + ": " + body
    Stream(message) => "stream: " + message
    Decode(message) => "decode: " + message
    Unsupported(what) => "unsupported: " + what
  }
}

///|
/// Whether asking again could plausibly succeed. A rate limit, a server fault and a
/// dropped stream qualify; a malformed body or a missing capability does not.
pub fn LlmError::is_retryable(self : LlmError) -> Bool {
  match self {
    Status(code~, ..) =>
      code == 408 || code == 409 || code == 429 || code >= 500
    Stream(_) => true
    Decode(_) => false
    Unsupported(_) => false
  }
}

///|
/// The wait the endpoint asked for, when it named one.
pub fn LlmError::retry_after(self : LlmError) -> Int64? {
  match self {
    Status(retry_after~, ..) => retry_after
    _ => None
  }
}

///|
pub extend LlmError with Eq::{not_equal, equal}

///|
pub extend LlmError with Debug::{to_repr}
