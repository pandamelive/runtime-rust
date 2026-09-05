#!/bin/bash
# runtime-rust 启动脚本
# 双模式：
#   1. 纯 SSH 模式（默认）：不设置 RUNNER_TOKEN，只启动 sshd，行为与旧版完全一致
#   2. Runner 模式：设置 RUNNER_TOKEN + REPO_URL，后台启动 sshd，前台运行 GitHub Actions Runner

# ==================== SSH 密钥（两种模式都执行）====================
if [ ! -f /root/.ssh/id_ed25519 ]; then
  echo "[runtime-rust] 第一次启动，生成新的 ED25519 密钥对..."
  ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519 -N "" -C "runtime-rust-$(hostname)"
  cp /root/.ssh/id_ed25519.pub /root/.ssh/authorized_keys
  chmod 700 /root/.ssh
  chmod 600 /root/.ssh/id_ed25519 /root/.ssh/authorized_keys
  chmod 644 /root/.ssh/id_ed25519.pub
else
  echo "[runtime-rust] 密钥已存在，沿用原密钥（容器重启不重新生成）"
fi

rm -rf /workspace/.ssh
mkdir -p /workspace/.ssh
cp /root/.ssh/id_ed25519 /workspace/.ssh/id_ed25519
cp /root/.ssh/id_ed25519.pub /workspace/.ssh/id_ed25519.pub

WORKSPACE_OWNER=$(stat -c '%u:%g' /workspace 2>/dev/null || echo "0:0")
chown -R "$WORKSPACE_OWNER" /workspace/.ssh 2>/dev/null || true
chmod 700 /workspace/.ssh 2>/dev/null || true
chmod 600 /workspace/.ssh/id_ed25519 2>/dev/null || true
chmod 644 /workspace/.ssh/id_ed25519.pub 2>/dev/null || true

echo "[runtime-rust] 密钥已同步到 /workspace/.ssh/，所有者: $WORKSPACE_OWNER"
echo "[runtime-rust] cargo/rustc/sccache/cross 已全局可用"

# ==================== 启动 sshd ====================
echo "[runtime-rust] 启动 sshd..."
/usr/sbin/sshd

# ==================== Runner 模式判断 ====================
if [ -z "${RUNNER_TOKEN}" ] || [ -z "${REPO_URL}" ]; then
  echo "[runtime-rust] 未设置 RUNNER_TOKEN / REPO_URL，进入纯 SSH 模式"
  echo "[runtime-rust] SSH 监听 22 端口，root 密码: password"
  # 前台保持容器运行
  tail -f /dev/null
fi

# ==================== GitHub Actions Runner 模式 ====================
RUNNER_NAME="${RUNNER_NAME:-runtime-rust-$(hostname)}"
RUNNER_LABELS="${RUNNER_LABELS:-runtime-rust,self-hosted,linux,x64,rust}"
RUNNER_GROUP="${RUNNER_GROUP:-Default}"

echo "[runtime-rust] ===== GitHub Actions Runner 模式 ====="
echo "[runtime-rust] 仓库: ${REPO_URL}"
echo "[runtime-rust] 名称: ${RUNNER_NAME}"
echo "[runtime-rust] 标签: ${RUNNER_LABELS}"

# 注册 runner
echo "[runtime-rust] 注册 runner..."
cd /opt/runner
./config.sh \
    --unattended \
    --url "${REPO_URL}" \
    --token "${RUNNER_TOKEN}" \
    --name "${RUNNER_NAME}" \
    --labels "${RUNNER_LABELS}" \
    --runnergroup "${RUNNER_GROUP}" \
    --replace

# 退出时自动注销
cleanup() {
    echo ""
    echo "[runtime-rust] 注销 runner..."
    cd /opt/runner
    ./config.sh remove --unattended --token "${RUNNER_TOKEN}" || true
    exit 0
}
trap cleanup SIGTERM SIGINT

echo "[runtime-rust] 启动 runner，等待任务..."
./run.sh
