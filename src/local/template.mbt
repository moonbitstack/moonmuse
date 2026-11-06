///|
/// Turning messages into the one prompt a local model sees. A served model gets a message
/// array and does this itself; a local one gets a string, and the string is a template the
/// model was trained on.

///|
/// The values a chat template is rendered with: the messages, the tools, and whether the
/// assistant turn is left open for the model to continue.
pub fn context(
  request : @moonmuse.Request,
  add_generation_prompt~ : Bool = true,
) -> Map[String, Json] {
  let messages = []
  for message in request.messages {
    messages.push(message_json(message))
  }
  let tools = []
  for tool in request.tools {
    tools.push(
      @moonmuse.object_json([
        ("name", Json::string(tool.name)),
        ("description", Json::string(tool.description)),
        ("parameters", tool.schema),
      ]),
    )
  }
  @prompt.values([
    ("model", Json::string(request.model)),
    ("messages", Json::array(messages)),
    ("tools", Json::array(tools)),
    ("add_generation_prompt", Json::boolean(add_generation_prompt)),
  ])
}

///|
/// One message as a template sees it. A tool call becomes `tool_calls`, because that is what
/// the templates iterate; a tool result carries its `tool_call_id`.
fn message_json(message : @moonmuse.Message) -> Json {
  let fields = [
    ("role", Json::string(message.role.code())),
    ("content", Json::string(visible_text(message))),
  ]
  let tool_calls = []
  for part in message.parts {
    match part {
      @moonmuse.Part::Call(id~, name~, args~) =>
        tool_calls.push(
          @moonmuse.object_json([
            ("id", Json::string(id)),
            ("name", Json::string(name)),
            ("arguments", args),
          ]),
        )
      _ => ()
    }
  }
  // Always present, even when empty: a template that asks for it is asking whether this
  // message made a call, and an undefined name is an error in the template engine.
  fields.push(("tool_calls", Json::array(tool_calls)))
  @moonmuse.object_json(fields)
}

///|
/// What a model reads of a message: its text, and a placeholder for an image, since a text
/// model cannot see one and silently dropping it would change the question.
fn visible_text(message : @moonmuse.Message) -> String {
  let parts = []
  for part in message.parts {
    match part {
      @moonmuse.Part::Text(text) => parts.push(text)
      @moonmuse.Part::Image(url~, ..) => parts.push("[image: " + url + "]")
      @moonmuse.Part::Result(content~, ..) => parts.push(content)
      _ => ()
    }
  }
  parts.join("\n")
}

///|
/// The ChatML template: Qwen, Hermes, Yi and most models fine-tuned on their format.
pub fn chatml() -> @prompt.Template {
  @prompt.Template::new(
    "{% for m in messages %}<|im_start|>{{ m.role }}\n{{ m.content }}{% if m.tool_calls %}\n{% for c in m.tool_calls %}<tool_call>{\"name\": \"{{ c.name }}\", \"arguments\": {{ c.arguments }}}</tool_call>{% endfor %}{% endif %}<|im_end|>\n{% endfor %}{% if add_generation_prompt %}<|im_start|>assistant\n{% endif %}",
  )
}

///|
/// The Llama 3 template, which names roles in a header block and ends turns with `eot_id`.
pub fn llama3() -> @prompt.Template {
  @prompt.Template::new(
    "{% for m in messages %}<|start_header_id|>{{ m.role }}<|end_header_id|>\n\n{{ m.content }}<|eot_id|>{% endfor %}{% if add_generation_prompt %}<|start_header_id|>assistant<|end_header_id|>\n\n{% endif %}",
  )
}
