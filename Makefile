.PHONY: check fetch build build-linux-amd64 build-darwin-arm64 build-darwin-amd64 build-windows-amd64 verify

check:
	./scripts/check.sh

fetch:
	./scripts/fetch-sources.sh

build:
	@case "$$(uname -s):$$(uname -m)" in \
		Linux:x86_64) ./scripts/build-linux-amd64.sh ;; \
		Darwin:arm64) ./scripts/build-darwin-arm64.sh ;; \
		Darwin:x86_64) ./scripts/build-darwin-amd64.sh ;; \
		*) echo "unsupported build host: $$(uname -s) $$(uname -m)" >&2; exit 1 ;; \
	esac

build-linux-amd64:
	./scripts/build-linux-amd64.sh

build-darwin-arm64:
	./scripts/build-darwin-arm64.sh

build-darwin-amd64:
	./scripts/build-darwin-amd64.sh

build-windows-amd64:
	pwsh -File ./scripts/build-windows-amd64.ps1

verify:
	./scripts/verify-bundle.sh
