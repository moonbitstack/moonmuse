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

if [ ! -x "tools/$target/weaver" ]; then
  mkdir -p tools
  curl -fsSL -o "tools/weaver.tar.xz" \
    "https://github.com/open-telemetry/weaver/releases/download/$version/$target.tar.xz"
  curl -fsSL -o "tools/weaver.sha256" \
    "https://github.com/open-telemetry/weaver/releases/download/$version/$target.tar.xz.sha256"
  # The release publishes the digest beside the archive; a download that does not match it is
  # not the tool this script runs.
  (cd tools && printf '%s  weaver.tar.xz\n' "$(cut -d' ' -f1 weaver.sha256)" | sha256sum -c -)
  tar xf "tools/weaver.tar.xz" -C tools
fi

rm -f tools/live-check.log
"tools/$target/weaver" registry live-check \
  -r 'https://github.com/open-telemetry/semantic-conventions-genai.git[model]' \
  --input-source otlp \
  --otlp-grpc-port "$port" \
  --inactivity-timeout 20 \
  --diagnostic-stdout > tools/live-check.log 2>&1 &
checker=$!

for _ in $(seq 1 120); do
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

moon run src/examples/05-observe --target native -- "127.0.0.1:$port"

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
