///|
/// Templates: a value is substituted, a missing value does not crash, and the result is a
/// message a request can carry.

///|
test "prompt: a variable is substituted" {
  let template = @prompt.Template::new("Hello {{ name }}, you are {{ role }}.")
  let text = template.render(
    @prompt.values([
      ("name", Json::string("Ada")),
      ("role", Json::string("an engineer")),
    ]),
  )
  assert_eq(text, "Hello Ada, you are an engineer.")
}

///|
test "prompt: a filter applies" {
  let template = @prompt.Template::new("{{ items | length }} items")
  let text = template.render(
    @prompt.values([("items", @moonmuse.strings_json(["a", "b", "c"]))]),
  )
  assert_eq(text, "3 items")
}

///|
test "prompt: a template renders as a message" {
  let template = @prompt.Template::new("sum {{ a }} and {{ b }}")
  let message = template.message(
    @moonmuse.User,
    @prompt.values([("a", Json::number(1.0)), ("b", Json::number(2.0))]),
  )
  assert_eq(message.role, @moonmuse.User)
  assert_eq(message.text_content(), "sum 1 and 2")
}

///|
test "prompt: a broken template is an error, not a panic" {
  let failed = try {
    let _ = @prompt.Template::new("{% if %}").render(@prompt.values([]))
    false
  } catch {
    @prompt.PromptError::Render(_) => true
  }
  assert_eq(failed, true)
}
