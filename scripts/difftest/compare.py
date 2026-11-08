"""Compare the bodies our dialects write with the bodies the official SDKs send.

The question is not whether a body is valid — it is whether it is the same body, field for
field, that the client library everybody uses puts on the wire for the same conversation. A
key one side sends and the other does not is a defect unless it is listed here with a reason.

    python scripts/difftest/compare.py [--sdk scripts/difftest/wire/sdk.json]

Exit code 1 means an unexplained difference: the allowlist is the only place a difference may
live, so adding one is a decision someone writes down.
"""

import argparse
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent

# What each library puts in front of the path our dialect writes.
PREFIX = {
    "openai": "/v1",
    "anthropic": "/v1",
    "gemini": "/v1beta",
    "ollama": "",
}

OURS = ["moon", "run", "src/examples/06-wire", "--target", "native"]


def leaves(node, prefix=""):
    """Flatten a body into {path: scalar} so two bodies can be compared key by key."""
    out = {}
    if isinstance(node, dict):
        if not node:
            out[prefix] = {}
        for key, value in node.items():
            out.update(leaves(value, f"{prefix}.{key}" if prefix else key))
    elif isinstance(node, list):
        if not node:
            out[prefix] = []
        for index, value in enumerate(node):
            out.update(leaves(value, f"{prefix}[{index}]"))
    else:
        out[prefix] = node
    return out


def ours():
    try:
        raw = subprocess.check_output(OURS, cwd=ROOT, text=True, encoding="utf-8")
    except subprocess.CalledProcessError as error:
        print("the wire example failed: %s" % error, file=sys.stderr)
        raise SystemExit(2)
    return json.loads(raw)


def load_allow(path):
    if not path.exists():
        return {}
    entries = json.loads(path.read_text(encoding="utf-8"))
    return {(entry["format"], entry["path"], entry["side"]): entry["reason"] for entry in entries}


def compare(format_name, sdk_call, ours_call, allow):
    problems = []
    explained = []

    prefix = PREFIX[format_name]
    sdk_path = sdk_call["path"]
    if prefix and sdk_path.startswith(prefix):
        sdk_path = sdk_path[len(prefix):]
    if sdk_path != ours_call["path"]:
        problems.append(("path", "sdk=%s ours=%s" % (sdk_path, ours_call["path"])))

    sdk_leaves = leaves(sdk_call["body"])
    ours_leaves = leaves(ours_call["body"])

    for key in sorted(set(sdk_leaves) - set(ours_leaves)):
        reason = allow.get((format_name, key, "sdk-only"))
        (explained if reason else problems).append(
            (key, reason or "the SDK sends it and we do not")
        )
    for key in sorted(set(ours_leaves) - set(sdk_leaves)):
        reason = allow.get((format_name, key, "ours-only"))
        (explained if reason else problems).append(
            (key, reason or "we send it and the SDK does not")
        )
    for key in sorted(set(sdk_leaves) & set(ours_leaves)):
        if sdk_leaves[key] != ours_leaves[key]:
            reason = allow.get((format_name, key, "value"))
            target = explained if reason else problems
            target.append(
                (
                    key,
                    reason
                    or "sdk=%r ours=%r" % (sdk_leaves[key], ours_leaves[key]),
                )
            )

    for key, note in explained:
        print("  ok   %-42s %s" % (key, note))
    for key, note in problems:
        print("  DIFF %-42s %s" % (key, note))
    return problems


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sdk", default="scripts/difftest/wire/sdk.json")
    parser.add_argument("--allow", default="scripts/difftest/allow.json")
    args = parser.parse_args()

    sdk = json.loads((ROOT / args.sdk).read_text(encoding="utf-8"))
    mine = ours()
    allow = load_allow(ROOT / args.allow)

    failures = 0
    for format_name in sorted(sdk):
        if format_name not in mine:
            print("%s: the example wrote nothing for it" % format_name)
            failures += 1
            continue
        print("%s" % format_name)
        problems = compare(format_name, sdk[format_name], mine[format_name], allow)
        failures += len(problems)

    print()
    if failures:
        print("%d unexplained difference(s): either fix the dialect or add the entry to "
              "scripts/difftest/allow.json with the reason it is right" % failures)
        return 1
    print("every format agrees with its official client, or the difference is on record")
    return 0


if __name__ == "__main__":
    sys.exit(main())
