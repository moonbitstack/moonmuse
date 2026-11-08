///|
/// How many tokens a request costs, before anyone answers it. A tokenizer is a large table
/// that most callers do not need, so the contract lives here and the implementation that
/// loads a vocabulary lives in `moonmuse/count`: a gateway is handed a counter, and a
/// deployment that has no vocabulary says so instead of inventing a number.
pub(open) trait Counter {
  fn count(Self, Request) -> Int32 raise LlmError
}
