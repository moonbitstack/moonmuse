///|
/// A local model as a provider. The engine generates text, the template says what text to
/// generate from, and the call style says how the model writes a tool call. Everything above
/// this — the tool loop, the layers, the gateway — cannot tell a local model from a remote one.

///|
/// A provider backed by an inference engine.
pub struct Local {
  engine : &Engine
  template : @prompt.Template
  model : String
  calls : Calls
  info : Array[@moonmuse.ModelInfo]
  /// How many tokens a single answer may run to.
  limit : Int32
}

///|
/// A provider for `engine`. The template defaults to ChatML, the format most open models are
/// tuned on; pass `template=@local.llama3()` for a Llama 3 model.
pub fn Local::new(
  engine : &Engine,
  template~ : @prompt.Template = chatml(),
  model~ : String = "local",
  calls~ : Calls = Tagged,
  info~ : Array[@moonmuse.ModelInfo] = [],
  limit~ : Int32 = 4_096,
) -> Local {
  { engine, template, model, calls, info, limit, }
}

///|
/// The prompt this request becomes. Rendering is where a template and its values meet, so a
/// bad template reports itself here rather than after a model has been loaded.
pub fn Local::prompt(
  self : Local,
  request : @moonmuse.Request,
) -> String raise LocalError {
  self.template.render(context(request)) catch {
    @prompt.PromptError::Render(message) => raise LocalError::Template(message)
  }
}

///|
/// A local failure as the shared one. A template that does not render is this side's mistake,
/// so it is `Decode`; an engine that fails is worth another attempt, so it is `Stream`.
fn as_llm(error : LocalError) -> @moonmuse.LlmError {
  match error {
    Engine(message) => @moonmuse.Stream(message)
    Template(message) => @moonmuse.Decode("template: " + message)
    Unsupported(what) => @moonmuse.Unsupported(what)
  }
}

///|
/// The reply an answer text describes: the text that is not a call, then each call.
fn reply_of(text : String, calls~ : Calls) -> @moonmuse.Reply {
  let parsed = parse(text, calls~)
  let parts = []
  if parsed.text != "" {
    parts.push(@moonmuse.Part::text(parsed.text))
  }
  for call in parsed.calls {
    parts.push(call)
  }
  let finish = if parsed.calls.is_empty() {
    @moonmuse.Stop
  } else {
    @moonmuse.Calls
  }
  @moonmuse.Reply::new(
    @moonmuse.Message::new(@moonmuse.Assistant, parts),
    finish~,
  )
}

///|
pub impl @moonmuse.Provider for Local with fn chat(self, request) {
  let outcome = try {
    let prompt = self.prompt(request)
    Ok(reply_of(self.engine.generate(prompt, self.limit), calls=self.calls))
  } catch {
    error => Err(error)
  }
  match outcome {
    Ok(reply) => reply
    Err(error) => raise as_llm(error)
  }
}

///|
/// A streamed answer. With no tools declared the model's text is forwarded as it is produced,
/// so a chat streams token by token. With tools the answer is buffered first: a call is written
/// inside the text, and half of one is not something a caller can act on.
pub impl @moonmuse.Provider for Local with fn stream(self, request, on_delta) {
  let outcome = try {
    let prompt = self.prompt(request)
    Ok(
      if request.tools.is_empty() {
        let text = self.engine.stream(prompt, self.limit, piece => {
          on_delta(@moonmuse.Delta::Text(piece))
        })
        reply_of(text, calls=self.calls)
      } else {
        reply_of(self.engine.generate(prompt, self.limit), calls=self.calls)
      },
    )
  } catch {
    error => Err(error)
  }
  let reply = match outcome {
    Ok(reply) => reply
    Err(error) => raise as_llm(error)
  }
  if !request.tools.is_empty() {
    let visible = reply.message.text_content(separator="")
    if visible != "" {
      on_delta(@moonmuse.Delta::Text(visible))
    }
    for part in reply.message.calls() {
      match part {
        @moonmuse.Part::Call(id~, name~, args~) => {
          on_delta(@moonmuse.Delta::CallStart(id~, name~))
          on_delta(@moonmuse.Delta::CallArgs(id~, chunk=@json.dumps(args)))
        }
        _ => ()
      }
    }
  }
  on_delta(@moonmuse.Delta::Done(reply))
  reply
}

///|
pub impl @moonmuse.Provider for Local with fn embed(self, model, inputs) {
  self.engine.embed(model, inputs) catch {
    error => raise as_llm(error)
  }
}

///|
pub impl @moonmuse.Provider for Local with fn models(self) {
  if !self.info.is_empty() {
    return self.info
  }
  let from_engine = self.engine.models()
  if from_engine.is_empty() {
    return [
      @moonmuse.ModelInfo::new(self.model, capabilities=[
        @moonmuse.Chat,
        @moonmuse.Tools,
      ]),
    ]
  }
  from_engine
}

///|
pub extend Local with @moonmuse.Provider::{chat, stream, embed, models}
