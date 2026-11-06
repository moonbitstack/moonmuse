"""The official OpenAI Python client against the gateway.

What is checked is the protocol: the SDK sends what it sends, and the gateway must answer in a
shape the SDK accepts and parses. The provider behind it echoes, so nothing here depends on a
model.
"""

import sys

from openai import OpenAI

BASE = "http://127.0.0.1:12000/v1"


def check(name, condition, detail=""):
    if not condition:
        print(f"FAIL {name} {detail}")
        sys.exit(1)
    print(f"ok {name}")


def main():
    client = OpenAI(api_key="test", base_url=BASE)

    reply = client.chat.completions.create(
        model="echo-1",
        messages=[{"role": "user", "content": "hello"}],
    )
    check("chat", reply.choices[0].message.content == "echo: hello", reply)
    check("usage", reply.usage.prompt_tokens == 9, reply.usage)
    check("finish", reply.choices[0].finish_reason == "stop")

    chunks = []
    stream = client.chat.completions.create(
        model="echo-1",
        messages=[{"role": "user", "content": "streamed hello"}],
        stream=True,
    )
    for event in stream:
        if event.choices and event.choices[0].delta.content:
            chunks.append(event.choices[0].delta.content)
    check("stream", "".join(chunks) == "echo: streamed hello", chunks)

    tools = [
        {
            "type": "function",
            "function": {
                "name": "add",
                "description": "add two numbers",
                "parameters": {
                    "type": "object",
                    "properties": {"a": {"type": "integer"}, "b": {"type": "integer"}},
                    "required": ["a", "b"],
                },
            },
        }
    ]
    called = client.chat.completions.create(
        model="echo-1",
        messages=[{"role": "user", "content": "please add"}],
        tools=tools,
    )
    check("tool finish", called.choices[0].finish_reason == "tool_calls")
    call = called.choices[0].message.tool_calls[0]
    check("tool name", call.function.name == "add")
    check("tool args", '"a": 2' in call.function.arguments, call.function.arguments)

    vectors = client.embeddings.create(model="echo-1", input=["a", "abcd"])
    check("embeddings", len(vectors.data) == 2)
    check("embedding width", len(vectors.data[0].embedding) == 3)

    models = client.models.list()
    check("models", any(model.id == "echo-1" for model in models.data))

    try:
        client.chat.completions.create(model="", messages=[])
        check("bad request", False, "expected an error")
    except Exception as error:  # noqa: BLE001 - the SDK's error type varies by version
        check("bad request", "400" in str(error) or "decode" in str(error).lower(), error)


if __name__ == "__main__":
    main()
