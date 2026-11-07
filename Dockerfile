# Patched rebuild of the upstream Jaeger agent (jaeger v1.62.0, the final agent release).
# The agent binary is rebuilt from the verified upstream tag with a current Go toolchain
# and patched modules, then shipped in a shell-less static runtime.
ARG GO_IMAGE=cgr.dev/chainguard/go:latest-dev@sha256:ed70318f7b4f2e4a82e1dbc363f7a13be3a5805081f86ed9d1ec02d2694c222f
ARG RUNTIME_IMAGE=cgr.dev/chainguard/static:latest@sha256:fc42af33e643f20d08baf03cddcc1c02ba57052dfb02edb0d79f3fc47bcea8d9

FROM ${GO_IMAGE} AS build
ARG JAEGER_VERSION=1.62.0
ARG JAEGER_COMMIT=4b7446248e087edffd15508e760e8e5da044f4b4
# Regex of tests to skip, for hosts whose inotify limits break the TLS cert-watch tests.
ARG GO_TEST_SKIP=

USER root
ENV CGO_ENABLED=0 \
    GOTOOLCHAIN=local \
    GOFLAGS=-mod=mod

WORKDIR /src
RUN git -c advice.detachedHead=false clone --quiet --depth 1 --branch "v${JAEGER_VERSION}" \
      https://github.com/jaegertracing/jaeger.git . \
    && test "$(git rev-parse HEAD)" = "${JAEGER_COMMIT}"

COPY build/patch-modules.sh /usr/local/bin/patch-modules.sh
RUN --mount=type=cache,id=jaeger-agent-go-mod,target=/root/go/pkg/mod,sharing=locked \
    sh /usr/local/bin/patch-modules.sh

RUN --mount=type=cache,id=jaeger-agent-go-mod,target=/root/go/pkg/mod,sharing=locked \
    --mount=type=cache,id=jaeger-agent-go-build,target=/root/.cache/go-build,sharing=locked \
    go vet ./cmd/agent/... \
    && GOMAXPROCS=2 go test -p=2 -count=1 -skip "${GO_TEST_SKIP}" ./cmd/agent/...

RUN --mount=type=cache,id=jaeger-agent-go-mod,target=/root/go/pkg/mod,sharing=locked \
    --mount=type=cache,id=jaeger-agent-go-build,target=/root/.cache/go-build,sharing=locked \
    version_pkg=github.com/jaegertracing/jaeger/pkg/version \
    && go build -trimpath -buildvcs=false \
      -ldflags "-s -w -buildid= -X ${version_pkg}.commitSHA=${JAEGER_COMMIT} -X ${version_pkg}.latestVersion=v${JAEGER_VERSION} -X ${version_pkg}.date=$(git log -1 --format=%cI)" \
      -o /out/agent ./cmd/agent \
    && /out/agent version

FROM ${RUNTIME_IMAGE}
ARG JAEGER_VERSION=1.62.0
ARG IMAGE_VERSION=1.62.0-patched-v5

LABEL org.opencontainers.image.title="jaeger-agent" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.description="Jaeger agent ${JAEGER_VERSION} rebuilt with patched Go toolchain and modules" \
      org.opencontainers.image.source="https://github.com/jaegertracing/jaeger" \
      org.opencontainers.image.licenses="Apache-2.0"

ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
COPY --from=build --chown=0:0 --chmod=0555 /out/agent /go/bin/agent-linux

USER 65532:65532
# 5775/udp zipkin compact thrift, 5778/tcp configs, 6831/udp jaeger compact thrift,
# 6832/udp jaeger binary thrift, 14271/tcp admin and health.
EXPOSE 5775/udp 5778/tcp 6831/udp 6832/udp 14271/tcp
ENTRYPOINT ["/go/bin/agent-linux"]
