"""The official Anthropic Python client against the gateway.

The Messages API has its own shape: a top-level `system`, a required `max_tokens`, content
blocks and named stream events. The SDK is the judge of whether the gateway got them right.
"""

import sys

from anthropic import Anthropic

BASE = "http://127.0.0.1:12000"


def check(name, condition, detail=""):
    if not condition:
        print(f"FAIL {name} {detail}")
        sys.exit(1)
    print(f"ok {name}")


def main():
    client = Anthropic(api_key="test", base_url=BASE)

    reply = client.messages.create(
        model="echo-1",
        max_tokens=64,
        system="be brief",
        messages=[{"role": "user", "content": "bonjour"}],
    )
    check("message type", reply.type == "message")
    check("role", reply.role == "assistant")
    check("content", reply.content[0].text == "echo: bonjour", reply.content)
    check("stop", reply.stop_reason == "end_turn")
    check("usage", reply.usage.input_tokens == 9)

    pieces = []
    with client.messages.stream(
        model="echo-1",
        max_tokens=64,
        messages=[{"role": "user", "content": "streaming"}],
    ) as stream:
        for text in stream.text_stream:
            pieces.append(text)
        final = stream.get_final_message()
    check("stream text", "".join(pieces) == "echo: streaming", pieces)
    check("stream stop", final.stop_reason == "end_turn", final.stop_reason)

    tools = [
        {
            "name": "add",
            "description": "add two numbers",
            "input_schema": {
                "type": "object",
                "properties": {"a": {"type": "integer"}, "b": {"type": "integer"}},
                "required": ["a", "b"],
            },
        }
    ]
    called = client.messages.create(
        model="echo-1",
        max_tokens=64,
        messages=[{"role": "user", "content": "please add"}],
        tools=tools,
    )
    check("tool stop", called.stop_reason == "tool_use", called.stop_reason)
    block = [b for b in called.content if b.type == "tool_use"][0]
    check("tool name", block.name == "add")
    check("tool input", block.input == {"a": 2, "b": 3}, block.input)


if __name__ == "__main__":
    main()
