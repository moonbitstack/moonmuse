///|
/// A traced call, exported two ways. With an `host:port` argument it sends the span over
/// OTLP/gRPC, which is what the semantic-conventions checker listens for; without one it
/// writes the same payload as OTLP JSON on stdout, which is what a person reads.
///
///     moon run src/examples/05-observe --target native
///     moon run src/examples/05-observe --target native -- 127.0.0.1:4317
///
/// The checker is a program, so this is a program rather than a test: CI starts the checker,
/// runs this against it, and reads the verdict.

///|
/// A tracer whose ids are a counter, so a run is the same every time.
fn tracer(sink : &@trace.Sink) -> @trace.Tracer {
  let mut next = 0
  @trace.Tracer::new(
    rand=width => {
      next = next + 1
      Bytes::make(width, (next % 250 + 1).to_byte())
    },
    sink~,
    sampler=@trace.parent_based(root=@trace.always),
  )
}

///|
/// The one call this program makes, through a sink the caller supplies.
async fn trace_one(sink : &@trace.Sink) -> Unit {
  let provider = @otel.traced(
    @fake.Fake::new([
      @moonmuse.Reply::new(
        @moonmuse.Message::assistant("hello"),
        usage=@moonmuse.Usage::new(7, 3),
      ),
    ]),
    tracer(sink),
  )
  let _ = provider.chat(
    @moonmuse.Request::new(
      "gpt-4o-mini",
      [@moonmuse.Message::user("hi")],
      temperature=0.2,
      max_tokens=64,
    ),
  )
}

///|
/// The clock the exporter batches on, in milliseconds.
fn millis() -> Int64 {
  @async.now()
}

///|
/// Octets for an exporter that jitters its retries. A generator seeded from the clock is
/// enough for a delay and is not used for anything a secret depends on.
fn random_bytes(width : Int32) -> Bytes {
  let seed = @async.now()
  let buffer = Buffer()
  for index = 0; index < width; index = index + 1 {
    let mixed = (
        seed * 6_364_136_223_846_793_005L +
        index.to_int64() * 1_442_695_040_888_963_407L
      ) >>
      33
    buffer.write_byte((mixed & 0xFF).to_byte())
  }
  buffer.to_bytes()
}

///|
async fn main {
  let arguments = @env.args()
  if arguments.length() > 1 {
    export_over_grpc(arguments[1])
  } else {
    let recorder = @trace.Recorder::new()
    trace_one(recorder)
    let resource = @otlp.Resource::of_service("moonmuse-example")
    println(
      @otlp.encode_traces(
        recorder.spans(),
        resource~,
        scope=@otlp.Scope::new(name="moonmuse/otel", version="0.1.0"),
      ),
    )
  }
}

///|
/// Send the span to an OTLP/gRPC collector and wait for it to be accepted.
async fn export_over_grpc(address : String) -> Unit {
  let (host, port) = host_and_port(address)
  let transport = @grpc.GrpcTransport::connect(host~, port~)
  let exporter = @otlp.TraceExporter::new(
    transport~,
    endpoint="http://" + address,
    // The checker is given the GenAI registry alone, which does not define the base resource
    // attributes: a `service.name` here would be reported as an attribute the registry has
    // never heard of. The JSON form below carries one, because a person is reading that.
    resource=@otlp.Resource::new(attributes=[]),
    format=@otlp.BodyFormat::Protobuf,
    now=millis,
    rand=random_bytes,
    attempts=5,
  )
  trace_one(exporter)
  let report = exporter.flush()
  println(
    "delivered " +
    report.delivered.to_string() +
    ", rejected " +
    report.rejected.to_string() +
    ", dropped " +
    report.dropped.to_string(),
  )
  if report.delivered == 0 {
    abort("the collector did not take the span")
  }
}

///|
/// `host:port` split at the last colon, which is where the port is even for an IPv6 literal.
fn host_and_port(address : String) -> (String, Int32) {
  let at = match address.rev_find(":") {
    Some(at) => at
    None => abort("an address needs a port: " + address)
  }
  let host = address.exact_view(start=0, end=at).to_owned()
  let port = @moonmuse.parse_int_lossy(
    address.exact_view(start=at + 1).to_owned(),
  )
  (host, port)
}
