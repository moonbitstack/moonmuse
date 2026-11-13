///|
/// The two wrappers, judged by what a recorder receives and what a registry exposes: the
/// names have to be the ones a backend matches on, and the content of a message has to be
/// absent unless the caller asked for it.

///|
/// A tracer whose spans a test can read back. The ids come from a counter rather than the
/// platform's entropy source, so a test needs nothing from the outside.
fn tracer(recorder : @trace.Recorder) -> @trace.Tracer {
  let mut next = 0
  @trace.Tracer::new(
    rand=width => {
      next = next + 1
      Bytes::make(width, (next % 250 + 1).to_byte())
    },
    sink=recorder,
    sampler=@trace.parent_based(root=@trace.always),
  )
}

///|
/// The value of an attribute, as the trace carries it.
fn attribute(span : @trace.SpanData, name : String) -> @trace.Value? {
  for pair in span.attributes {
    if pair.0 == name {
      return Some(pair.1)
    }
  }
  None
}

///|
/// A request with enough fields to be worth recording.
fn request() -> @moonmuse.Request {
  @moonmuse.Request::new(
    "gpt-test",
    [@moonmuse.Message::user("hello")],
    temperature=0.3,
    max_tokens=64,
    stop=["\n\n"],
  )
}

///|
/// A provider whose one answer reports a cost.
fn answer() -> @fake.Fake {
  @fake.Fake::new([
    @moonmuse.Reply::new(
      @moonmuse.Message::assistant("hi there"),
      usage=@moonmuse.Usage::new(7, 3, cached=1),
      raw={ "model": "gpt-test-2024" },
    ),
  ])
}

///|
async test "otel: a chat call is one client span with the request and the cost" {
  let recorder = @trace.Recorder::new()
  let provider = @otel.traced(answer(), tracer(recorder))
  let _ = provider.chat(request())
  let spans = recorder.spans()
  assert_eq(spans.length(), 1)
  let span = spans[0]
  assert_eq(span.name, "chat gpt-test")
  assert_eq(span.kind, @trace.Client)
  assert_eq(
    attribute(span, @semconv.gen_ai_operation_name),
    Some(@trace.Str("chat")),
  )
  assert_eq(
    attribute(span, @semconv.gen_ai_request_model),
    Some(@trace.Str("gpt-test")),
  )
  assert_eq(
    attribute(span, @semconv.gen_ai_request_max_tokens),
    Some(@trace.Int(64L)),
  )
  assert_eq(
    attribute(span, @semconv.gen_ai_usage_input_tokens),
    Some(@trace.Int(7L)),
  )
  assert_eq(
    attribute(span, @semconv.gen_ai_usage_output_tokens),
    Some(@trace.Int(3L)),
  )
  assert_eq(
    attribute(span, @semconv.gen_ai_usage_cache_read_input_tokens),
    Some(@trace.Int(1L)),
  )
  assert_eq(
    attribute(span, @semconv.gen_ai_response_model),
    Some(@trace.Str("gpt-test-2024")),
  )
  assert_eq(
    attribute(span, @semconv.gen_ai_response_finish_reasons),
    Some(@trace.Strs(["stop"])),
  )
  assert_eq(span.status, @trace.Ok)
}

///|
async test "otel: the message text is not recorded unless the caller asks" {
  let quiet = @trace.Recorder::new()
  let provider = @otel.traced(answer(), tracer(quiet))
  let _ = provider.chat(request())
  assert_eq(attribute(quiet.spans()[0], @semconv.gen_ai_input_messages), None)
  assert_eq(attribute(quiet.spans()[0], @semconv.gen_ai_output_messages), None)

  let loud = @trace.Recorder::new()
  let provider = @otel.traced(answer(), tracer(loud), content=true)
  let _ = provider.chat(request())
  assert_eq(
    attribute(loud.spans()[0], @semconv.gen_ai_input_messages),
    Some(@trace.Str("user: hello\n")),
  )
  assert_eq(
    attribute(loud.spans()[0], @semconv.gen_ai_output_messages),
    Some(@trace.Str("hi there")),
  )
}

///|
async test "otel: a failed call ends its span with the error and still raises" {
  let recorder = @trace.Recorder::new()
  let provider = @otel.traced(@fake.Fake::failing(429), tracer(recorder))
  let outcome = Ok(provider.chat(request())) catch { error => Err(error) }
  match outcome {
    Ok(_) => abort("a failing provider must raise")
    Err(@moonmuse.Status(code~, ..)) => assert_eq(code, 429)
    Err(_) => abort("expected a status")
  }
  let spans = recorder.spans()
  assert_eq(spans.length(), 1)
  match spans[0].status {
    @trace.Error(message) => assert_eq(message.contains("429"), true)
    _ => abort("a failed call must end its span as an error")
  }
  assert_eq(spans[0].events.length(), 1)
  assert_eq(spans[0].events[0].name, @semconv.gen_ai_client_operation_exception)
}

