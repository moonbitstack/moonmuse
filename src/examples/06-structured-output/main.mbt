///|
/// The value the model is asked to produce as JSON.
struct Person {
  name : String
  age : Int32
}

///|
/// The explicit deserializer (Koog derives this from the Kotlin type; MoonBit has
/// no reflection, so the schema states its own parser).
fn parse_person(j : Json) -> Person? {
  guard j is Object(m) else { return None }
  guard m.get("name") is Some(String(name)) else { return None }
  guard m.get("age") is Some(Number(age, ..)) else { return None }
  Some({ name, age: age.to_int(), })
}

///|
fn person_schema() -> @moonmuse.StructuredSchema[Person] {
  {
    name: "Person",
    description: "a person with a name and age",
    schema: @toolbox.TObject(
      properties=[
        { name: "name", description: "full name", ptype: @toolbox.TString, },
        { name: "age", description: "age in years", ptype: @toolbox.TInteger, },
      ],
      required=["name", "age"],
    ),
    parse: parse_person,
  }
}

///|
/// Structured output (Koog `requestStructured`): the agent asks the model for a
/// value matching a schema, extracts the JSON from the reply — even out of prose or
/// a code fence — and parses it; a malformed reply triggers a fixing re-prompt. The
/// scripted clients here reproduce the clean, the fenced, and the retry cases.
///
///     moon run examples/09-structured-output --target native
#coverage.skip
async fn main {
  @async.with_task_group(_g => {
    // A clean JSON reply parses straight through.
    let clean = @moonmuse.AIAgent::new(
      @moonmuse.MockClient::new([
        @moonmuse.Message::assistant("{\"name\":\"Ann\",\"age\":30}"),
      ]),
      model=@models.deepseek_v4_flash,
    )
    let r1 = clean.request_structured("who?", person_schema()) catch {
      e => {
        println("failed: " + e.to_string())
        return
      }
    }
    println("clean: name=\{r1.value.name} age=\{r1.value.age} raw=\{r1.raw}")

    // JSON buried in prose and a code fence is still extracted.
    let fenced = @moonmuse.AIAgent::new(
      @moonmuse.MockClient::new([
        @moonmuse.Message::assistant(
          "Sure!\n```json\n{\"name\":\"Cid\",\"age\":40}\n```",
        ),
      ]),
      model=@models.deepseek_v4_flash,
    )
    let r2 = fenced.request_structured("who?", person_schema()) catch {
      e => {
        println("failed: " + e.to_string())
        return
      }
    }
    println("fenced: name=\{r2.value.name} age=\{r2.value.age}")

    // A malformed first reply is re-prompted; the second reply parses.
    let retry = @moonmuse.AIAgent::new(
      @moonmuse.MockClient::new([
        @moonmuse.Message::assistant("sorry, I cannot do that"),
        @moonmuse.Message::assistant("{\"name\":\"Bob\",\"age\":25}"),
      ]),
      model=@models.deepseek_v4_flash,
    )
    let r3 = retry.request_structured("who?", person_schema()) catch {
      e => {
        println("failed: " + e.to_string())
        return
      }
    }
    println("after retry: name=\{r3.value.name} age=\{r3.value.age}")
  })
}
