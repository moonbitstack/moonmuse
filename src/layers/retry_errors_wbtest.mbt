///|
test "describe_llm_error reads the status and body a bare Error hides" {
  let api : Error = @moonllm.ApiError(code=503, message="upstream overloaded")
  // What the language gives on its own: the constructor's name, nothing of the payload —
  // which is why the describer exists.
  assert_eq(@moonmuse.default_describe(api).contains("503".view()), false)
  let described = describe_llm_error(api)
  assert_eq(described.contains("503".view()), true)
  assert_eq(described.contains("upstream overloaded".view()), true)
  assert_eq(
    describe_llm_error(@moonllm.Transport("connection reset by peer")).contains(
      "connection reset".view(),
    ),
    true,
  )
  assert_eq(
    describe_llm_error(@moonllm.Decode("bad body")).contains("bad body".view()),
    true,
  )
  assert_eq(
    describe_llm_error(@moonllm.Stream("truncated")).contains(
      "truncated".view(),
    ),
    true,
  )
}

///|
test "describe_llm_error classifies moonllm errors against the default patterns" {
  let config = @moonmuse.RetryConfig::default()
  let retryable = e => config.matches(describe_llm_error(e))
  assert_eq(retryable(@moonllm.ApiError(code=429, message="slow down")), true)
  assert_eq(retryable(@moonllm.ApiError(code=503, message="unavailable")), true)
  assert_eq(retryable(@moonllm.Transport("connection reset by peer")), true)
  assert_eq(
    retryable(@moonllm.ApiError(code=400, message="bad request")),
    false,
  )
  assert_eq(retryable(@moonllm.ApiError(code=401, message="no key")), false)
  assert_eq(retryable(@moonllm.Decode("unexpected token")), false)
}
