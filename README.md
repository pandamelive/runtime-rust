# runtime-rust

Rust 构建环境 Docker 镜像，用于 CI/CD 和本地构建 Rust 项目。

## 包含组件

| 组件 | 说明 |
|------|------|
| Rust stable | 最新稳定版工具链 |
| sccache | 编译缓存，大幅提升重复构建速度 |
| cross | 交叉编译工具 |
| musl-tools | musl 静态编译支持 |
| perl | OpenSSL 编译依赖 |
| build-essential | C/C++ 编译工具链 |
| 常用 target | x86_64-linux-musl / aarch64-linux-musl / x86_64-windows-msvc / x86_64-apple-darwin / aarch64-apple-darwin |

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
