///|
/// A provider that traces its calls by the OpenTelemetry GenAI conventions. One span covers
/// one call: the request on the way in, the answer or the error on the way out. What the
/// answer said is not recorded unless the caller asks, because a message body is the user's
/// data — the convention makes the same distinction, and a trace that carries it by default
/// is a trace that leaks.
///
/// The attribute and metric names are taken from `moontel/semconv`, which generates them
/// from a pinned upstream registry; a name written here by hand is a name a dashboard will
/// not match.

///|
/// A provider wrapped in tracing.
pub struct Traced {
  /// The provider being observed.
  inner : &@moonmuse.Provider
  tracer : @trace.Tracer
  /// Whether message bodies become attributes. Off by default.
  content : Bool
}

///|
/// Observe `provider` through `tracer`. Spans are named after the operation and the model,
/// which is how the convention names them.
pub fn traced(
  provider : &@moonmuse.Provider,
  tracer : @trace.Tracer,
  content~ : Bool = false,
) -> &@moonmuse.Provider {
  Traced::{ inner: provider, tracer, content, }
}

///|
/// A span for one call, or nothing when the tracer cannot mint ids — observation must never
/// be the reason a call fails.
fn Traced::begin(
  self : Traced,
  operation : String,
  model : String,
  attributes : Array[(String, @trace.Value)],
) -> @trace.Span? {
  let name = if model == "" { operation } else { operation + " " + model }
  let all = [
    (@semconv.gen_ai_operation_name, @trace.Str(operation)),
    ..attributes,
  ]
  Some(
    self.tracer.start(name, kind=@trace.Client, at=wall_nanos(), attributes=all),
  ) catch {
    _ => None
  }
}

///|
/// Close a span with what the call produced.
fn Traced::end(
  self : Traced,
  span : @trace.Span?,
  reply : @moonmuse.Reply?,
  error : @moonmuse.LlmError?,
) -> Unit {
  match span {
    None => ()
    Some(span) => {
      match reply {
        Some(reply) => {
          report_reply(span, reply, self.content)
          span.set_status(@trace.Ok)
        }
        None => ()
      }
      match error {
        Some(error) => {
          let message = error.describe()
          span.set_status(@trace.Error(message))
          span.add_event(
            @semconv.gen_ai_client_operation_exception,
            attributes=[("exception.message", @trace.Str(message))],
            at=wall_nanos(),
          )
        }
        None => ()
      }
      span.finish(at=wall_nanos())
    }
  }
}

///|
/// What the answer adds to the span: the model that answered, why it stopped, what it cost,
/// and — only when the caller asked — what was said.
fn report_reply(
  span : @trace.Span,
  reply : @moonmuse.Reply,
  content : Bool,
) -> Unit {
  let model = @moonmuse.json_string_or(reply.raw, "model", "")
  if model != "" {
    span.set_attribute(@semconv.gen_ai_response_model, @trace.Str(model))
  }
  span.set_attribute(
    @semconv.gen_ai_response_finish_reasons,
    @trace.Strs([finish_code(reply.finish)]),
  )
  match reply.usage.input {
    Some(value) =>
      span.set_attribute(
        @semconv.gen_ai_usage_input_tokens,
        @trace.Int(value.to_int64()),
      )
    None => ()
  }
  match reply.usage.output {
    Some(value) =>
      span.set_attribute(
        @semconv.gen_ai_usage_output_tokens,
        @trace.Int(value.to_int64()),
      )
    None => ()
  }
  match reply.usage.cached {
    Some(value) =>
      span.set_attribute(
        @semconv.gen_ai_usage_cache_read_input_tokens,
        @trace.Int(value.to_int64()),
      )
    None => ()
  }
  if content {
    let text = reply.text()
    if text != "" {
      span.set_attribute(@semconv.gen_ai_output_messages, @trace.Str(text))
    }
  }
}

///|
/// The finish reason as the convention spells it.
fn finish_code(finish : @moonmuse.Finish) -> String {
  match finish {
    @moonmuse.Stop => "stop"
    @moonmuse.Length => "length"
    @moonmuse.Calls => "tool_calls"
    @moonmuse.Filtered => "content_filter"
    @moonmuse.Other(text) => text
  }
}

