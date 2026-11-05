///|
test "message text_content concatenates only Text parts" {
  let m = Message::{
    role: Assistant,
    parts: [
      Text("hello"),
      ToolCall(id=Some("1"), tool="search", args=Json::object({})),
      Text("world"),
    ],
    finish_reason: None,
    meta: None,
  }
  assert_eq(m.text_content(separator=" "), "hello world")
}

///|
test "message tool_calls returns the ToolCall parts in order" {
  let m = Message::{
    role: Assistant,
    parts: [
      Text("let me look"),
      ToolCall(id=Some("a"), tool="search", args=Json::object({})),
      ToolCall(id=Some("b"), tool="calc", args=Json::object({})),
    ],
    finish_reason: None,
    meta: None,
  }
  let calls = m.tool_calls()
  assert_eq(calls.length(), 2)
  guard calls[0] is ToolCall(tool=t0, ..) else {
    fail("part 0 not a tool call")
  }
  guard calls[1] is ToolCall(tool=t1, ..) else {
    fail("part 1 not a tool call")
  }
  assert_eq(t0, "search")
  assert_eq(t1, "calc")
}

///|
test "a plain assistant reply has no tool calls (the loop's finish signal)" {
  assert_eq(Message::assistant("done").tool_calls().length(), 0)
}

///|
test "PromptBuilder chains into an ordered message list" {
  let p = PromptBuilder::new(id="t")
    .system("you are a bot")
    .user("hi")
    .tool_result(tool="search", output="42", id="1")
    .build()
  assert_eq(p.messages.length(), 3)
  assert_eq(p.messages[0].role, System)
  assert_eq(p.messages[1].role, User)
  assert_eq(p.messages[2].role, User)
  guard p.messages[2].parts[0] is ToolResult(output=out, ..) else {
    fail("expected a tool result part")
  }
  assert_eq(out, "42")
}

///|
test "Prompt append is a non-mutating copy" {
  let base = PromptBuilder::new().user("a").build()
  let grown = base.append(Message::assistant("b"))
  assert_eq(base.messages.length(), 1)
  assert_eq(grown.messages.length(), 2)
}
