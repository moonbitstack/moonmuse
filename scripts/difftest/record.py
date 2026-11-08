"""Ask every official client library to send the same conversation, and keep what it sent.

What an SDK sends is not what its documentation shows: defaults are filled in, optional
fields are dropped, and each library puts its own version prefix on the path. That is exactly
why this is worth comparing — the library under test has to agree with the client people
actually use, not with the shape a table on a website describes.

    python scripts/difftest/record.py [--out scripts/difftest/wire/sdk.json]

Every SDK is optional: one that is not installed is reported and skipped, so a contributor can
run the part they have. CI installs all of them.
"""

import argparse
import json
import os
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from stub import Recorder, serve

SYSTEM = "Answer in one sentence."
USER = "Why is the sky blue?"
TEMPERATURE = 0.2
LIMIT = 256

MODELS = {
    "openai": "gpt-4o-mini",
    "anthropic": "claude-sonnet-4-20250514",
    "gemini": "gemini-2.0-flash",
    "ollama": "qwen2.5",
}


def take_openai(base):
    from openai import OpenAI

    client = OpenAI(api_key="sk-difftest", base_url=base + "/v1")
    return client.chat.completions.create(
        model=MODELS["openai"],
        messages=[
            {"role": "system", "content": SYSTEM},
            {"role": "user", "content": USER},
        ],
        temperature=TEMPERATURE,
        max_tokens=LIMIT,
    )


def take_anthropic(base):
    import inspect

    from anthropic import Anthropic

    client = Anthropic(api_key="sk-ant-difftest", base_url=base)
    params = {
        "model": MODELS["anthropic"],
        "max_tokens": LIMIT,
        "system": SYSTEM,
        "messages": [{"role": "user", "content": USER}],
    }
    # The 2.6 line of the SDK stopped taking `temperature` at the top level and moved it under
    # `output_config`. Following whichever shape the installed version offers is what keeps
    # this recorder usable across versions.
    if "temperature" in inspect.signature(client.messages.create).parameters:
        params["temperature"] = TEMPERATURE
    else:
        params["output_config"] = {"temperature": TEMPERATURE}
    return client.messages.create(**params)


def take_gemini(base):
    from google import genai
    from google.genai import types

    client = genai.Client(
        api_key="difftest",
        http_options=types.HttpOptions(base_url=base, api_version="v1beta"),
    )
    return client.models.generate_content(
        model=MODELS["gemini"],
        contents=USER,
        config=types.GenerateContentConfig(
            system_instruction=SYSTEM,
            temperature=TEMPERATURE,
            max_output_tokens=LIMIT,
        ),
    )


def take_ollama(base):
    import ollama

    client = ollama.Client(host=base)
    return client.chat(
        model=MODELS["ollama"],
        messages=[
            {"role": "system", "content": SYSTEM},
            {"role": "user", "content": USER},
        ],
        stream=False,
        options={"temperature": TEMPERATURE, "num_predict": LIMIT},
    )


TAKERS = {
    "openai": take_openai,
    "anthropic": take_anthropic,
    "gemini": take_gemini,
    "ollama": take_ollama,
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--out", default="scripts/difftest/wire/sdk.json", help="where to write the bodies"
    )
    args = parser.parse_args()

    recorder = Recorder()
    server = serve(recorder)
    base = "http://127.0.0.1:%d" % server.server_address[1]

    recorded = {}
    skipped = []
    for name, taker in TAKERS.items():
        try:
            taker(base)
        except ImportError as error:
            skipped.append((name, "not installed: %s" % error))
            continue
        except Exception as error:
            # The stub answers with the smallest valid reply, but a library may still reject
            # it on parsing. The request has already been recorded, which is what we came for.
            print("note: %s raised after sending (%s)" % (name, error), file=sys.stderr)
        taken = recorder.take()
        if not taken:
            skipped.append((name, "sent nothing"))
            continue
        recorded[name] = taken[-1]

    server.shutdown()

    for name, reason in skipped:
        print("skipped %s: %s" % (name, reason), file=sys.stderr)
    if not recorded:
        print("no SDK sent a request; nothing to compare", file=sys.stderr)
        return 1

    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(recorded, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("recorded %s into %s" % (", ".join(sorted(recorded)), out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
