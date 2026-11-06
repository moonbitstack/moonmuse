///|
/// A real Ollama server. These run when `MOONMUSE_LIVE` is set, and are skipped when it is
/// not — a machine without a model server cannot answer them, and a CI job that sets the
/// variable fails loudly when the server is missing rather than reporting a green run.
///
/// `OLLAMA_BASE` and `OLLAMA_MODEL` choose the address and the chat model; the embedding
/// model is `OLLAMA_EMBED_MODEL` (default `nomic-embed-text`).

///|
/// The address to talk to, or `None` when live tests are off.
fn live_base() -> String? {
  match @env.get_env_var("MOONMUSE_LIVE") {
    Some(_) =>
      Some(@env.get_env_var("OLLAMA_BASE").unwrap_or("http://127.0.0.1:11434"))
    None => None
  }
}

///|
/// The chat model to use.
fn live_model() -> String {
  @env.get_env_var("OLLAMA_MODEL").unwrap_or("qwen2.5:0.5b")
}

///|
async test "ollama live: a chat answers with text" {
  match live_base() {
    None => ()
    Some(base) => {
      let client = Client::new(base~)
      let reply = client.chat(
        @moonmuse.Request::new(
          live_model(),
          [@moonmuse.Message::user("Reply with the single word: ready")],
          max_tokens=32,
        ),
      )
      assert_eq(reply.text().trim() != "", true)
      assert_eq(reply.usage.input is Some(_), true)
    }
  }
}

///|
async test "ollama live: a declaration of tools is accepted" {
  match live_base() {
    None => ()
    Some(base) => {
      let client = Client::new(base~)
      let reply = client.chat(
        @moonmuse.Request::new(
          live_model(),
          [@moonmuse.Message::user("What is 2 + 3? Use the add tool.")],
          tools=[
            @moonmuse.Tool::new(
              "add",
              "Add two integers",
              schema=@moonmuse.parse_json_lossy(
                "{\"type\":\"object\",\"properties\":{\"a\":{\"type\":\"integer\"},\"b\":{\"type\":\"integer\"}},\"required\":[\"a\",\"b\"]}",
              ),
            ),
          ],
          choice=@moonmuse.Required,
          max_tokens=256,
        ),
      )
      // Whether a model this small actually calls the tool is its business; the contract
      // under test is that the declaration and a required choice are accepted and answered.
      assert_eq(reply.text() != "" || reply.calls().length() > 0, true)
    }
  }
}

///|
async test "ollama live: embeddings come back one per input" {
  match live_base() {
    None => ()
    Some(base) => {
      let client = Client::new(base~)
      let model = @env.get_env_var("OLLAMA_EMBED_MODEL").unwrap_or(
        "nomic-embed-text",
      )
      let vectors = client.embed(model, ["alpha", "beta"])
      assert_eq(vectors.length(), 2)
      assert_eq(vectors[0].length() > 0, true)
      assert_eq(vectors[0].length(), vectors[1].length())
      assert_eq(vectors[0] == vectors[1], false)
    }
  }
}
