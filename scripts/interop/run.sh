#!/usr/bin/env bash
# Start the gateway, point the official SDKs at it, stop it. CI runs this; so can a person.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"

moon build src/examples/04-gateway --target native
_build/native/debug/build/examples/04-gateway/04-gateway.exe &
server=$!
trap 'kill "$server" 2>/dev/null || true' EXIT

for _ in $(seq 1 120); do
  if curl -sf http://127.0.0.1:12000/v1/models > /dev/null; then
    break
  fi
  sleep 0.5
done

python3 scripts/interop/openai_sdk.py
python3 scripts/interop/anthropic_sdk.py
python3 scripts/interop/ollama_sdk.py
