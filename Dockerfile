# runtime-rust - Rust 构建环境镜像（全量工具版）
# 包含 stable 工具链(default profile)、sccache、cross、musl-tools、mold、SSH 服务端、
# rustfmt、clippy、PowerShell、cargo-deny/udeps/outdated/nextest/bloat、调试工具等
FROM ubuntu:22.04
LABEL maintainer="PandaNetPL"
LABEL description="Rust 构建环境 - stable(default)/sccache/cross/musl-tools/mold/ssh/rustfmt/clippy/pwsh/cargo-tools (full)"

# 避免交互式配置
ENV DEBIAN_FRONTEND=noninteractive

# 使用国内 apt 源（阿里云），提升国内构建和运行时 apt 速度
RUN sed -i 's|archive.ubuntu.com|mirrors.aliyun.com|g' /etc/apt/sources.list && \
    sed -i 's|security.ubuntu.com|mirrors.aliyun.com|g' /etc/apt/sources.list

# 安装系统依赖（编译基础 + 开发工具 + 调试工具）
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
    # 文本/JSON 处理
    ripgrep \
    jq \
    fd-find \
    # 数据库调试
    sqlite3 \
    # 构建/脚本
    make \
    python3 \
    python3-pip \
    # 网络/调试
    lsof \
    net-tools \
    iproute2 \
    tcpdump \
    strace \
    gdb \
    # 压缩/同步
    zip \
    unzip \
    rsync \
    && rm -rf /var/lib/apt/lists/*

# 安装 PowerShell（合规脚本 check-compliance.ps1 运行环境）
RUN apt-get update && apt-get install -y --no-install-recommends \
        wget \
        apt-transport-https \
        software-properties-common \
    && wget -q --retry=3 --tries=3 "https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb" \
    && dpkg -i packages-microsoft-prod.deb \
    && apt-get update && apt-get install -y --no-install-recommends \
        powershell \
    && rm -rf /var/lib/apt/lists/* packages-microsoft-prod.deb

# 配置 SSH 服务端（密钥在 entrypoint.sh 第一次启动时生成，容器重启不重新生成）
RUN mkdir -p /run/sshd /root/.ssh \
    && chmod 700 /root/.ssh \
    && sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    && echo "root:password" | chpasswd

# 安装 Rust stable 工具链（default profile 含 rustfmt + clippy + rust-docs）
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH

# 验证阶段只需 x86_64-unknown-linux-musl（静态二进制验证）
# 发布阶段需要更多 target 时，取消注释对应行：
#   rustup target add aarch64-unknown-linux-musl
#   rustup target add x86_64-pc-windows-gnu
#   (注意: win-msvc / apple-darwin 在 Linux 上无法真正链接，需对应 SDK)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile default \
    && rustup target add x86_64-unknown-linux-musl

# 【关键】先配置 cargo 国内源（rsproxy），确保后续所有 cargo install 走国内镜像
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

# 安装 sccache（编译缓存）
RUN cargo install sccache --locked

# 安装 cross（交叉编译）
RUN cargo install cross --locked

# 安装 cargo 开发工具（分开安装，便于定位问题；cargo-expand 需 nightly，暂不包含）
RUN cargo install cargo-deny --locked
RUN cargo install cargo-udeps --locked
RUN cargo install cargo-outdated --locked
RUN cargo install cargo-nextest --locked
RUN cargo install cargo-bloat --locked

# 安装 mold 快速链接器（固定版本，避免 GitHub API 限流导致构建失败）
ENV MOLD_VERSION=2.42.0
RUN curl -fsSL --retry 3 --retry-delay 5 \
    "https://github.com/rui314/mold/releases/download/v${MOLD_VERSION}/mold-${MOLD_VERSION}-x86_64-linux.tar.gz" \
    -o /tmp/mold.tar.gz \
    && tar -xzf /tmp/mold.tar.gz -C /tmp \
    && cp /tmp/mold-${MOLD_VERSION}-x86_64-linux/bin/mold /usr/local/bin/mold \
    && cp /tmp/mold-${MOLD_VERSION}-x86_64-linux/bin/ld.mold /usr/local/bin/ld.mold \
    && rm -rf /tmp/mold* \
    && mold --version

# 配置 sccache
ENV RUSTC_WRAPPER=sccache \
    SCCACHE_DIR=/cache/sccache \
    SCCACHE_CACHE_SIZE=20G

RUN mkdir -p /cache/sccache

# 【关键优化】创建全局符号链接，确保 cargo/rustc 在任何 shell（包括 SSH non-login）都可用
# default profile 下 rustfmt/clippy 一定存在，无需静默失败
RUN ln -sf /usr/local/cargo/bin/cargo /usr/local/bin/cargo && \
    ln -sf /usr/local/cargo/bin/rustc /usr/local/bin/rustc && \
    ln -sf /usr/local/cargo/bin/rustup /usr/local/bin/rustup && \
    ln -sf /usr/local/cargo/bin/sccache /usr/local/bin/sccache && \
    ln -sf /usr/local/cargo/bin/cross /usr/local/bin/cross && \
    ln -sf /usr/local/cargo/bin/cargo-clippy /usr/local/bin/cargo-clippy && \
    ln -sf /usr/local/cargo/bin/cargo-fmt /usr/local/bin/cargo-fmt && \
    ln -sf /usr/local/cargo/bin/rustfmt /usr/local/bin/rustfmt && \
    ln -sf /usr/local/cargo/bin/cargo-deny /usr/local/bin/cargo-deny && \
    ln -sf /usr/local/cargo/bin/cargo-udeps /usr/local/bin/cargo-udeps && \
    ln -sf /usr/local/cargo/bin/cargo-outdated /usr/local/bin/cargo-outdated && \
    ln -sf /usr/local/cargo/bin/cargo-nextest /usr/local/bin/cargo-nextest && \
    ln -sf /usr/local/cargo/bin/cargo-bloat /usr/local/bin/cargo-bloat && \
    ln -sf /usr/bin/pwsh /usr/local/bin/pwsh && \
    ln -sf /usr/bin/fdfind /usr/local/bin/fd

# 【双保险】环境变量写入 /etc/environment，确保 SSH non-login shell 继承
RUN echo 'CARGO_HOME=/usr/local/cargo' >> /etc/environment && \
    echo 'RUSTUP_HOME=/usr/local/rustup' >> /etc/environment && \
    echo 'RUSTC_WRAPPER=sccache' >> /etc/environment && \
    echo 'SCCACHE_DIR=/cache/sccache' >> /etc/environment && \
    echo 'SCCACHE_CACHE_SIZE=20G' >> /etc/environment && \
    echo 'PATH=/usr/local/cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' >> /etc/environment

# GitHub Actions Runner（设置 RUNNER_TOKEN 时自动启用，不设置则纯 SSH 模式）
ARG RUNNER_VERSION=2.319.1
RUN arch=$(uname -m) && \
    curl -fsSL --retry 3 --retry-delay 5 \
    "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${arch}-${RUNNER_VERSION}.tar.gz" \
    -o /tmp/runner.tar.gz && \
    mkdir -p /opt/runner && tar xzf /tmp/runner.tar.gz -C /opt/runner && \
    rm /tmp/runner.tar.gz && \
    /opt/runner/bin/installdependencies.sh
ENV PATH=/opt/runner/bin:$PATH

# 验证安装（用 which 确保工具存在，避免 --version 输出格式差异导致失败）
RUN which rustc && which cargo && which rustfmt && which cargo-clippy && \
    which sccache && which cross && which mold && which clang && \
    which pwsh && which cargo-deny && which cargo-nextest && \
    which rg && which jq && which sqlite3 && which fd && \
    rustc --version && cargo --version && rustfmt --version && \
    cargo clippy --version && sccache --version && cross --version && \
    mold --version && pwsh --version

# 复制启动脚本
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /workspace
EXPOSE 22
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
