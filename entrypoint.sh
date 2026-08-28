#!/bin/bash
# runtime-rust 启动脚本（优化版）
# 1. 第一次启动时生成 SSH 密钥对（容器重启不重新生成，容器重建才生成新的）
# 2. 每次启动都清空 /workspace/.ssh/ 目录，放入最新密钥（删除旧密钥，只保留最新的）
# 3. 启动 sshd 服务

# 第一次启动时生成密钥对（仅当不存在时，容器重启沿用原密钥，容器重建才生成新的）
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

# 每次启动都清空 /workspace/.ssh/ 目录（删除旧密钥，包括 id_rsa 等历史残留），然后放入最新密钥
# 因为 /workspace 是持久化挂载，可能保留了上次容器的旧密钥，必须清空确保只有最新的
rm -rf /workspace/.ssh
mkdir -p /workspace/.ssh
cp /root/.ssh/id_ed25519 /workspace/.ssh/id_ed25519
cp /root/.ssh/id_ed25519.pub /workspace/.ssh/id_ed25519.pub

# 自动匹配 /workspace 目录的所有者和权限
# 这样挂载同一目录的其他容器（如 agent-canvas 的 openhands 用户）能直接读取
WORKSPACE_OWNER=$(stat -c '%u:%g' /workspace 2>/dev/null || echo "0:0")
chown -R "$WORKSPACE_OWNER" /workspace/.ssh 2>/dev/null || true
chmod 700 /workspace/.ssh 2>/dev/null || true
chmod 600 /workspace/.ssh/id_ed25519 2>/dev/null || true
chmod 644 /workspace/.ssh/id_ed25519.pub 2>/dev/null || true

echo "[runtime-rust] 已清空 /workspace/.ssh/ 并放入最新密钥（仅保留 id_ed25519）"
echo "[runtime-rust] 所有者匹配: $WORKSPACE_OWNER"
echo "[runtime-rust] 其他容器可通过此私钥免密登录本容器"
echo "[runtime-rust] 密钥策略: 第一次启动生成，容器重启沿用，容器重建才生成新的"
echo "[runtime-rust] cargo/rustc 已全局可用（符号链接 + /etc/environment）"
echo "[runtime-rust] 启动 sshd..."
exec /usr/sbin/sshd -D