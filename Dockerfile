# runtime-rust - Rust 构建环境镜像（全量工具版）
# 包含 stable 工具链、rustfmt、clippy、sccache、cross、cargo 工具集、
# mingw-w64(Windows交叉编译)、mold、PowerShell、SSH 服务端、GitHub Actions Runner 等
FROM ubuntu:22.04
LABEL maintainer="PandaNetPL"
LABEL description="Rust 构建环境 - stable/rustfmt/clippy/sccache/cross/mingw-w64/mold/pwsh/ssh (full)"

# 避免交互式配置
ENV DEBIAN_FRONTEND=noninteractive

# 使用国内 apt 源（阿里云），提升国内构建和运行时 apt 速度
RUN sed -i 's|archive.ubuntu.com|mirrors.aliyun.com|g' /etc/apt/sources.list && \
    sed -i 's|security.ubuntu.com|mirrors.aliyun.com|g' /etc/apt/sources.list

# 安装系统依赖（编译基础 + Windows交叉编译 + 开发工具 + 调试工具）
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
    # Windows 交叉编译
    mingw-w64 \
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
    # 非交互式 SSH（同步代码到远程节点）
    sshpass \
    && rm -rf /var/lib/apt/lists/*

# 安装 PowerShell（合规脚本 check-compliance.ps1 运行环境）
# 用 curl 代替 wget，避免 wget --retry 参数歧义
RUN apt-get update && apt-get install -y --no-install-recommends \
        apt-transport-https \
        software-properties-common \
    && curl -fsSL --retry 3 "https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb" \
        -o packages-microsoft-prod.deb \
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

# 安装 Rust stable 工具链 + rustfmt + clippy + Windows target
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal \
    && rustup target add x86_64-unknown-linux-musl \
    && rustup target add x86_64-pc-windows-gnu \
    && rustup component add rustfmt clippy

# 安装 sccache（编译缓存）
RUN cargo install sccache --locked

# 安装 cross（交叉编译）
RUN cargo install cross --locked

# 安装 cargo 工具集
RUN cargo install cargo-deny --locked && \
    cargo install cargo-udeps --locked && \
    cargo install cargo-outdated --locked && \
    cargo install cargo-nextest --locked && \
    cargo install cargo-bloat --locked && \
    cargo install cargo-edit --locked && \
    cargo install cargo-watch --locked && \
    cargo install cargo-expand --locked

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

# 配置 cargo 国内源（rsproxy，国内依赖下载更快）+ mold 链接器 + Windows 交叉编译
# 注意：此配置在 cargo install 之后，确保 GitHub Actions（国外）构建时从 crates.io 下载
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

# Windows 交叉编译
[target.x86_64-pc-windows-gnu]
linker = "x86_64-w64-mingw32-gcc"
EOF

# 配置 sccache
ENV RUSTC_WRAPPER=sccache \
    SCCACHE_DIR=/cache/sccache \
    SCCACHE_CACHE_SIZE=20G

RUN mkdir -p /cache/sccache

# 【关键优化】创建全局符号链接，确保所有工具在任何 shell（包括 SSH non-login）都可用
RUN ln -sf /usr/local/cargo/bin/cargo /usr/local/bin/cargo && \
    ln -sf /usr/local/cargo/bin/rustc /usr/local/bin/rustc && \
    ln -sf /usr/local/cargo/bin/rustup /usr/local/bin/rustup && \
    ln -sf /usr/local/cargo/bin/rustfmt /usr/local/bin/rustfmt && \
    ln -sf /usr/local/cargo/bin/cargo-fmt /usr/local/bin/cargo-fmt && \
    ln -sf /usr/local/cargo/bin/cargo-clippy /usr/local/bin/cargo-clippy && \
    ln -sf /usr/local/cargo/bin/sccache /usr/local/bin/sccache && \
    ln -sf /usr/local/cargo/bin/cross /usr/local/bin/cross && \
    ln -sf /usr/local/cargo/bin/cargo-deny /usr/local/bin/cargo-deny && \
    ln -sf /usr/local/cargo/bin/cargo-udeps /usr/local/bin/cargo-udeps && \
    ln -sf /usr/local/cargo/bin/cargo-outdated /usr/local/bin/cargo-outdated && \
    ln -sf /usr/local/cargo/bin/cargo-nextest /usr/local/bin/cargo-nextest && \
    ln -sf /usr/local/cargo/bin/cargo-bloat /usr/local/bin/cargo-bloat && \
    ln -sf /usr/local/cargo/bin/cargo-add /usr/local/bin/cargo-add && \
    ln -sf /usr/local/cargo/bin/cargo-rm /usr/local/bin/cargo-rm && \
    ln -sf /usr/local/cargo/bin/cargo-upgrade /usr/local/bin/cargo-upgrade && \
    ln -sf /usr/local/cargo/bin/cargo-watch /usr/local/bin/cargo-watch && \
    ln -sf /usr/local/cargo/bin/cargo-expand /usr/local/bin/cargo-expand && \
    ln -sf /usr/bin/pwsh /usr/local/bin/pwsh && \
    ln -sf /usr/bin/fdfind /usr/local/bin/fd && \
    ln -sf /usr/bin/x86_64-w64-mingw32-gcc /usr/local/bin/x86_64-w64-mingw32-gcc

# 【双保险】环境变量写入 /etc/environment，确保 SSH non-login shell 继承
RUN echo 'CARGO_HOME=/usr/local/cargo' >> /etc/environment && \
    echo 'RUSTUP_HOME=/usr/local/rustup' >> /etc/environment && \
    echo 'RUSTC_WRAPPER=sccache' >> /etc/environment && \
    echo 'SCCACHE_DIR=/cache/sccache' >> /etc/environment && \
    echo 'SCCACHE_CACHE_SIZE=20G' >> /etc/environment && \
    echo 'PATH=/usr/local/cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' >> /etc/environment

# GitHub Actions Runner（设置 RUNNER_TOKEN 时自动启用，不设置则纯 SSH 模式）
# 注意：uname -m 返回 x86_64，但 GitHub Runner 文件名用 x64，需映射
ARG RUNNER_VERSION=2.319.1
RUN arch=$(uname -m) && \
    if [ "$arch" = "x86_64" ]; then arch="x64"; fi && \
    curl -fsSL --retry 3 --retry-delay 5 \
    "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${arch}-${RUNNER_VERSION}.tar.gz" \
    -o /tmp/runner.tar.gz && \
    mkdir -p /opt/runner && tar xzf /tmp/runner.tar.gz -C /opt/runner && \
    rm /tmp/runner.tar.gz && \
    /opt/runner/bin/installdependencies.sh
ENV PATH=/opt/runner/bin:$PATH

# 验证安装（全量工具验证）
RUN rustc --version && \
    cargo --version && \
    rustfmt --version && \
    cargo clippy --version && \
    sccache --version && \
    cross --version && \
    mold --version && \
    pwsh --version && \
    x86_64-w64-mingw32-gcc --version | head -1 && \
    rg --version | head -1 && \
    jq --version && \
    sqlite3 --version && \
    cargo deny --version && \
    cargo nextest --version && \
    cargo watch --version

# 复制启动脚本
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /workspace
EXPOSE 22
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
