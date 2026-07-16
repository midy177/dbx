.DEFAULT_GOAL := dev

BUN ?= bun
PNPM ?= pnpm
DOCKER ?= docker
DOCKER_COMPOSE ?= docker compose

TAURI_DEV_PORT ?= 1420
IMAGE ?= dbx
TAG ?= local
PLATFORM ?= linux/amd64
PREBUILT_PLATFORMS ?= linux/amd64,linux/arm64
DBX_PUBLIC_BASE_PATH ?= /
DOCKERFILE ?= deploy/Dockerfile
PREBUILT_DOCKERFILE ?= deploy/Dockerfile.prebuilt
COMPOSE_FILE ?= deploy/docker-compose.yml

INSTALL_STAMP := node_modules/.bun-install.stamp
DOCS_INSTALL_STAMP := docs/node_modules/.pnpm-install.stamp
WEB_BINARY := target/release/dbx-web

.PHONY: help install clean-install docs-install check-tauri-dev-port dev dev-fast dev-web dev-backend build frontend-build app-build package web-check web-check-embedded web-binary web-prebuilt image image-frontend image-load image-push image-prebuilt-load image-prebuilt-push compose-build docs docs-build check test cargo-check-fast cargo-test-fast

$(INSTALL_STAMP): package.json bun.lock
	$(BUN) install --frozen-lockfile
	@mkdir -p node_modules
	@touch $@

$(DOCS_INSTALL_STAMP): docs/package.json docs/pnpm-lock.yaml
	cd docs && $(PNPM) install --frozen-lockfile --ignore-workspace
	@mkdir -p docs/node_modules
	@touch $@

help:
	@printf '%s\n' 'DBX targets:'
	@printf '%s\n' ''
	@printf '%s\n' 'Development:'
	@printf '  %-24s %s\n' 'make' 'Start the local desktop development environment'
	@printf '  %-24s %s\n' 'make dev' 'Start Tauri desktop dev'
	@printf '  %-24s %s\n' 'make dev-web' 'Start the Vite web frontend dev server'
	@printf '  %-24s %s\n' 'make dev-backend' 'Start the dbx-web backend dev server'
	@printf '  %-24s %s\n' 'make dev-fast' 'Start Tauri dev without default Rust features'
	@printf '%s\n' ''
	@printf '%s\n' 'Builds:'
	@printf '  %-24s %s\n' 'make build' 'Typecheck and build the frontend'
	@printf '  %-24s %s\n' 'make app-build' 'Build the desktop app package'
	@printf '  %-24s %s\n' 'make package' 'Alias for app-build'
	@printf '  %-24s %s\n' 'make web-binary' 'Build dbx-web with embedded frontend assets'
	@printf '  %-24s %s\n' 'make web-prebuilt' 'Build embedded dbx-web binaries for PREBUILT_PLATFORMS'
	@printf '%s\n' ''
	@printf '%s\n' 'Containers:'
	@printf '  %-24s %s\n' 'make image' 'Build a local Docker image'
	@printf '  %-24s %s\n' 'make image-frontend' 'Build only the Docker frontend stage'
	@printf '  %-24s %s\n' 'make image-load' 'Buildx image for PLATFORM and load it locally'
	@printf '  %-24s %s\n' 'make image-push' 'Buildx image for PLATFORM and push it'
	@printf '  %-24s %s\n' 'make image-prebuilt-load' 'Build runtime image from local prebuilt binary and load it locally'
	@printf '  %-24s %s\n' 'make image-prebuilt-push' 'Build multi-platform runtime image from local prebuilt binaries and push it'
	@printf '  %-24s %s\n' 'make compose-build' 'Build via deploy/docker-compose.yml'
	@printf '%s\n' ''
	@printf '%s\n' 'Checks:'
	@printf '  %-24s %s\n' 'make check' 'Run project checks'
	@printf '  %-24s %s\n' 'make test' 'Run project tests'
	@printf '  %-24s %s\n' 'make web-check' 'Run cargo check for dbx-web'
	@printf '  %-24s %s\n' 'make web-check-embedded' 'Check dbx-web with embedded frontend assets'
	@printf '  %-24s %s\n' 'make cargo-check-fast' 'Run Rust check without default features'
	@printf '  %-24s %s\n' 'make cargo-test-fast' 'Run Rust tests without default features'
	@printf '%s\n' ''
	@printf '%s\n' 'Variables:'
	@printf '  %-24s %s\n' 'IMAGE=dbx' 'Docker image name'
	@printf '  %-24s %s\n' 'TAG=local' 'Docker image tag'
	@printf '  %-24s %s\n' 'PLATFORM=linux/amd64' 'Buildx platform'
	@printf '  %-24s %s\n' 'PREBUILT_PLATFORMS=linux/amd64,linux/arm64' 'Local zigbuild platforms for runtime-only image builds'
	@printf '  %-24s %s\n' 'DBX_PUBLIC_BASE_PATH=/' 'Frontend/router base path baked into the image'

