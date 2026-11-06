"""The official Ollama Python client against the gateway.

Ollama's own API is not OpenAI's: `/api/chat`, `/api/embed`, `/api/tags`, and a stream of
newline-delimited objects. The client library is the judge of the shapes.
"""

import sys

import ollama

HOST = "http://127.0.0.1:12000"


def check(name, condition, detail=""):
    if not condition:
        print(f"FAIL {name} {detail}")
        sys.exit(1)
    print(f"ok {name}")


def main():
    client = ollama.Client(host=HOST)

    reply = client.chat(
        model="echo-1",
        messages=[{"role": "user", "content": "salut"}],
    )
    check("chat", reply["message"]["content"] == "echo: salut", reply)

    pieces = []
    for part in client.chat(
        model="echo-1",
        messages=[{"role": "user", "content": "streaming"}],
        stream=True,
    ):
        content = part.get("message", {}).get("content", "")
        if content:
            pieces.append(content)
    check("stream", "".join(pieces) == "echo: streaming", pieces)

    tags = client.list()
    names = [model.model for model in tags.models]
    check("tags", "echo-1" in names, names)

    vectors = client.embed(model="echo-1", input=["ab", "abcd"])
    check("embed", len(vectors.embeddings) == 2)
    check("embed width", len(vectors.embeddings[0]) == 3)


if __name__ == "__main__":
    main()
