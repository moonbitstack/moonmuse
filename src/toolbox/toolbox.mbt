///|
/// A tool the model may call, and the function behind it. The schema is stated once, here,
/// and reaches the model through `Request.tools`; the function sees the parsed arguments
/// and returns the text the model is shown.

///|
/// One callable tool.
pub struct Entry {
  tool : @moonmuse.Tool
  run : async (Json) -> String
}

///|
/// A set of tools addressable by name.
pub struct Toolbox {
  mut entries : Array[Entry]
}

///|
/// An empty set.
pub fn Toolbox::new() -> Toolbox {
  { entries: [], }
}

///|
/// Add a tool. A later tool with the same name replaces the earlier one, so a caller can
/// override a default without rebuilding the set.
pub fn Toolbox::add(
  self : Toolbox,
  tool : @moonmuse.Tool,
  run : async (Json) -> String,
) -> Unit {
  let kept = self.entries.filter(entry => entry.tool.name != tool.name)
  self.entries = [..kept, { tool, run, }]
}

///|
/// The tools as the model sees them, in the order they were added.
pub fn Toolbox::tools(self : Toolbox) -> Array[@moonmuse.Tool] {
  self.entries.map(entry => entry.tool)
}

///|
/// Whether a tool of this name is registered.
pub fn Toolbox::has(self : Toolbox, name : String) -> Bool {
  for entry in self.entries {
    if entry.tool.name == name {
      return true
    }
  }
  false
}

///|
/// Run one call and return its result. A tool that raises, or that is not registered,
/// still produces a result: the model is supposed to see the failure and decide what to
/// do, and a loop that raised instead would lose the conversation.
pub async fn Toolbox::call(
  self : Toolbox,
  part : @moonmuse.Part,
) -> @moonmuse.Part {
  match part {
    @moonmuse.Part::Call(id~, name~, args~) => {
      for entry in self.entries {
        if entry.tool.name == name {
          let output = (entry.run)(args) catch {
            error => "error: " + error.to_string()
          }
          return @moonmuse.Part::result(
            id,
            output,
            error=output.has_prefix("error: "),
          )
        }
      }
      @moonmuse.Part::result(id, "error: no tool named " + name, error=true)
    }
    other =>
      @moonmuse.Part::result(
        "",
        "error: not a call: " + other.text_of(),
        error=true,
      )
  }
}

///|
/// Ask, run whatever tools the model asks for, and ask again — at most `limit` rounds of
/// tool calls. The reply that comes back is the last one the model produced, whether it
/// was a final answer or a call the budget ran out on; the caller can tell by
/// `Reply::calls`.
pub async fn run(
  provider : &@moonmuse.Provider,
  request : @moonmuse.Request,
  toolbox : Toolbox,
  limit~ : Int32 = 10,
) -> @moonmuse.Reply raise @moonmuse.LlmError {
  let mut current = request
  let mut round = 0
  while true {
    let reply = provider.chat(current)
    let calls = reply.calls()
    if calls.is_empty() || round >= limit {
      return reply
    }
    let results = []
    for call in calls {
      let result = toolbox.call(call) catch {
        error =>
          @moonmuse.Part::result("", "error: " + error.to_string(), error=true)
      }
      results.push(result)
    }
    current = current.push(reply.message)
    current = current.push(@moonmuse.Message::new(@moonmuse.Tool, results))
    round = round + 1
  }
  abort("unreachable")
}
