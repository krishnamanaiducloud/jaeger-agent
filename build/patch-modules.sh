#!/bin/sh
# Raise the Go modules linked into cmd/agent to releases that fix every known
# vulnerability in upstream jaeger v1.62.0. Run inside the upstream source tree.
set -eu

# Retry transient module proxy and checksum database failures.
retry() {
  attempt=1
  until "$@"; do
    if [ "$attempt" -ge 4 ]; then
      return 1
    fi
    echo "Command failed (attempt $attempt), retrying: $*" >&2
    sleep $((attempt * 5))
    attempt=$((attempt + 1))
  done
}

retry go get \
  github.com/apache/thrift@v0.25.0 \
  github.com/klauspost/compress@v1.20.3 \
  golang.org/x/crypto@v0.58.1-0.20261009181718-2f1f834330b2 \
  golang.org/x/net@v0.62.0 \
  golang.org/x/sys@v0.49.0 \
  golang.org/x/text@v0.43.0 \
  google.golang.org/grpc@v1.84.0 \
  google.golang.org/protobuf@v1.36.12

# -e: newer OpenTelemetry SDK test-only packages no longer resolve; they are not linked into the agent.
retry go mod tidy -e

# Fail the build if any pin was not applied.
for pin in \
  github.com/apache/thrift@v0.25.0 \
  github.com/klauspost/compress@v1.20.3 \
  golang.org/x/crypto@v0.58.1-0.20261009181718-2f1f834330b2 \
  golang.org/x/net@v0.62.0 \
  golang.org/x/text@v0.43.0 \
  google.golang.org/grpc@v1.84.0; do
  module=${pin%@*}
  want=${pin#*@}
  have=$(go list -m -f '{{.Version}}' "$module")
  if [ "$have" != "$want" ]; then
    echo "module $module is $have, want $want" >&2
    exit 1
  fi
done
