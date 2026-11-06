///|
/// What an endpoint answered: the status, the headers worth reading, and the body as it
/// arrived. Parsing is the dialect's job, so this type keeps the body as text.

///|
/// An HTTP answer.
pub struct Response {
  status : Int32
  headers : Array[(String, String)]
  body : String
}

///|
/// The last value of a header, case-insensitively.
pub fn Response::header(self : Response, name : String) -> String? {
  let wanted = name.to_lower()
  let mut found = None
  for pair in self.headers {
    if pair.0.to_lower() == wanted {
      found = Some(pair.1)
    }
  }
  found
}

///|
/// The body as JSON, or `Decode` when it is not.
pub fn Response::json(self : Response) -> Json raise @moonmuse.LlmError {
  @json.parse(self.body) catch {
    _ => raise @moonmuse.Decode("response is not JSON: " + self.body)
  }
}

///|
/// The `retry-after` header in seconds, when the endpoint sent one.
pub fn Response::retry_after(self : Response) -> Int64? {
  match self.header("retry-after") {
    Some(text) => {
      let seconds = @moonmuse.parse_int_lossy(text)
      if seconds > 0 {
        Some(seconds.to_int64())
      } else {
        None
      }
    }
    None => None
  }
}

///|
/// Send one call to `base + call.path`. A transport failure becomes `Stream`, which is
/// retryable: a refused connection is worth one more try, a malformed body is not.
pub async fn send(
  call : @moonmuse.Call,
  base~ : String,
  headers~ : Array[(String, String)] = [],
  timeout? : Int32,
) -> Response raise @moonmuse.LlmError {
  let url = join(base, call.path)
  let all_headers = [..headers, ..call.headers]
  let payload = call.body.stringify()
  let response = match call.verb {
    "GET" =>
      @moonfetch.get(url, headers=all_headers, timeout?) catch {
        error => raise @moonmuse.Stream(error.to_string())
      }
    "DELETE" =>
      @moonfetch.delete(url, headers=all_headers, timeout?) catch {
        error => raise @moonmuse.Stream(error.to_string())
      }
    "HEAD" =>
      @moonfetch.head(url, headers=all_headers, timeout?) catch {
        error => raise @moonmuse.Stream(error.to_string())
      }
    "PUT" =>
      @moonfetch.put(
        url,
        body=@moonfetch.Body::Text(payload),
        headers=all_headers,
        timeout?,
      ) catch {
        error => raise @moonmuse.Stream(error.to_string())
      }
    "PATCH" =>
      @moonfetch.patch(
        url,
        body=@moonfetch.Body::Text(payload),
        headers=all_headers,
        timeout?,
      ) catch {
        error => raise @moonmuse.Stream(error.to_string())
      }
    "POST" =>
      @moonfetch.post(
        url,
        body=@moonfetch.Body::Text(payload),
        headers=all_headers,
        timeout?,
      ) catch {
        error => raise @moonmuse.Stream(error.to_string())
      }
    other => raise @moonmuse.Decode("unknown HTTP verb: " + other)
  }
  { status: response.status, headers: response.headers, body: response.text(), }
}

///|
/// A base URL and a path, joined by exactly one slash.
fn join(base : String, path : String) -> String {
  let base = if base.has_suffix("/") {
    base.exact_view(start=0, end=base.length() - 1).to_owned()
  } else {
    base
  }
  let path = if path.has_prefix("/") { path } else { "/" + path }
  base + path
}

///|
/// The status of a response that failed, as an error. A success status passes through.
pub fn ensure_success(response : Response) -> Response raise @moonmuse.LlmError {
  if response.status >= 400 {
    raise @moonmuse.Status(
      code=response.status,
      body=response.body,
      retry_after=response.retry_after(),
    )
  }
  response
}
