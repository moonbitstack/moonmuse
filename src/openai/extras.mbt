///|
/// The endpoints OpenAI offers beside chat: the Responses API, moderation, images, files,
/// batches and fine-tuning. They are methods on the client rather than part of `Provider`,
/// because no other vendor has the same set and a contract every provider must fill would be
/// mostly `Unsupported`.
///
/// Audio endpoints take and return binary bodies, which the transport does not carry yet;
/// they are the one part of the surface left for the transport's streaming work.

///|
/// What a moderation call found.
pub(all) struct Moderation {
  /// Whether any category was flagged.
  flagged : Bool
  /// The categories that were flagged, with their scores.
  flagged_categories : Map[String, Double]
}

///|
/// One generated image: a URL, or base64 when the endpoint was asked for it.
pub(all) struct Image {
  url : String?
  base64 : String?
  revised_prompt : String?
}

///|
/// One uploaded file.
pub(all) struct FileInfo {
  id : String
  filename : String
  bytes : Int32
  purpose : String
}

///|
/// One batch job.
pub(all) struct Batch {
  id : String
  status : String
  input_file : String
  output_file : String?
  failed : Int32
  completed : Int32
  total : Int32
}

///|
/// One fine-tuning job.
pub(all) struct FineTune {
  id : String
  status : String
  model : String
  trained_tokens : Int32?
}

///|
/// Check text against the moderation model. A result with nothing flagged still carries the
/// scores of the categories that were checked.
pub async fn Client::moderate(
  self : Client,
  model : String,
  inputs : Array[String],
) -> Moderation raise @moonmuse.LlmError {
  let body = @moonmuse.object_json([
    ("model", Json::string(model)),
    ("input", @moonmuse.strings_json(inputs)),
  ])
  let response = self.send(@moonmuse.Call::new("POST", "/moderations", body))
  if response.status >= 400 {
    raise @moonmuse.Status(
      code=response.status,
      body=response.body,
      retry_after=response.retry_after(),
    )
  }
  let payload = response.json()
  let flagged = Map([])
  let mut any = false
  for result in @moonmuse.json_array(payload, "results") {
    if @moonmuse.json_bool(result, "flagged").unwrap_or(false) {
      any = true
    }
    match @moonmuse.json_object(result, "category_scores") {
      Some(scores) =>
        for name, value in scores {
          match @moonmuse.json_as_number(value) {
            Some(score) => flagged[name] = score
            None => ()
          }
        }
      None => ()
    }
  }
  { flagged: any, flagged_categories: flagged, }
}

///|
/// Generate images from a prompt.
pub async fn Client::images(
  self : Client,
  prompt : String,
  model~ : String = "gpt-image-1",
  size~ : String = "1024x1024",
  count~ : Int32 = 1,
) -> Array[Image] raise @moonmuse.LlmError {
  let body = @moonmuse.object_json([
    ("model", Json::string(model)),
    ("prompt", Json::string(prompt)),
    ("size", Json::string(size)),
    ("n", Json::number(count.to_double())),
  ])
  let response = self.send(
    @moonmuse.Call::new("POST", "/images/generations", body),
  )
  if response.status >= 400 {
    raise @moonmuse.Status(
      code=response.status,
      body=response.body,
      retry_after=response.retry_after(),
    )
  }
  let payload = response.json()
  let out = []
  for item in @moonmuse.json_array(payload, "data") {
    out.push(Image::{
      url: @moonmuse.json_string(item, "url"),
      base64: @moonmuse.json_string(item, "b64_json"),
      revised_prompt: @moonmuse.json_string(item, "revised_prompt"),
    })
  }
  out
}

///|
/// The files this account has uploaded.
pub async fn Client::files(
  self : Client,
) -> Array[FileInfo] raise @moonmuse.LlmError {
  let response = self.send(@moonmuse.Call::new("GET", "/files", Json::null()))
  if response.status >= 400 {
    raise @moonmuse.Status(
      code=response.status,
      body=response.body,
      retry_after=response.retry_after(),
    )
  }
  let payload = response.json()
  let out = []
  for item in @moonmuse.json_array(payload, "data") {
    out.push(file_of(item))
  }
  out
}

