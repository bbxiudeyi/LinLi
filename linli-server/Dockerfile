# 多阶段构建：构建 Rust 二进制，再用极小镜像运行
FROM rust:1.95-slim AS builder
WORKDIR /app
# 先拷 manifests 利用 Docker 缓存
COPY Cargo.toml Cargo.lock ./
RUN mkdir src && echo "fn main() {}" > src/main.rs && \
    cargo build --release || true && rm -rf src
COPY migrations ./migrations
COPY src ./src
RUN touch src/main.rs && cargo build --release

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates libssl3 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder /app/target/release/linli-server /app/linli-server
COPY --from=builder /app/migrations /app/migrations
EXPOSE 8080
ENV HOST=0.0.0.0 PORT=8080
CMD ["/app/linli-server"]
