///|
/// A provider that reports what its calls cost, as OpenTelemetry metrics with the
/// names the semantic conventions define. A trace answers "what happened to this
/// one call"; a metric answers "how many calls, how long, how many tokens", which
/// is the question an operator asks when nothing is wrong yet.
///
/// The instrument names are the convention's: `gen_ai.client.operation.duration`
/// for the time a call took and the token counters for what it spent. The
/// convention's older `gen_ai.client.token.usage` was retired upstream in favour
/// of one counter per direction, so that is what is written here — a dashboard
/// that wants the old name can sum them. The dotted names are kept exactly as the
/// conventions spell them; an exporter translates them to its wire, not this code.

///|
/// A provider wrapped in metrics.
pub struct Metered {
  inner : &@moonmuse.Provider
  /// How long a call took, in seconds.
  duration : @moontel.Histogram
  /// Input tokens per call.
  input : @moontel.Counter
  /// Output tokens per call.
  output : @moontel.Counter
  /// The wait before the first event of a streamed call, in seconds.
  first : @moontel.Histogram
}

///|
/// Report `provider`'s calls into `meter`. The instruments are created once, here,
/// named by the GenAI semantic conventions, so a backend matches on the names it
/// already matches on for every other client — no Prometheus translation, no
/// renaming at the exporter.
pub fn metered(
  provider : &@moonmuse.Provider,
  meter : @moontel.Meter,
) -> &@moonmuse.Provider {
  let duration_name = @semconv.gen_ai_client_operation_duration
  let input_name = @semconv.gen_ai_client_inference_operation_input_tokens
  let output_name = @semconv.gen_ai_client_inference_operation_output_tokens
  let first_name = @semconv.gen_ai_client_inference_time_to_first_chunk
  let duration = meter.histogram(
    duration_name,
    description="Time a model call took, in seconds.",
  ) catch {
    _ => abort("metric refused: " + duration_name)
  }
  let input = meter.counter(
    input_name,
    description="Tokens a model call was given.",
  ) catch {
    _ => abort("metric refused: " + input_name)
  }
  let output = meter.counter(
    output_name,
    description="Tokens a model call produced.",
  ) catch {
    _ => abort("metric refused: " + output_name)
  }
  let first = meter.histogram(
    first_name,
    description="Time from asking to the first event of a streamed answer, in seconds.",
  ) catch {
    _ => abort("metric refused: " + first_name)
  }
  Metered::{ inner: provider, duration, input, output, first, }
}

///|
/// Record one finished call. `elapsed` is the time it took and `first` the wait before its
/// first event, both in microseconds, which is the resolution the monotonic clock reads in.
fn Metered::observe(
  self : Metered,
  operation : String,
  model : String,
  elapsed : Double,
  first : Double?,
  reply : @moonmuse.Reply?,
) -> Unit {
  let labels = @moontel.Attributes::new(entries=[
    (@semconv.gen_ai_operation_name, @trace.Str(operation)),
    (@semconv.gen_ai_request_model, @trace.Str(model)),
  ])
  let seconds = elapsed / 1_000_000.0
  self.duration.record(seconds, attributes=labels)
  match first {
    Some(wait) => {
      let wait = wait / 1_000_000.0
      self.first.record(wait, attributes=labels)
    }
    None => ()
  }
  match reply {
    Some(reply) => {
      match reply.usage.input {
        Some(value) => self.input.add(value.to_double(), attributes=labels)
        None => ()
      }
      match reply.usage.output {
        Some(value) => self.output.add(value.to_double(), attributes=labels)
        None => ()
      }
    }
    None => ()
  }
}

///|
pub impl @moonmuse.Provider for Metered with fn chat(self, request) {
  let started = @bench.monotonic_clock_start()
  let outcome = Ok(self.inner.chat(request)) catch { error => Err(error) }
  match outcome {
    Ok(reply) => {
      self.observe(
        "chat",
        request.model,
        @bench.monotonic_clock_end(started),
        None,
        Some(reply),
      )
      reply
    }
    Err(error) => {
      self.observe(
        "chat",
        request.model,
        @bench.monotonic_clock_end(started),
        None,
        None,
      )
      raise error
    }
  }
}

///|
pub impl @moonmuse.Provider for Metered with fn stream(self, request, on_delta) {
  let started = @bench.monotonic_clock_start()
  let mut first : Double? = None
  let outcome = Ok(
    self.inner.stream(request, delta => {
      if first is None {
        first = Some(@bench.monotonic_clock_end(started))
      }
      on_delta(delta)
    }),
  ) catch {
    error => Err(error)
  }
  match outcome {
    Ok(reply) => {
      self.observe(
        "chat",
        request.model,
        @bench.monotonic_clock_end(started),
        first,
        Some(reply),
      )
      reply
    }
    Err(error) => {
      self.observe(
        "chat",
        request.model,
        @bench.monotonic_clock_end(started),
        first,
        None,
      )
      raise error
    }
  }
}

///|
pub impl @moonmuse.Provider for Metered with fn embed(self, model, inputs) {
  let started = @bench.monotonic_clock_start()
  let outcome = Ok(self.inner.embed(model, inputs)) catch {
    error => Err(error)
  }
  match outcome {
    Ok(vectors) => {
      self.observe(
        "embeddings",
        model,
        @bench.monotonic_clock_end(started),
        None,
        None,
      )
      vectors
    }
    Err(error) => {
      self.observe(
        "embeddings",
        model,
        @bench.monotonic_clock_end(started),
        None,
        None,
      )
      raise error
    }
  }
}

///|
pub impl @moonmuse.Provider for Metered with fn models(self) {
  @moonmuse.Provider::models(self.inner)
}

///|
pub extend Metered with @moonmuse.Provider::{chat, stream, embed, models}