///|
/// One file, by id.
pub async fn Client::file(
  self : Client,
  id : String,
) -> FileInfo raise @moonmuse.LlmError {
  let response = self.send(
    @moonmuse.Call::new("GET", "/files/" + id, Json::null()),
  )
  if response.status >= 400 {
    raise @moonmuse.Status(
      code=response.status,
      body=response.body,
      retry_after=response.retry_after(),
    )
  }
  file_of(response.json())
}

///|
/// Delete a file.
pub async fn Client::delete_file(
  self : Client,
  id : String,
) -> Bool raise @moonmuse.LlmError {
  let response = self.send(
    @moonmuse.Call::new("DELETE", "/files/" + id, Json::null()),
  )
  if response.status >= 400 {
    raise @moonmuse.Status(
      code=response.status,
      body=response.body,
      retry_after=response.retry_after(),
    )
  }
  @moonmuse.json_bool(response.json(), "deleted").unwrap_or(false)
}

///|
/// The batch jobs this account has run.
pub async fn Client::batches(
  self : Client,
) -> Array[Batch] raise @moonmuse.LlmError {
  let response = self.send(@moonmuse.Call::new("GET", "/batches", Json::null()))
  if response.status >= 400 {
    raise @moonmuse.Status(
      code=response.status,
      body=response.body,
      retry_after=response.retry_after(),
    )
  }
  let payload = response.json()
  let out = []
  for item in @moonmuse.json_array(payload, "data") {
    out.push(batch_of(item))
  }
  out
}

///|
/// One batch job, by id.
pub async fn Client::batch(
  self : Client,
  id : String,
) -> Batch raise @moonmuse.LlmError {
  let response = self.send(
    @moonmuse.Call::new("GET", "/batches/" + id, Json::null()),
  )
  if response.status >= 400 {
    raise @moonmuse.Status(
      code=response.status,
      body=response.body,
      retry_after=response.retry_after(),
    )
  }
  batch_of(response.json())
}

///|
/// Start a batch job over an uploaded file.
pub async fn Client::start_batch(
  self : Client,
  input_file : String,
  endpoint~ : String = "/v1/chat/completions",
  window~ : String = "24h",
) -> Batch raise @moonmuse.LlmError {
  let body = @moonmuse.object_json([
    ("input_file_id", Json::string(input_file)),
    ("endpoint", Json::string(endpoint)),
    ("completion_window", Json::string(window)),
  ])
  let response = self.send(@moonmuse.Call::new("POST", "/batches", body))
  if response.status >= 400 {
    raise @moonmuse.Status(
      code=response.status,
      body=response.body,
      retry_after=response.retry_after(),
    )
  }
  batch_of(response.json())
}

///|
/// The fine-tuning jobs this account has run.
pub async fn Client::fine_tunes(
  self : Client,
) -> Array[FineTune] raise @moonmuse.LlmError {
  let response = self.send(
    @moonmuse.Call::new("GET", "/fine_tuning/jobs", Json::null()),
  )
  if response.status >= 400 {
    raise @moonmuse.Status(
      code=response.status,
      body=response.body,
      retry_after=response.retry_after(),
    )
  }
  let payload = response.json()
  let out = []
  for item in @moonmuse.json_array(payload, "data") {
    out.push(fine_tune_of(item))
  }
  out
}

///|
/// One fine-tuning job, by id.
pub async fn Client::fine_tune(
  self : Client,
  id : String,
) -> FineTune raise @moonmuse.LlmError {
  let response = self.send(
    @moonmuse.Call::new("GET", "/fine_tuning/jobs/" + id, Json::null()),
  )
  if response.status >= 400 {
    raise @moonmuse.Status(
      code=response.status,
      body=response.body,
      retry_after=response.retry_after(),
    )
  }
  fine_tune_of(response.json())
}

