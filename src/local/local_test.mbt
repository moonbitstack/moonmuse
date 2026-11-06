///|
/// A local model is text in, text out. These cases check the three places that text is turned
/// into something structured: the template that builds the prompt, the reader that finds calls
/// in the answer, and the provider that joins them.

///|
/// An engine that answers from a script, so a test is about this package and not about weights.
struct Script {
  replies : Array[String]
  mut next : Int32
}

///|
impl @local.Engine for Script with fn generate(_self, _prompt, _limit) {
  let index = if _self.next < _self.replies.length() {
    _self.next
  } else {
    _self.replies.length() - 1
  }
  _self.next = _self.next + 1
  _self.replies[index]
}

///|
pub extend Script with @local.Engine::{generate}

///|
test "calls: a tagged call is found and removed from the text" {
  let answer = "Let me check.\n<tool_call>{\"name\": \"add\", \"arguments\": {\"a\": 2, \"b\": 3}}</tool_call>"
  let parsed = @local.parse(answer, calls=@local.Tagged)
  assert_eq(parsed.text, "Let me check.")
  assert_eq(parsed.calls.length(), 1)
  assert_eq(
    parsed.calls[0],
    @moonmuse.Part::call("call_0", "add", { "a": 2, "b": 3 }),
  )
}

///|
test "calls: two calls get ids by position" {
  let answer = "<tool_call>{\"name\": \"a\", \"arguments\": {}}</tool_call><tool_call>{\"name\": \"b\", \"arguments\": {}}</tool_call>"
  let parsed = @local.parse(answer)
  assert_eq(parsed.calls.length(), 2)
  match parsed.calls[1] {
    @moonmuse.Part::Call(id~, name~, ..) => {
      assert_eq(id, "call_1")
      assert_eq(name, "b")
    }
    _ => abort("expected a call")
  }
}

///|
test "calls: a fenced block is read" {
  let answer = "Here:\n```json\n{\"name\": \"add\", \"arguments\": {\"a\": 1}}\n```\nDone."
  let parsed = @local.parse(answer, calls=@local.Fenced)
  assert_eq(parsed.calls.length(), 1)
  assert_eq(parsed.text, "Here:\n\nDone.")
}

///|
test "calls: a bare object is recognised by its name" {
  let parsed = @local.parse(
    "calling {\"name\": \"add\", \"arguments\": {\"a\": 1}} now",
    calls=@local.Bare,
  )
  assert_eq(parsed.calls.length(), 1)
  assert_eq(parsed.text, "calling  now")
}

///|
test "calls: arguments written as a JSON string are parsed" {
  let parsed = @local.parse(
    "<tool_call>{\"name\": \"add\", \"arguments\": \"{\\\"a\\\": 4}\"}</tool_call>",
  )
  assert_eq(parsed.calls.length(), 1)
  assert_eq(parsed.calls[0], @moonmuse.Part::call("call_0", "add", { "a": 4 }))
}

///|
test "calls: a JSON array of calls is read" {
  let parsed = @local.parse(
    "<tool_call>[{\"name\": \"a\", \"arguments\": {}}, {\"name\": \"b\", \"arguments\": {}}]</tool_call>",
  )
  assert_eq(parsed.calls.length(), 2)
}

///|
test "calls: malformed JSON is text, not a call" {
  let parsed = @local.parse("<tool_call>{not json}</tool_call>")
  assert_eq(parsed.calls.length(), 0)
  assert_eq(parsed.text, "")
}

///|
test "template: chatml renders the roles and leaves the assistant turn open" {
  let prompt = @local.chatml().render(
    @local.context(
      @moonmuse.Request::new("qwen", [
        @moonmuse.Message::system("be brief"),
        @moonmuse.Message::user("hi"),
      ]),
    ),
  )
  assert_eq(
    prompt, "<|im_start|>system\nbe brief<|im_end|>\n<|im_start|>user\nhi<|im_end|>\n<|im_start|>assistant\n",
  )
}

///|
test "template: llama3 names roles in a header" {
  let prompt = @local.llama3().render(
    @local.context(
      @moonmuse.Request::new("llama", [@moonmuse.Message::user("hi")]),
    ),
  )
  assert_eq(
    prompt, "<|start_header_id|>user<|end_header_id|>\n\nhi<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n",
  )
}

///|
test "template: a tool result carries its content" {
  let prompt = @local.chatml().render(
    @local.context(
      @moonmuse.Request::new("m", [@moonmuse.Message::tool("4", id="call_0")]),
    ),
  )
  assert_eq(prompt.contains("<|im_start|>tool"), true)
  assert_eq(prompt.contains("4"), true)
}

///|
test "template: text is not HTML-escaped" {
  let prompt = @local.chatml().render(
    @local.context(
      @moonmuse.Request::new("m", [@moonmuse.Message::user("a < b & c")]),
    ),
  )
  assert_eq(prompt.contains("a < b & c"), true)
}

///|
async test "local: an answer with a call becomes a reply with a call" {
  let engine = Script::{
    replies: [
      "<tool_call>{\"name\": \"add\", \"arguments\": {\"a\": 2}}</tool_call>",
    ],
    next: 0,
  }
  let provider = @local.Local::new(engine)
  let reply = provider.chat(
    @moonmuse.Request::new("m", [@moonmuse.Message::user("2+?")]),
  )
  assert_eq(reply.finish, @moonmuse.Calls)
  assert_eq(reply.calls()[0], @moonmuse.Part::call("call_0", "add", { "a": 2 }))
}

///|
async test "local: plain text is a text reply" {
  let engine = Script::{ replies: ["hello"], next: 0, }
  let provider = @local.Local::new(engine)
  let reply = provider.chat(
    @moonmuse.Request::new("m", [@moonmuse.Message::user("hi")]),
  )
  assert_eq(reply.text(), "hello")
  assert_eq(reply.finish, @moonmuse.Stop)
}

///|
async test "local: a text-only model streams without buffering" {
  let engine = Script::{ replies: ["one two"], next: 0, }
  let provider = @local.Local::new(engine)
  let pieces = []
  let reply = provider.stream(
    @moonmuse.Request::new("m", [@moonmuse.Message::user("count")]),
    delta => {
      match delta {
        @moonmuse.Delta::Text(piece) => pieces.push(piece)
        _ => ()
      }
    },
  )
  assert_eq(pieces, ["one two"])
  assert_eq(reply.text(), "one two")
}

///|
async test "local: embeddings are refused when the engine has none" {
  let engine = Script::{ replies: ["x"], next: 0, }
  let provider = @local.Local::new(engine)
  let refused = try {
    let _ = provider.embed("e", ["a"])
    false
  } catch {
    @moonmuse.Unsupported(_) => true
    _ => false
  }
  assert_eq(refused, true)
}

///|
async test "local: a model list is what the provider was told" {
  let engine = Script::{ replies: ["x"], next: 0, }
  let provider = @local.Local::new(engine, info=[
    @moonmuse.ModelInfo::new("tiny", context=2048),
  ])
  let models = provider.models()
  assert_eq(models.length(), 1)
  assert_eq(models[0].id, "tiny")
}
