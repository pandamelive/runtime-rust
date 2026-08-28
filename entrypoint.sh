#!/bin/bash
# runtime-rust 启动脚本
# 1. 把 SSH 私钥复制到工作目录，方便其他容器（如 openhand）读取实现免密登录
# 2. 启动 sshd 服务

mkdir -p /workspace/.ssh
cp /root/.ssh/id_rsa /workspace/.ssh/id_rsa
cp /root/.ssh/id_rsa.pub /workspace/.ssh/id_rsa.pub
chmod 600 /workspace/.ssh/id_rsa 2>/dev/null || true
chmod 644 /workspace/.ssh/id_rsa.pub 2>/dev/null || true

echo "[runtime-rust] SSH 私钥已复制到 /workspace/.ssh/id_rsa"
echo "[runtime-rust] 其他容器可通过此私钥免密登录本容器"
echo "[runtime-rust] 启动 sshd..."

exec /usr/sbin/sshd -D
