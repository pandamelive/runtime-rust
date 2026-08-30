# runtime-rust

Rust 构建环境 Docker 镜像，用于 CI/CD 和本地构建 Rust 项目。

## 生态定位

本项目是 **PandaNetOS 生态项目群**的标准 Rust 构建环境镜像，为 [PandaNetOS](https://github.com/PandaNetOS/PandaNetOS) 生态下所有 Rust 项目（PK、SPDE 等）提供统一的编译环境。

### 标准库路径约定

使用本镜像构建生态项目时，项目需与 `PandaNetOS` 标准库仓库保持同级目录布局：

```
<workspace>/
├── PandaNetOS/              # 标准库仓库（必须与项目同级）
│   └── crates/pandanetos/
├── pk/                      # 主控台
└── spde/                    # 下载节点
```

项目 `Cargo.toml` 中统一使用 path 依赖：

```toml
[dependencies]
pandanetos = { path = "../PandaNetOS/crates/pandanetos" }
```

> 本镜像内置 sccache、cross、mold、musl-tools 等工具，配合上述目录布局可直接构建生态项目。

## 包含组件

| 组件 | 说明 |
|------|------|
| Rust stable | 最新稳定版工具链 |
| clippy / rustfmt | 静态检查组件（`cargo clippy`/`cargo fmt`） |
| sccache | 编译缓存，大幅提升重复构建速度 |
| cross | 交叉编译工具 |
| mold | 快速链接器（默认链接器，提升链接速度） |
| musl-tools | musl 静态编译支持 |
| cmake / clang / llvm | C 工具链（bindgen / openssl-sys 等依赖需要） |
| perl | OpenSSL 编译依赖 |
| build-essential | C/C++ 编译工具链 |
| 验证 target | x86_64-unknown-linux-musl（静态二进制验证，验证阶段只需这一个） |
| 发布 target | aarch64-unknown-linux-musl / x86_64-pc-windows-gnu 等按需添加（win-msvc / apple-darwin 在 Linux 上无法真正链接，需对应 SDK） |

> 工具链全局可用：`cargo`/`rustc`/`rustup`/`sccache`/`cross`/`cargo-clippy`/`cargo-fmt` 已符号链接到 `/usr/local/bin` 并写入 `/etc/environment`，SSH 登录（non-login shell）也能直接用。
> 依赖下载走国内镜像源（rsproxy sparse），链接默认走 mold。
> apt 源已切换为阿里云镜像，国内构建和运行时更快。

## SSH 密钥说明

### 密钥生成策略

- **第一次启动容器**：自动生成一对新的 ED25519 SSH 密钥对
- **容器重启（docker restart）**：沿用原密钥，不重新生成
- **容器重建（docker rm + docker run / compose up --force-recreate）**：生成新的密钥对

### 密钥位置

容器内密钥路径：
- 私钥：`/root/.ssh/id_ed25519`
- 公钥：`/root/.ssh/id_ed25519.pub`
- authorized_keys：`/root/.ssh/authorized_keys`（自动写入公钥，免密登录用）

持久化目录密钥路径（每次启动自动清空旧目录并放入最新密钥）：
- 私钥：`/workspace/.ssh/id_ed25519`
- 公钥：`/workspace/.ssh/id_ed25519.pub`

> **重要**：每次容器启动都会执行 `rm -rf /workspace/.ssh`，清空整个密钥目录后再放入最新密钥。这确保了持久化目录里只有当前容器的最新密钥，不会残留旧版本（如 `id_rsa`）或上次容器的密钥。

### agent-canvas 容器里的密钥路径

如果 agent-canvas 容器挂载了 runtime-rust 的 `/workspace` 目录（或共享同一 volume），在 agent-canvas 容器内读取密钥的路径为：

- **当前版本（ED25519）**：`/home/openhands/workspace/.ssh/id_ed25519`
- **旧版本（RSA）**：`/home/openhands/workspace/.ssh/id_rsa`（已废弃，v2 起不再生成）

> 注意：v2 版本起密钥类型从 RSA 改为 ED25519，文件名从 `id_rsa` 变为 `id_ed25519`。每次启动会清空旧目录，所以升级后 agent-canvas 里只会看到 `id_ed25519`，不会有旧的 `id_rsa` 残留。

### 权限设置

- `/workspace/.ssh/` 目录：700
- 私钥 `id_ed25519`：600
- 公钥 `id_ed25519.pub`：644
- 所有者：自动匹配 `/workspace` 目录的所有者（方便其他容器如 agent-canvas 的 openhands 用户读取）

### 其他容器免密登录

如果其他容器（如 agent-canvas）挂载了同一个 `/workspace` 目录，可以直接读取私钥免密登录 runtime-rust：

```bash
# agent-canvas 容器内执行
ssh -i /home/openhands/workspace/.ssh/id_ed25519 -p 2222 \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  root@<runtime-rust-ip>
```

连接后直接可用 cargo（已全局配置，不需要 source 任何环境脚本）：
```bash
ssh -i /home/openhands/workspace/.ssh/id_ed25519 -p 2222 root@<runtime-rust-ip> \
  'cd /workspace/project && cargo build --release'
```

### root 密码

默认 root 密码为 `password`（内网环境使用，如需更安全请修改或禁用密码登录）。

## 镜像地址

```
ghcr.io/pandamelive/runtime-rust:latest
```

## 使用方法

### Docker 直接使用

```bash
docker pull ghcr.io/pandamelive/runtime-rust:latest
docker run --rm -it -v $(pwd):/workspace ghcr.io/pandamelive/runtime-rust:latest cargo build --release
```

### Docker Compose 使用（推荐）

```bash
# 项目目录挂载到 /workspace，sccache 缓存用命名卷持久化（容器重建后缓存不丢）
docker compose up -d
# 进入容器构建
docker compose exec runtime-rust bash
```

- `./project` → `/workspace`：你的项目目录（唯一挂载点）
- `sccache-cache` → `/cache/sccache`：命名卷，sccache 编译缓存跨容器重建保留

### GitHub Actions 使用

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    container:
      image: ghcr.io/pandamelive/runtime-rust:latest
    steps:
      - uses: actions/checkout@v4
      - name: Cache sccache
        uses: actions/cache@v4
        with:
          path: /cache/sccache
          key: sccache-${{ runner.os }}-${{ hashFiles('**/Cargo.lock') }}
          restore-keys: |
            sccache-${{ runner.os }}-
      - name: Build
        run: cargo build --release
```

### 本地交叉编译

```bash
# 编译 Linux musl 静态二进制
docker run --rm -v $(pwd):/workspace ghcr.io/pandamelive/runtime-rust:latest \
  cargo build --release --target x86_64-unknown-linux-musl
```

### 验证阶段 target 说明

- **验证阶段（CI / agent 日常验证）只需 `x86_64-unknown-linux-musl`** 一个 target：
  - spde/pk 等项目的 `cargo build / test / clippy` 日常验证在 gnu target 下完成；
  - 需要静态二进制产物验证时，用 `x86_64-unknown-linux-musl` 编译即可。
- **发布阶段**才按目标平台增加 target（aarch64-unknown-linux-musl、x86_64-pc-windows-gnu 等），已注释在 Dockerfile 中，按需取消注释。
- 注意：`x86_64-pc-windows-msvc`、`x86_64-apple-darwin`、`aarch64-apple-darwin` 在 Linux 主机上无法真正链接（缺对应 SDK/工具链），不做验证 target。

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `RUSTC_WRAPPER` | `sccache` | 自动启用 sccache 编译缓存 |
| `SCCACHE_DIR` | `/cache/sccache` | sccache 缓存目录 |
| `SCCACHE_CACHE_SIZE` | `20G` | 缓存大小上限 |

## 构建镜像

```bash
docker build -t runtime-rust .
```

## License

MIT