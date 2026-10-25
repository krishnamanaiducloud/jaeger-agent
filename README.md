# jaeger-agent (patched)

Patched rebuild of the upstream [Jaeger](https://github.com/jaegertracing/jaeger) agent,
published as `mohankrishna999/jaeger-agent`.

Upstream stopped shipping the agent after **v1.62.0** (it was removed in Jaeger v2, see
[jaegertracing/jaeger#4739](https://github.com/jaegertracing/jaeger/issues/4739)), so the
final upstream image keeps accumulating Go toolchain and module CVEs. This repository
rebuilds that exact release from the verified upstream tag with a current Go toolchain and
patched modules, and ships it in a shell-less static runtime.

## Layout

```
.
├── Dockerfile                 # verified source checkout, module patching, vet/test, static build
├── Dockerfile-debug           # same binary on a Wolfi base with a shell
├── Makefile                   # build, build-debug, scan, push
├── build/
│   └── patch-modules.sh       # pinned module upgrades, fails if any pin is not applied
├── k8s/
│   ├── daemonset.yaml         # one agent per node, non-root, read-only root filesystem
│   ├── service.yaml           # headless service for the agent ports
│   └── kustomization.yaml     # image tag pin
└── .github/workflows/
    └── container-security.yml # build both images and fail on any Trivy finding
```

## Release 1.62.0-patched-v4

| Component | Upstream v1.62.0 | Previous `-patched-v3` | `-patched-v4` |
|---|---|---|---|
| Go toolchain | 1.23.2 | 1.26.4 | 1.27.3 |
| `github.com/apache/thrift` | 0.21.0 | 0.23.0 | 0.25.0 |
| `github.com/klauspost/compress` | 1.17.10 | 1.17.10 | 1.20.3 |
| `golang.org/x/net` | 0.30.0 | 0.55.0 | 0.61.0 |
| `golang.org/x/text` | 0.19.0 | 0.37.0 | 0.43.0 |
| `google.golang.org/grpc` | 1.67.1 | 1.79.3 | 1.84.0 |
| `google.golang.org/protobuf` | 1.34.2 | | 1.36.12 |
| Runtime base | distroless static | distroless static (Debian 13) | Chainguard static (digest-pinned) |

Trivy 0.76.1 reported 22 HIGH, 15 MEDIUM and 1 LOW findings in `-patched-v3`, all in the
agent binary. `-patched-v4` and `-patched-v4-debug` report no findings at any severity.

The source is cloned at tag `v1.62.0` and the build fails unless it resolves to upstream
commit `4b7446248e087edffd15508e760e8e5da044f4b4`. `go vet` and the `cmd/agent` tests run
before the binary is built.

## Runtime contract

Unchanged from earlier `-patched` tags, so existing manifests keep working:

- Entrypoint `/go/bin/agent-linux`, user `65532:65532`, no shell in the production image.
- Ports: `5775/udp` (Zipkin compact Thrift), `5778/tcp` (sampling configs),
  `6831/udp` (Jaeger compact Thrift), `6832/udp` (Jaeger binary Thrift),
  `14271/tcp` (admin and health).
- `SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt`.

## Build, scan and push

```sh
make build-debug   # builds 1.62.0-patched-v4 and 1.62.0-patched-v4-debug
make scan          # Trivy 0.76.1, fails on any finding
make push
```

`GO_TEST_SKIP` takes a test-name regex for hosts whose inotify limits break the TLS
certificate-watch tests (`too many open files`), for example
`--build-arg GO_TEST_SKIP=TestProxyClientTLS`. CI runs the full suite.

## Deploy

```sh
kubectl apply -k k8s/
```

Set `--reporter.grpc.host-port` in `k8s/daemonset.yaml` to your collector's gRPC endpoint.

## Migration

The agent is a stopgap. New services should send OTLP directly to the Jaeger v2 collector
or an OpenTelemetry Collector, after which this image can be retired.
