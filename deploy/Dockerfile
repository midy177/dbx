# syntax=docker/dockerfile:1

ARG BUN_VERSION=1.3.14
ARG RUST_VERSION=1

# Stage 1: Build frontend (native, no emulation)
FROM --platform=$BUILDPLATFORM oven/bun:${BUN_VERSION} AS frontend
WORKDIR /app
COPY package.json bun.lock ./
# The frontend build only needs the root deps. Strip "workspaces" so bun does
# not install the node packages (cli/mcp-server/node-core), which pull in
# better-sqlite3 - a native module that cannot build on this minimal image and
# is not used by the desktop app. The lockfile can't stay frozen once the
# workspace graph changes, so install without --frozen-lockfile.
RUN bun -e "const fs = require('node:fs'); const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8')); delete pkg.workspaces; fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2) + '\n');"
# Keep tarball extraction out of BuildKit's persistent cache. Rolldown's native
# optional packages are large, and stale cached tarballs can break extraction.
RUN bun install --cache-dir=/tmp/bun-install-cache \
    && rm -rf /tmp/bun-install-cache
COPY apps/desktop/ apps/desktop/
COPY crates/dbx-core/assets/database-drivers.manifest.json crates/dbx-core/assets/database-drivers.manifest.json
ARG DBX_PUBLIC_BASE_PATH=/
ENV DBX_PUBLIC_BASE_PATH=${DBX_PUBLIC_BASE_PATH}
RUN bun run build

# Stage 2: Cross-compile Rust backend for the requested platform (native, no emulation)
FROM --platform=$BUILDPLATFORM rust:${RUST_VERSION}-bookworm AS backend
ARG TARGETARCH
WORKDIR /app
RUN dpkg --add-architecture arm64 \
    && apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake pkg-config perl python3-pip gcc-aarch64-linux-gnu \
    libfontconfig-dev:arm64 libfreetype-dev:arm64 \
    && pip3 install --break-system-packages ziglang \
    && rustup target add x86_64-unknown-linux-gnu aarch64-unknown-linux-gnu \
    && rm -rf /var/lib/apt/lists/*
RUN --mount=type=cache,target=/usr/local/cargo/registry,sharing=locked \
    --mount=type=cache,target=/usr/local/cargo/git,sharing=locked \
    cargo install cargo-zigbuild

# Copy dependency manifests only and create dummy sources to pre-compile dependencies.
# This layer is cached by GHA as long as Cargo.toml/Cargo.lock don't change.
COPY Cargo.toml Cargo.lock ./
COPY crates/dbx-core/Cargo.toml crates/dbx-core/
COPY crates/dbx-web/Cargo.toml crates/dbx-web/
COPY src-tauri/Cargo.toml src-tauri/
RUN mkdir -p crates/dbx-core/src && echo '' > crates/dbx-core/src/lib.rs \
    && mkdir -p crates/dbx-web/src && echo 'fn main() {}' > crates/dbx-web/src/main.rs \
    && mkdir -p src-tauri/src && echo 'fn main() {}' > src-tauri/src/main.rs && echo 'pub fn run() {}' > src-tauri/src/lib.rs

COPY src-tauri/build.rs src-tauri/
COPY src-tauri/tauri.conf.json src-tauri/

RUN --mount=type=cache,target=/usr/local/cargo/registry,sharing=locked \
    --mount=type=cache,target=/usr/local/cargo/git,sharing=locked \
    --mount=type=cache,target=/app/target,sharing=locked \
    case "$TARGETARCH" in \
    amd64) rust_target=x86_64-unknown-linux-gnu; lib_arch=x86_64-linux-gnu ;; \
    arm64) rust_target=aarch64-unknown-linux-gnu; lib_arch=aarch64-linux-gnu ;; \
    *) echo "Unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac && \
    LIBRARY_PATH="/usr/lib/$lib_arch" \
    PKG_CONFIG_PATH="/usr/lib/$lib_arch/pkgconfig" \
    PKG_CONFIG_SYSROOT_DIR="/" \
    RUSTFLAGS="-L native=/usr/lib/$lib_arch" \
    cargo zigbuild --release -p dbx-web --target "$rust_target" || true

# Copy real sources and rebuild (only application code recompiles)
COPY crates/ crates/
COPY --from=frontend /app/dist dist/

# Docker COPY preserves original file timestamps, which may be older than the
# dummy-source binary compiled above. Touch all .rs files so cargo detects the
# source change and recompiles instead of reusing the dummy binary.
RUN find crates/ -name '*.rs' -exec touch {} +

RUN --mount=type=cache,target=/usr/local/cargo/registry,sharing=locked \
    --mount=type=cache,target=/usr/local/cargo/git,sharing=locked \
    --mount=type=cache,target=/app/target,sharing=locked \
    case "$TARGETARCH" in \
    amd64) rust_target=x86_64-unknown-linux-gnu; lib_arch=x86_64-linux-gnu ;; \
    arm64) rust_target=aarch64-unknown-linux-gnu; lib_arch=aarch64-linux-gnu ;; \
    *) echo "Unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac && \
    LIBRARY_PATH="/usr/lib/$lib_arch" \
    PKG_CONFIG_PATH="/usr/lib/$lib_arch/pkgconfig" \
    PKG_CONFIG_SYSROOT_DIR="/" \
    RUSTFLAGS="-L native=/usr/lib/$lib_arch" \
    cargo zigbuild --release -p dbx-web --target "$rust_target" --features embedded-static && \
    mkdir -p "/out/linux/$TARGETARCH" && \
    cp "/app/target/$rust_target/release/dbx-web" "/out/linux/$TARGETARCH/"

# Stage 3: Final image
FROM debian:bookworm-slim
ARG TARGETPLATFORM
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    fontconfig \
    fonts-dejavu-core \
    libfreetype6 \
    libssl3 \
    curl \
    && rm -rf /var/lib/apt/lists/*
COPY --from=backend /out/${TARGETPLATFORM}/dbx-web /usr/local/bin/
ENV DBX_DATA_DIR=/app/data
EXPOSE 4224
CMD ["dbx-web"]
