///|
/// A gateway over a deterministic provider, so a client SDK can check the protocol without a
/// model in the loop: the answer is an echo of the last user text, and a tool call comes back
/// when the caller offers a tool. Started by `scripts/interop/run.sh`.

///|
/// A provider whose answers are a function of the request.
struct Echo {
  mut calls : Int32
}

///|
impl @moonmuse.Provider for Echo with fn chat(self, request) {
  self.calls = self.calls + 1
  let last = last_user_text(request)
  let wants_tool = request.tools.length() > 0 &&
    (last.contains("add") || last.contains("tool"))
  if wants_tool {
    return @moonmuse.Reply::new(
      @moonmuse.Message::new(@moonmuse.Assistant, [
        @moonmuse.Part::call("call_1", "add", { "a": 2, "b": 3 }),
      ]),
      finish=@moonmuse.Calls,
      usage=@moonmuse.Usage::new(11, 4),
    )
  }
  @moonmuse.Reply::new(
    @moonmuse.Message::assistant("echo: " + last),
    usage=@moonmuse.Usage::new(9, 3, cached=1),
  )
}

///|
impl @moonmuse.Provider for Echo with fn stream(self, request, on_delta) {
  let reply = self.chat(request)
  let text = reply.message.text_content(separator="")
  let mut start = 0
  while start < text.length() {
    let end = if start + 5 < text.length() { start + 5 } else { text.length() }
    on_delta(@moonmuse.Delta::Text(text.exact_view(start~, end~).to_owned()))
    start = end
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
  on_delta(@moonmuse.Delta::Done(reply))
  reply
}

///|
impl @moonmuse.Provider for Echo with fn embed(_self, _model, inputs) {
  let vectors = []
  for input in inputs {
    let weight = input.length().to_double()
    vectors.push([weight, weight + 1.0, weight + 2.0])
  }
  @moonmuse.check_vectors(inputs, vectors)
}

///|
impl @moonmuse.Provider for Echo with fn models(_self) {
  [
    @moonmuse.ModelInfo::new("echo-1", context=8192, capabilities=[
      @moonmuse.Chat,
      @moonmuse.Tools,
      @moonmuse.Embedding,
    ]),
  ]
}

///|
pub extend Echo with @moonmuse.Provider::{chat, stream, embed, models}

///|
/// The last user message's text, which is what this provider echoes.
fn last_user_text(request : @moonmuse.Request) -> String {
  let mut found = ""
  for message in request.messages {
    if message.role == @moonmuse.User {
      found = message.text_content(separator=" ")
    }
  }
  found
}

///|
async fn main {
  let dialects : Array[&@moonmuse.Dialect] = [
    @openai.dialect, @anthropic.dialect, @gemini.dialect, @ollama.dialect,
  ]
  let app = @serve.serve(Echo::{ calls: 0, }, dialects~)
  println("listening on 127.0.0.1:12000")
  @mooncat.serve(app, host="127.0.0.1", port=12000)
}