///|
async test "otel: a streamed call is one span that notes the first event" {
  let recorder = @trace.Recorder::new()
  let provider = @otel.traced(@fake.Fake::text("abcdefghij"), tracer(recorder))
  let seen = []
  let reply = provider.stream(request(), delta => seen.push(delta))
  assert_eq(reply.text(), "abcdefghij")
  assert_eq(seen.length(), 3)
  let spans = recorder.spans()
  assert_eq(spans.length(), 1)
  assert_eq(
    attribute(spans[0], @semconv.gen_ai_request_stream),
    Some(@trace.Bool(true)),
  )
  assert_eq(spans[0].events.length(), 1)
  assert_eq(
    spans[0].events[0].name,
    @semconv.gen_ai_client_inference_time_to_first_chunk,
  )
}

///|
/// The collected metrics, which is what an exporter would read back from the
/// provider: the names are the convention's, the attributes are the operation and
/// the model, and the token counters carry the cost the fake reported.
async test "otel: metrics carry the conventional names and the model attribute" {
  let recorder = @otlp.MetricRecorder::new()
  let provider_meter = @moontel.MeterProvider::new(sink=recorder, now=() => 0L)
  let meter = provider_meter.meter(name="moonmuse")
  let provider = @otel.metered(answer(), meter)
  let _ = provider.chat(request())
  let metrics = provider_meter.collect(at=1_000_000L)
  let input = metric(
    metrics, @semconv.gen_ai_client_inference_operation_input_tokens,
  )
  assert_eq(input.kind, @otlp.Sum(temporality=@otlp.Cumulative, monotonic=true))
  let point = input.points[0]
  assert_eq(point.point, @otlp.AsDouble(7.0))
  assert_eq(
    attribute_value(point.attributes, @semconv.gen_ai_operation_name),
    Some(@trace.Str("chat")),
  )
  assert_eq(
    attribute_value(point.attributes, @semconv.gen_ai_request_model),
    Some(@trace.Str("gpt-test")),
  )
  let output = metric(
    metrics, @semconv.gen_ai_client_inference_operation_output_tokens,
  )
  assert_eq(output.points[0].point, @otlp.AsDouble(3.0))
  let duration = metric(metrics, @semconv.gen_ai_client_operation_duration)
  assert_eq(duration.kind, @otlp.Histogram(temporality=@otlp.Cumulative))
}

///|
async test "otel: a streamed call records the wait for its first event" {
  let recorder = @otlp.MetricRecorder::new()
  let provider_meter = @moontel.MeterProvider::new(sink=recorder, now=() => 0L)
  let meter = provider_meter.meter(name="moonmuse")
  let provider = @otel.metered(@fake.Fake::text("abc"), meter)
  let _ = provider.stream(request(), _delta => ())
  let metrics = provider_meter.collect(at=1_000_000L)
  let first = metric(
    metrics, @semconv.gen_ai_client_inference_time_to_first_chunk,
  )
  let point = first.points[0]
  assert_eq(
    attribute_value(point.attributes, @semconv.gen_ai_operation_name),
    Some(@trace.Str("chat")),
  )
  assert_eq(
    attribute_value(point.attributes, @semconv.gen_ai_request_model),
    Some(@trace.Str("gpt-test")),
  )
}

///|
/// An embed call has no usage to count, so it records only its operation time, and the
/// label reads `embeddings` rather than `chat`: a metric with a chat label on it would put
/// the two operations in one series.
async test "otel: an embed call records its duration but no token counter" {
  let recorder = @otlp.MetricRecorder::new()
  let provider_meter = @moontel.MeterProvider::new(sink=recorder, now=() => 0L)
  let meter = provider_meter.meter(name="moonmuse")
  let provider = @otel.metered(@fake.Fake::new([]), meter)
  let vectors = provider.embed("gpt-test", ["hello", "world"])
  assert_eq(vectors.length(), 2)
  let metrics = provider_meter.collect(at=1_000_000L)
  let duration = metric(metrics, @semconv.gen_ai_client_operation_duration)
  let point = duration.points[0]
  assert_eq(
    attribute_value(point.attributes, @semconv.gen_ai_operation_name),
    Some(@trace.Str("embeddings")),
  )
  assert_eq(
    attribute_value(point.attributes, @semconv.gen_ai_request_model),
    Some(@trace.Str("gpt-test")),
  )
  match find(metrics, @semconv.gen_ai_client_inference_operation_input_tokens) {
    Some(input) => assert_eq(input.points.length(), 0)
    None => ()
  }
}

///|
/// A metric by its conventional name, or a clear failure if the collection missed it.
fn metric(metrics : Array[@otlp.Metric], name : String) -> @otlp.Metric {
  match find(metrics, name) {
    Some(metric) => metric
    None => abort("metric not collected: " + name)
  }
}

///|
/// A metric by its conventional name, if the collection has it.
fn find(metrics : Array[@otlp.Metric], name : String) -> @otlp.Metric? {
  for metric in metrics {
    if metric.name == name {
      return Some(metric)
    }
  }
  None
}

///|
/// The value of a metric attribute, by the convention's key.
fn attribute_value(
  attributes : Array[(String, @trace.Value)],
  name : String,
) -> @trace.Value? {
  for pair in attributes {
    if pair.0 == name {
      return Some(pair.1)
    }
  }
  None
}
