# runtime-rust - Rust 构建环境镜像
# 包含 stable 工具链、sccache、cross、musl-tools 等，用于 CI/CD 和本地构建

FROM ubuntu:22.04

LABEL maintainer="PandaNetPL"
LABEL description="Rust 构建环境 - stable/sccache/cross/musl-tools"

# 避免交互式配置
ENV DEBIAN_FRONTEND=noninteractive

# 安装系统依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    git \
    pkg-config \
    libssl-dev \
    musl-tools \
    perl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 安装 Rust stable 工具链
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal \
    && rustup target add x86_64-unknown-linux-musl \
    && rustup target add aarch64-unknown-linux-musl \
    && rustup target add x86_64-pc-windows-msvc \
    && rustup target add x86_64-apple-darwin \
    && rustup target add aarch64-apple-darwin

# 安装 sccache（编译缓存）
RUN cargo install sccache --locked

# 安装 cross（交叉编译）
RUN cargo install cross --locked

# 配置 sccache 环境变量
ENV RUSTC_WRAPPER=sccache \
    SCCACHE_DIR=/cache/sccache \
    SCCACHE_CACHE_SIZE=20G

# 创建缓存目录
RUN mkdir -p /cache/sccache

# 验证安装
RUN rustc --version && cargo --version && sccache --version && cross --version

WORKDIR /workspace

CMD ["bash"]