///|
/// The request's own attributes, which is everything a trace needs before the answer exists.
fn request_attributes(
  request : @moonmuse.Request,
) -> Array[(String, @trace.Value)] {
  let attributes : Array[(String, @trace.Value)] = [
    (@semconv.gen_ai_request_model, @trace.Str(request.model)),
  ]
  match request.max_tokens {
    Some(value) =>
      attributes.push(
        (@semconv.gen_ai_request_max_tokens, @trace.Int(value.to_int64())),
      )
    None => ()
  }
  match request.temperature {
    Some(value) =>
      attributes.push(
        (@semconv.gen_ai_request_temperature, @trace.Double(value)),
      )
    None => ()
  }
  if !request.stop.is_empty() {
    attributes.push(
      (@semconv.gen_ai_request_stop_sequences, @trace.Strs(request.stop)),
    )
  }
  if !request.tools.is_empty() {
    attributes.push(
      (
        @semconv.gen_ai_tool_definitions,
        @trace.Strs(request.tools.map(tool => tool.name)),
      ),
    )
  }
  attributes
}

///|
/// The message bodies as one string, when the caller asked for content. This is a debug aid:
/// the convention has no shape for a whole conversation and a backend that indexes it needs
/// one the deployment chose, not one this library made up.
fn messages_text(messages : Array[@moonmuse.Message]) -> String {
  let out = StringBuilder()
  for message in messages {
    out.write_string(role_code(message.role))
    out.write_string(": ")
    out.write_string(message.text_content(separator="\n"))
    out.write_string("\n")
  }
  out.to_string()
}

///|
/// A role as the convention spells it.
fn role_code(role : @moonmuse.Role) -> String {
  match role {
    @moonmuse.System => "system"
    @moonmuse.User => "user"
    @moonmuse.Assistant => "assistant"
    @moonmuse.Tool => "tool"
  }
}

///|
pub impl @moonmuse.Provider for Traced with fn chat(self, request) {
  let span = self.begin("chat", request.model, request_attributes(request))
  match span {
    Some(span) =>
      if self.content {
        span.set_attribute(
          @semconv.gen_ai_input_messages,
          @trace.Str(messages_text(request.messages)),
        )
      }
    None => ()
  }
  let outcome = Ok(self.inner.chat(request)) catch { error => Err(error) }
  match outcome {
    Ok(reply) => {
      self.end(span, Some(reply), None)
      reply
    }
    Err(error) => {
      self.end(span, None, Some(error))
      raise error
    }
  }
}

///|
/// A streamed call is one span, opened before the first event and closed after the last, with
/// the time to the first event recorded as an event so a trace shows where the wait was.
pub impl @moonmuse.Provider for Traced with fn stream(self, request, on_delta) {
  let attributes = request_attributes(request)
  attributes.push((@semconv.gen_ai_request_stream, @trace.Bool(true)))
  let span = self.begin("chat", request.model, attributes)
  let mut first = -1L
  let outcome = Ok(
    self.inner.stream(request, delta => {
      if first < 0 {
        match delta {
          Text(_) | CallStart(..) => {
            first = wall_nanos()
            match span {
              Some(span) =>
                span.add_event(
                  @semconv.gen_ai_client_inference_time_to_first_chunk,
                  at=first,
                )
              None => ()
            }
          }
          _ => ()
        }
      }
      on_delta(delta)
    }),
  ) catch {
    error => Err(error)
  }
  match outcome {
    Ok(reply) => {
      self.end(span, Some(reply), None)
      reply
    }
    Err(error) => {
      self.end(span, None, Some(error))
      raise error
    }
  }
}

///|
pub impl @moonmuse.Provider for Traced with fn embed(self, model, inputs) {
  let span = self.begin("embeddings", model, [
    (@semconv.gen_ai_request_model, @trace.Str(model)),
  ])
  let outcome = Ok(self.inner.embed(model, inputs)) catch {
    error => Err(error)
  }
  match outcome {
    Ok(vectors) => {
      match span {
        Some(span) =>
          if vectors.length() > 0 {
            span.set_attribute(
              @semconv.gen_ai_embeddings_dimension_count,
              @trace.Int(vectors[0].length().to_int64()),
            )
          }
        None => ()
      }
      self.end(span, None, None)
      vectors
    }
    Err(error) => {
      self.end(span, None, Some(error))
      raise error
    }
  }
}

///|
pub impl @moonmuse.Provider for Traced with fn models(self) {
  let span = self.begin("models", "", [])
  let outcome = Ok(self.inner.models()) catch { error => Err(error) }
  match outcome {
    Ok(models) => {
      self.end(span, None, None)
      models
    }
    Err(error) => {
      self.end(span, None, Some(error))
      raise error
    }
  }
}

///|
pub extend Traced with @moonmuse.Provider::{chat, stream, embed, models}

///|
/// A wall-clock reading in nanoseconds, which is the unit a span takes its times in. The
/// runtime clock reads milliseconds, so the value is exact to a millisecond and is written in
/// the unit the trace format expects rather than in the unit the clock happens to use.
fn wall_nanos() -> Int64 {
  @async.now() * 1_000_000
}
