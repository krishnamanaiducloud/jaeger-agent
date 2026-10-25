.PHONY: build build-debug scan push all

# Build Vars
IMAGENAME=mohankrishna999/jaeger-agent
VERSION=1.62.0-patched-v4
TRIVY_IMAGE=aquasec/trivy:0.76.1

.DEFAULT_GOAL := all

build:
	@docker build --platform linux/amd64 -t ${IMAGENAME}:${VERSION} .
build-debug: build
	@docker build --platform linux/amd64 --build-arg PRODUCTION_IMAGE=${IMAGENAME}:${VERSION} -f Dockerfile-debug -t ${IMAGENAME}:${VERSION}-debug .
scan:
	@for tag in ${VERSION} ${VERSION}-debug; do \
		docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v trivy-cache:/root/.cache/trivy ${TRIVY_IMAGE} \
			image --scanners vuln --severity UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL --exit-code 1 ${IMAGENAME}:$$tag || exit 1; \
	done
push:
	@docker push ${IMAGENAME}:${VERSION}
	@docker push ${IMAGENAME}:${VERSION}-debug
all: build-debug scan push
