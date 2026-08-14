.PHONY: check fetch build verify

check:
	./scripts/check.sh

fetch:
	./scripts/fetch-sources.sh

build:
	./scripts/build-linux-amd64.sh

verify:
	./scripts/verify-bundle.sh out/wurster-edge-runtime-linux-amd64
