# runtime-rust - Rust 构建环境镜像（优化版）
# 包含 stable 工具链、sccache、cross、musl-tools、mold、SSH 服务端等
FROM ubuntu:22.04
LABEL maintainer="PandaNetPL"
LABEL description="Rust 构建环境 - stable/sccache/cross/musl-tools/mold/ssh (optimized)"

# 避免交互式配置
ENV DEBIAN_FRONTEND=noninteractive

# 安装系统依赖（新增 cmake/clang/libclang-dev/mold 依赖）
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    git \
    pkg-config \
    libssl-dev \
    musl-tools \
    perl \
    openssh-client \
    openssh-server \
    ca-certificates \
    cmake \
    clang \
    libclang-dev \
    llvm-dev \
    libxml2-dev \
    libsqlite3-dev \
    xz-utils \
    file \
    jq \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# 配置 SSH 服务端 + 生成默认密钥对（免密登录用）
RUN mkdir -p /run/sshd /root/.ssh \
    && chmod 700 /root/.ssh \
    && ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N "" -C "runtime-rust-default" \
    && cp /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys \
    && chmod 600 /root/.ssh/id_rsa /root/.ssh/authorized_keys \
    && sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    && echo "root:password" | chpasswd

# 安装 Rust stable 工具链
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH

# 验证阶段只需 x86_64-unknown-linux-musl（静态二进制验证）
# 发布阶段需要更多 target 时，取消注释对应行：
#   rustup target add aarch64-unknown-linux-musl
#   rustup target add x86_64-pc-windows-gnu
#   (注意: win-msvc / apple-darwin 在 Linux 上无法真正链接，需对应 SDK)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal \
    && rustup component add clippy rustfmt \
    && rustup target add x86_64-unknown-linux-musl

# 安装 sccache（编译缓存）
RUN cargo install sccache --locked

# 安装 cross（交叉编译）
RUN cargo install cross --locked

# 安装 mold 快速链接器（从 GitHub 下载最新版）
RUN MOLD_VERSION=$(curl -s --retry 3 --retry-delay 5 https://api.github.com/repos/rui314/mold/releases/latest | grep -oP '"tag_name": "\K[^"]+') \
    && curl -fsSL --retry 3 --retry-delay 5 "https://github.com/rui314/mold/releases/download/${MOLD_VERSION}/mold-${MOLD_VERSION}-x86_64-linux.tar.gz" -o /tmp/mold.tar.gz \
    && tar -xzf /tmp/mold.tar.gz -C /tmp \
    && cp /tmp/mold-${MOLD_VERSION}-x86_64-linux/bin/mold /usr/local/bin/mold \
    && cp /tmp/mold-${MOLD_VERSION}-x86_64-linux/bin/ld.mold /usr/local/bin/ld.mold \
    && rm -rf /tmp/mold* \
    && mold --version

# 配置 cargo 国内源（rsproxy，国内依赖下载更快）+ mold 链接器
RUN mkdir -p /usr/local/cargo \
    && cat > /usr/local/cargo/config.toml << 'EOF'
[source.crates-io]
replace-with = 'rsproxy-sparse'

[source.rsproxy]
registry = "https://rsproxy.cn/crates.io-index"

[source.rsproxy-sparse]
registry = "sparse+https://rsproxy.cn/index/"

[registries.rsproxy]
index = "https://rsproxy.cn/crates.io-index"

[net]
git-fetch-with-cli = true

# 使用 mold 作为默认链接器（提升链接速度）
[target.x86_64-unknown-linux-gnu]
linker = "clang"
rustflags = ["-C", "link-arg=-fuse-ld=mold"]

[target.x86_64-unknown-linux-musl]
rustflags = ["-C", "link-arg=-fuse-ld=mold"]
EOF

# 配置 sccache
ENV RUSTC_WRAPPER=sccache \
    SCCACHE_DIR=/cache/sccache \
    SCCACHE_CACHE_SIZE=20G

RUN mkdir -p /cache/sccache

# 【关键优化】创建全局符号链接，确保 cargo/rustc 在任何 shell（包括 SSH non-login）都可用
RUN ln -sf /usr/local/cargo/bin/cargo /usr/local/bin/cargo && \
    ln -sf /usr/local/cargo/bin/rustc /usr/local/bin/rustc && \
    ln -sf /usr/local/cargo/bin/rustup /usr/local/bin/rustup && \
    ln -sf /usr/local/cargo/bin/sccache /usr/local/bin/sccache && \
    ln -sf /usr/local/cargo/bin/cross /usr/local/bin/cross && \
    ln -sf /usr/local/cargo/bin/cargo-clippy /usr/local/bin/cargo-clippy 2>/dev/null || true && \
    ln -sf /usr/local/cargo/bin/cargo-fmt /usr/local/bin/cargo-fmt 2>/dev/null || true && \
    ln -sf /usr/local/cargo/bin/rustfmt /usr/local/bin/rustfmt 2>/dev/null || true

# 【双保险】环境变量写入 /etc/environment，确保 SSH non-login shell 继承
RUN echo 'CARGO_HOME=/usr/local/cargo' >> /etc/environment && \
    echo 'RUSTUP_HOME=/usr/local/rustup' >> /etc/environment && \
    echo 'RUSTC_WRAPPER=sccache' >> /etc/environment && \
    echo 'SCCACHE_DIR=/cache/sccache' >> /etc/environment && \
    echo 'SCCACHE_CACHE_SIZE=20G' >> /etc/environment && \
    echo 'PATH=/usr/local/cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' >> /etc/environment

# 验证安装
RUN rustc --version && cargo --version && sccache --version && cross --version && mold --version && clang --version | head -1

# 复制启动脚本
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /workspace
EXPOSE 22
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
