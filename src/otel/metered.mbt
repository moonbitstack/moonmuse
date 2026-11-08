///|
/// A provider that reports what its calls cost, as Prometheus metrics with the names the
/// OpenTelemetry GenAI conventions define. A trace answers "what happened to this one call";
/// a metric answers "how many calls, how long, how many tokens", which is the question an
/// operator asks when nothing is wrong yet.
///
/// The instrument names are the convention's: `gen_ai.client.operation.duration` for the
/// time a call took and the token counters for what it spent. The convention's older
/// `gen_ai.client.token.usage` was retired upstream in favour of one counter per direction,
/// so that is what is written here — a dashboard that wants the old name can sum them.

///|
/// A provider wrapped in metrics.
pub struct Metered {
  inner : &@moonmuse.Provider
  /// How long a call took, in seconds.
  duration : @moonp8s.Family[@moonp8s.Histogram]
  /// Input tokens per call.
  input : @moonp8s.Family[@moonp8s.Counter]
  /// Output tokens per call.
  output : @moonp8s.Family[@moonp8s.Counter]
  /// The wait before the first event of a streamed call, in seconds.
  first : @moonp8s.Family[@moonp8s.Histogram]
}

///|
/// The exposition's spelling of a convention name: OpenMetrics allows letters, digits,
/// colons and underscores, so the dots a semantic convention writes become underscores.
/// This is the same translation the OpenTelemetry Prometheus exporter makes, and it is what
/// a dashboard written against either one already queries.
fn prometheus(name : String) -> String {
  let out = StringBuilder()
  for char in name {
    if char == '.' || char == '-' {
      out.write_char('_')
    } else {
      out.write_char(char)
    }
  }
  out.to_string()
}

///|
/// Report `provider`'s calls into `registry`. The instruments are created once, here, so a
/// registry that already has them refuses the second wrapper rather than mixing two series.
pub fn metered(
  provider : &@moonmuse.Provider,
  registry : @moonp8s.Registry,
) -> &@moonmuse.Provider {
  let labels = ["operation", "model"]
  let duration = @moonp8s.Family::new(labels, () => @moonp8s.Histogram::new()) catch {
    error => abort("metric refused: " + error.message())
  }
  registry.register(
    prometheus(@semconv.gen_ai_client_operation_duration),
    "Time a model call took.",
    duration,
  ) catch {
    error => abort("metric refused: " + error.message())
  }
  let input = @moonp8s.Family::new(labels, () => @moonp8s.Counter::new()) catch {
    error => abort("metric refused: " + error.message())
  }
  registry.register(
    prometheus(@semconv.gen_ai_client_inference_operation_input_tokens),
    "Tokens a model call was given.",
    input,
  ) catch {
    error => abort("metric refused: " + error.message())
  }
  let output = @moonp8s.Family::new(labels, () => @moonp8s.Counter::new()) catch {
    error => abort("metric refused: " + error.message())
  }
  registry.register(
    prometheus(@semconv.gen_ai_client_inference_operation_output_tokens),
    "Tokens a model call produced.",
    output,
  ) catch {
    error => abort("metric refused: " + error.message())
  }
  let first = @moonp8s.Family::new(labels, () => @moonp8s.Histogram::new()) catch {
    error => abort("metric refused: " + error.message())
  }
  registry.register(
    prometheus(@semconv.gen_ai_client_inference_time_to_first_chunk),
    "Time from asking to the first event of a streamed answer.",
    first,
  ) catch {
    error => abort("metric refused: " + error.message())
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
  let labels = [operation, model]
  let seconds = elapsed / 1_000_000.0
  let duration = self.duration.labels(labels) catch { _ => return }
  duration.observe(seconds)
  match first {
    Some(wait) => {
      let wait = wait / 1_000_000.0
      let series = self.first.labels(labels) catch { _ => return }
      series.observe(wait)
    }
    None => ()
  }
  match reply {
    Some(reply) => {
      match reply.usage.input {
        Some(value) => {
          let counter = self.input.labels(labels) catch { _ => return }
          counter.inc(by=value.to_double()) catch {
            _ => ()
          }
        }
        None => ()
      }
      match reply.usage.output {
        Some(value) => {
          let counter = self.output.labels(labels) catch { _ => return }
          counter.inc(by=value.to_double()) catch {
            _ => ()
          }
        }
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