install: $(INSTALL_STAMP)

clean-install:
	rm -rf node_modules $(INSTALL_STAMP)
	$(BUN) install --frozen-lockfile
	@mkdir -p node_modules
	@touch $(INSTALL_STAMP)

docs-install: $(DOCS_INSTALL_STAMP)

check-tauri-dev-port:
	@if lsof -nP -iTCP:$(TAURI_DEV_PORT) -sTCP:LISTEN >/dev/null 2>&1; then \
		echo "Port $(TAURI_DEV_PORT) is already in use. DBX Tauri dev requires http://localhost:$(TAURI_DEV_PORT)."; \
		echo ""; \
		lsof -nP -iTCP:$(TAURI_DEV_PORT) -sTCP:LISTEN; \
		echo ""; \
		echo "Stop the process above, then run make dev again. Example: kill <PID>"; \
		exit 1; \
	fi

dev: install check-tauri-dev-port
	$(BUN) run dev:tauri

dev-fast: install check-tauri-dev-port
	$(BUN) run tauri dev -- --no-default-features

dev-web: install
	$(BUN) run dev:web

dev-backend: install
	$(BUN) run dev:backend

build frontend-build: install
	$(BUN) run build:checked

app-build package: install
	$(BUN) run tauri build

web-check:
	cargo check -p dbx-web

web-check-embedded: frontend-build
	cargo check -p dbx-web --features embedded-static

$(WEB_BINARY): frontend-build
	cargo build --release -p dbx-web --features embedded-static

web-binary: $(WEB_BINARY)

web-prebuilt:
	$(BUN) run build:web-prebuilt --platforms $(PREBUILT_PLATFORMS)

image:
	$(DOCKER) build \
		-f $(DOCKERFILE) \
		--build-arg DBX_PUBLIC_BASE_PATH=$(DBX_PUBLIC_BASE_PATH) \
		-t $(IMAGE):$(TAG) \
		.

image-frontend:
	$(DOCKER) build \
		-f $(DOCKERFILE) \
		--target frontend \
		--build-arg DBX_PUBLIC_BASE_PATH=$(DBX_PUBLIC_BASE_PATH) \
		.

image-load:
	$(DOCKER) buildx build \
		-f $(DOCKERFILE) \
		--platform $(PLATFORM) \
		--build-arg DBX_PUBLIC_BASE_PATH=$(DBX_PUBLIC_BASE_PATH) \
		-t $(IMAGE):$(TAG) \
		--load \
		.

image-push:
	$(DOCKER) buildx build \
		-f $(DOCKERFILE) \
		--platform $(PLATFORM) \
		--build-arg DBX_PUBLIC_BASE_PATH=$(DBX_PUBLIC_BASE_PATH) \
		-t $(IMAGE):$(TAG) \
		--push \
		.

image-prebuilt-load:
	$(BUN) run build:web-prebuilt --platforms $(PLATFORM)
	$(DOCKER) buildx build \
		-f $(PREBUILT_DOCKERFILE) \
		--platform $(PLATFORM) \
		-t $(IMAGE):$(TAG) \
		--load \
		.

image-prebuilt-push: web-prebuilt
	$(DOCKER) buildx build \
		-f $(PREBUILT_DOCKERFILE) \
		--platform $(PREBUILT_PLATFORMS) \
		-t $(IMAGE):$(TAG) \
		--push \
		.

compose-build:
	$(DOCKER_COMPOSE) -f $(COMPOSE_FILE) build

docs: docs-install
	cd docs && ./node_modules/.bin/next dev --hostname 127.0.0.1

docs-build: docs-install
	cd docs && ./node_modules/.bin/next build && node scripts/generate-sitemap.mjs

check: install
	$(BUN) run check

test: install
	$(BUN) run test

cargo-check-fast:
	cargo check --no-default-features

cargo-test-fast:
	cargo test --no-default-features
