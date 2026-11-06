///|
/// A prompt written as a template: the same Jinja syntax a web page uses, rendered against a
/// map of values. Keeping prompts out of MoonBit string concatenation is what makes them
/// reviewable and testable.

///|
/// A template that failed to render, with the engine's own message.
pub(all) suberror PromptError {
  Render(String)
}

///|
/// A prompt template.
pub struct Template {
  source : String
}

///|
/// A template from its source text.
pub fn Template::new(source : String) -> Template {
  { source, }
}

///|
/// Render the template against `values`. A missing variable renders as the engine's default
/// for it, which is what a template author expects.
pub fn Template::render(
  self : Template,
  values : Map[String, Json],
) -> String raise PromptError {
  @moonpug.render(self.source, Json::object(values)) catch {
    error => raise PromptError::Render(error.to_string())
  }
}

///|
/// Render and wrap in a message of `role`.
pub fn Template::message(
  self : Template,
  role : @moonmuse.Role,
  values : Map[String, Json],
) -> @moonmuse.Message raise PromptError {
  @moonmuse.Message::new(role, [@moonmuse.Part::text(self.render(values))])
}

///|
/// Render several templates as the messages of one request, in order. The first value of
/// each pair is the role.
pub fn conversation(
  turns : Array[(@moonmuse.Role, Template)],
  values : Map[String, Json],
) -> Array[@moonmuse.Message] raise PromptError {
  let messages = []
  for turn in turns {
    messages.push(turn.1.message(turn.0, values))
  }
  messages
}

///|
/// A value map from key/value pairs.
pub fn values(pairs : Array[(String, Json)]) -> Map[String, Json] {
  let map = Map([])
  for pair in pairs {
    map[pair.0] = pair.1
  }
  map
}
