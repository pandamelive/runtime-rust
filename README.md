# runtime-rust

Rust 构建环境 Docker 镜像，用于 CI/CD 和本地构建 Rust 项目。

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