///|
/// Answer through the Responses API. Its request shape differs from chat — `input` instead of
/// `messages`, `instructions` for the system prompt — so the body is built here and the reply
/// is read from `output`.
pub async fn Client::responses(
  self : Client,
  request : @moonmuse.Request,
) -> @moonmuse.Reply raise @moonmuse.LlmError {
  let input = []
  let mut instructions = ""
  for message in request.messages {
    match message.role {
      @moonmuse.System => {
        let text = message.text_content(separator="\n")
        if instructions != "" {
          instructions = instructions + "\n"
        }
        instructions = instructions + text
      }
      _ =>
        input.push(
          @moonmuse.object_json([
            ("role", Json::string(message.role.code())),
            ("content", Json::string(message.text_content(separator=""))),
          ]),
        )
    }
  }
  let fields : Array[(String, Json)] = [
    ("model", Json::string(request.model)),
    ("input", Json::array(input)),
  ]
  if instructions != "" {
    fields.push(("instructions", Json::string(instructions)))
  }
  match request.max_tokens {
    Some(value) =>
      fields.push(("max_output_tokens", Json::number(value.to_double())))
    None => ()
  }
  match request.temperature {
    Some(value) => fields.push(("temperature", Json::number(value)))
    None => ()
  }
  let body = Json::object(@moonmuse.merge_json(of_pairs(fields), request.extra))
  let response = self.send(@moonmuse.Call::new("POST", "/responses", body))
  if response.status >= 400 {
    raise @moonmuse.Status(
      code=response.status,
      body=response.body,
      retry_after=response.retry_after(),
    )
  }
  let payload = response.json()
  let parts = []
  for item in @moonmuse.json_array(payload, "output") {
    match @moonmuse.json_string(item, "type") {
      Some("message") =>
        for block in @moonmuse.json_array(item, "content") {
          match @moonmuse.json_string(block, "text") {
            Some(text) => parts.push(@moonmuse.Part::text(text))
            None => ()
          }
        }
      Some("function_call") =>
        parts.push(
          @moonmuse.Part::call(
            @moonmuse.json_string_or(item, "call_id", ""),
            @moonmuse.json_string_or(item, "name", ""),
            @moonmuse.parse_json_lossy(
              @moonmuse.json_string_or(item, "arguments", ""),
            ),
          ),
        )
      _ => ()
    }
  }
  let usage = match @moonmuse.json_object(payload, "usage") {
    Some(fields) => {
      let map = Json::object(fields)
      @moonmuse.Usage::{
        input: @moonmuse.json_int(map, "input_tokens"),
        output: @moonmuse.json_int(map, "output_tokens"),
        cached: None,
      }
    }
    None => @moonmuse.Usage::zero()
  }
  @moonmuse.Reply::new(
    @moonmuse.Message::new(@moonmuse.Assistant, parts),
    finish=@moonmuse.Stop,
    usage~,
    raw=payload,
  )
}

///|
/// A file body.
fn file_of(item : Json) -> FileInfo {
  {
    id: @moonmuse.json_string_or(item, "id", ""),
    filename: @moonmuse.json_string_or(item, "filename", ""),
    bytes: @moonmuse.json_int(item, "bytes").unwrap_or(0),
    purpose: @moonmuse.json_string_or(item, "purpose", ""),
  }
}

///|
/// A batch body.
fn batch_of(item : Json) -> Batch {
  let counts = @moonmuse.json_field(item, "request_counts").unwrap_or(
    Json::null(),
  )
  {
    id: @moonmuse.json_string_or(item, "id", ""),
    status: @moonmuse.json_string_or(item, "status", ""),
    input_file: @moonmuse.json_string_or(item, "input_file_id", ""),
    output_file: @moonmuse.json_string(item, "output_file_id"),
    failed: @moonmuse.json_int(counts, "failed").unwrap_or(0),
    completed: @moonmuse.json_int(counts, "completed").unwrap_or(0),
    total: @moonmuse.json_int(counts, "total").unwrap_or(0),
  }
}

///|
/// A fine-tuning job body.
fn fine_tune_of(item : Json) -> FineTune {
  {
    id: @moonmuse.json_string_or(item, "id", ""),
    status: @moonmuse.json_string_or(item, "status", ""),
    model: @moonmuse.json_string_or(item, "model", ""),
    trained_tokens: @moonmuse.json_int(item, "trained_tokens"),
  }
}
