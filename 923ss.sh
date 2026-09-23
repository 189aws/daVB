#!/bin/bash
set -e

# ========== 配置区 ==========
TG_TOKEN="8896559295:AAHWVHQVJfoWG9v4McFg2qJgACw0nEpMxJo"
TG_CHAT_ID="1417748881"

# 随机生成参数
LISTEN_PORT=$(shuf -i 30000-50000 -n 1)      # 外部随机监听端口
SS_KEY=$(openssl rand -base64 16)            # 16 字节 Base64 密钥
# ============================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

log "检查基础环境并安装 Docker..."
apt-get update -qq && apt-get install -y -qq openssl python3 curl >/dev/null 2>&1

if ! command -v docker &>/dev/null; then
    apt-get install -y -qq docker.io
    systemctl start docker && systemctl enable docker
fi

log "清理旧容器..."
docker rm -f ss-v2ray-plugin 2>/dev/null || true

log "启动 SS-Rust + v2ray-plugin 容器..."
# 使用 shadowsocks-rust 镜像，内置 v2ray-plugin
docker run -d \
    --name ss-v2ray-plugin \
    --restart always \
    -p ${LISTEN_PORT}:${LISTEN_PORT}/tcp \
    -p ${LISTEN_PORT}:${LISTEN_PORT}/udp \
    ghcr.io/shadowsocks/ssserver-rust:latest \
    ssserver \
        -s "0.0.0.0:${LISTEN_PORT}" \
        -m "2022-blake3-aes-128-gcm" \
        -k "${SS_KEY}" \
        --plugin "v2ray-plugin" \
        --plugin-opts "server;path=/ss-ws"

SERVER_IP=$(curl -s --max-time 10 ipv4.icanhazip.com || curl -s --max-time 10 api.ipify.org)

# 生成 SS 链接 (带 v2ray-plugin 参数)
PLUGIN_OPTS="plugin=v2ray-plugin;mode=websocket;path=/ss-ws"
SS_B64=$(python3 -c "
import base64
raw = '2022-blake3-aes-128-gcm:${SS_KEY}'
print(base64.urlsafe_b64encode(raw.encode()).decode().rstrip('='))
")

SS_LINK="ss://${SS_B64}@${SERVER_IP}:${LISTEN_PORT}/?${PLUGIN_OPTS}#SS2022_v2ray_plugin"

if [ -n "$TG_TOKEN" ] && [ -n "$TG_CHAT_ID" ]; then
    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -d "chat_id=${TG_CHAT_ID}" \
        -d "parse_mode=HTML" \
        --data-urlencode "text=<code>${SS_LINK}</code>" >/dev/null
fi

echo ""
echo "══════════════════════════════════════════════"
echo "  部署完成（SS + v2ray-plugin 模式）"
echo "══════════════════════════════════════════════"
echo "  服务器 IP : ${SERVER_IP}"
echo "  监听端口   : ${LISTEN_PORT}"
echo "  加密算法   : 2022-blake3-aes-128-gcm"
echo "  SS 密码    : ${SS_KEY}"
echo "  Plugin     : v2ray-plugin (mode: websocket, path: /ss-ws)"
echo "══════════════════════════════════════════════"
echo "  一键链接:"
echo "  ${SS_LINK}"
echo "══════════════════════════════════════════════"
