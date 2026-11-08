"""The official Google Gen AI client against the gateway.

Gemini's API puts the model in the path and streams from a different method than it answers,
so a gateway that speaks it is judged on those two shapes. The provider behind it echoes, so
nothing here depends on a model.
"""

import sys

from google import genai
from google.genai import types

BASE = "http://127.0.0.1:12000"


def check(name, condition, detail=""):
    if not condition:
        print(f"FAIL {name} {detail}")
        sys.exit(1)
    print(f"ok {name}")


def main():
    client = genai.Client(
        api_key="test",
        http_options=types.HttpOptions(base_url=BASE, api_version="v1beta"),
    )

    reply = client.models.generate_content(model="echo-1", contents="bonjour")
    check("generate", reply.text == "echo: bonjour", reply.text)
    usage = reply.usage_metadata
    check("usage", usage.prompt_token_count == 9, usage)
    check("candidates", reply.candidates[0].finish_reason.value == "STOP")

    pieces = []
    for chunk in client.models.generate_content_stream(
        model="echo-1", contents="streaming"
    ):
        if chunk.text:
            pieces.append(chunk.text)
    check("stream", "".join(pieces) == "echo: streaming", pieces)

    vectors = client.models.embed_content(model="echo-1", contents=["ab", "abcd"])
    check("embed", len(vectors.embeddings) == 2, vectors.embeddings)
    check("embed width", len(vectors.embeddings[0].values) == 3)

    names = [model.name for model in client.models.list()]
    check("models", "models/echo-1" in names, names)


if __name__ == "__main__":
    main()
