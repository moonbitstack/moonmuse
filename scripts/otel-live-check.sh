#!/usr/bin/env bash
# Check the telemetry this library emits against the OpenTelemetry GenAI semantic
# conventions, with the conventions project's own tool. CI runs this; so can a person.
#
# The tool is `weaver`, from open-telemetry/weaver: it listens for OTLP, matches every span
# against the registry, and reports an attribute the registry does not define, one it has
# deprecated, and one whose stability is not settled. The registry is the GenAI one, because
# that is where these names live now — the main registry marks every one of them deprecated
# and points here.
#
#     bash scripts/otel-live-check.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

version=v0.28.0
target=weaver-x86_64-unknown-linux-gnu
port="${WEAVER_PORT:-4317}"
registry="tools/semconv-genai"

if [ ! -x "tools/$target/weaver" ]; then
  mkdir -p tools
  # The release CDN answers 504 under load often enough that a single attempt is a flaky job.
  # The API is a second host for the same bytes, and it is the one that stays up when the
  # download host does not, so a failed download falls back to it.
  fetch() {
    curl -fsSL --retry 6 --retry-delay 3 --retry-all-errors -o "$2" \
      "https://github.com/open-telemetry/weaver/releases/download/$version/$1" && return 0
    echo "the release host refused $1; asking the API for it"
    id="$(gh api "repos/open-telemetry/weaver/releases/tags/$version" \
      --jq ".assets[] | select(.name==\"$1\") | .id")"
    gh api -H "Accept: application/octet-stream" \
      "repos/open-telemetry/weaver/releases/assets/$id" > "$2"
  }
  fetch "$target.tar.xz" "tools/weaver.tar.xz"
  fetch "$target.tar.xz.sha256" "tools/weaver.sha256"
  # The release publishes the digest beside the archive; a download that does not match it is
  # not the tool this script runs.
  # The digest file is written in more than one shape across releases; the hash is the same
  # sixty-four hexadecimal characters in all of them.
  digest="$(grep -oE '[0-9a-f]{64}' tools/weaver.sha256 | head -1)"
  if [ -z "$digest" ]; then
    echo "the digest file does not hold a SHA-256"
    cat tools/weaver.sha256
    exit 1
  fi
  (cd tools && printf '%s  weaver.tar.xz\n' "$digest" | sha256sum -c -)
  tar xf "tools/weaver.tar.xz" -C tools
fi

# The registry is cloned once instead of on every run: weaver fetches it itself when it is
# given a URL, which puts a git clone between the listener and the span and turns a slow
# network into "connection refused" a second later.
if [ ! -f "$registry/model/manifest.yaml" ]; then
  rm -rf "$registry"
  for attempt in 1 2 3; do
    if git clone --depth 1 --quiet \
      https://github.com/open-telemetry/semantic-conventions-genai.git "$registry"; then
      break
    fi
    echo "cloning the registry failed (attempt $attempt)"
    sleep 5
  done
fi
[ -f "$registry/model/manifest.yaml" ] || { echo "the registry is not here"; exit 1; }

echo "building the example"
moon build src/examples/05-observe --target native

rm -f tools/live-check.log
"tools/$target/weaver" registry live-check \
  -r "$registry/model" \
  --input-source otlp \
  --otlp-grpc-port "$port" \
  --inactivity-timeout 30 \
  --diagnostic-stdout > tools/live-check.log 2>&1 &
checker=$!

# Two waits, because either one alone is a race: the log line says the listener was asked for,
# the socket says it is there, and a process that died in between fails the check instead of
# letting the example connect to nothing.
for _ in $(seq 1 180); do
  if grep -q "OTLP gRPC listener started" tools/live-check.log 2>/dev/null; then
    break
  fi
  if ! kill -0 "$checker" 2>/dev/null; then
    cat tools/live-check.log
    echo "weaver stopped before it listened"
    exit 1
  fi
  sleep 1
done
if ! grep -q "OTLP gRPC listener started" tools/live-check.log; then
  tail -30 tools/live-check.log
  echo "weaver did not listen within three minutes"
  exit 1
fi
for _ in $(seq 1 30); do
  if (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
    break
  fi
  if ! kill -0 "$checker" 2>/dev/null; then
    cat tools/live-check.log
    echo "weaver stopped while the port was being waited on"
    exit 1
  fi
  sleep 1
done

if ! moon run src/examples/05-observe --target native -- "127.0.0.1:$port"; then
  echo "the example could not deliver the span"
  tail -30 tools/live-check.log
  exit 1
fi

wait "$checker" || true
cat tools/live-check.log

# Weaver counts its findings at the end. A violation is an attribute the registry does not
# have, which is the case this check exists for; an improvement only says the convention is
# not stable yet, which is true of every GenAI name today.
if grep -q "\[violation\]" tools/live-check.log; then
  echo "the telemetry does not match the registry"
  exit 1
fi
if ! grep -q "span: 1" tools/live-check.log; then
  echo "the checker did not receive the span"
  exit 1
fi
echo "every attribute is one the registry defines"
