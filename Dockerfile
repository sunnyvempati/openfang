# syntax=docker/dockerfile:1
FROM rust:1-slim-bookworm AS builder
WORKDIR /build
RUN apt-get update && apt-get install -y pkg-config libssl-dev && rm -rf /var/lib/apt/lists/*
COPY Cargo.toml Cargo.lock ./
COPY crates ./crates
COPY xtask ./xtask
COPY agents ./agents
COPY packages ./packages
RUN cargo build --release --bin openfang

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y ca-certificates chromium curl && rm -rf /var/lib/apt/lists/*
COPY --from=builder /build/target/release/openfang /usr/local/bin/
COPY --from=builder /build/agents /opt/openfang/agents
COPY openfang.toml /opt/openfang/config.toml
EXPOSE 4200
ENV OPENFANG_HOME=/data
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["entrypoint.sh"]
