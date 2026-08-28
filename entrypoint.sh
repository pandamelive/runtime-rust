#!/bin/bash
# runtime-rust 启动脚本（优化版）
# 1. 把 SSH 私钥复制到工作目录，自动匹配所有者，方便其他容器读取免密登录
# 2. 启动 sshd 服务

mkdir -p /workspace/.ssh

# 复制密钥
cp /root/.ssh/id_rsa /workspace/.ssh/id_rsa
cp /root/.ssh/id_rsa.pub /workspace/.ssh/id_rsa.pub

# 【关键优化】自动匹配 /workspace 目录的所有者和权限
# 这样挂载同一目录的其他容器（如 agent-canvas 的 openhands 用户）能直接读取
WORKSPACE_OWNER=$(stat -c '%u:%g' /workspace 2>/dev/null || echo "0:0")
chown -R "$WORKSPACE_OWNER" /workspace/.ssh 2>/dev/null || true
chmod 700 /workspace/.ssh 2>/dev/null || true
chmod 600 /workspace/.ssh/id_rsa 2>/dev/null || true
chmod 644 /workspace/.ssh/id_rsa.pub 2>/dev/null || true

echo "[runtime-rust] SSH 私钥已复制到 /workspace/.ssh/id_rsa"
echo "[runtime-rust] 所有者匹配: $WORKSPACE_OWNER"
echo "[runtime-rust] 其他容器可通过此私钥免密登录本容器"
echo "[runtime-rust] cargo/rustc 已全局可用（符号链接 + /etc/environment）"
echo "[runtime-rust] 启动 sshd..."
exec /usr/sbin/sshd -D