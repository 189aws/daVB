#!/bin/bash
set -e

# ========== 配置区 ==========
TG_TOKEN="8896559295:AAHWVHQVJfoWG9v4McFg2qJgACw0nEpMxJo"
TG_CHAT_ID="1417748881"

LISTEN_PORT=$(shuf -i 30000-50000 -n 1)        # 外部 REALITY 监听端口
SS_PORT=38421                                 # 本地 SS 端口
SS_KEY=$(openssl rand -base64 16)             # SS 2022 密钥
SNI_DOMAIN="gateway.icloud.com"              # 伪装 SNI 域名

# ============================

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
log() { echo -e "${GREEN}[✓]${NC} $1"; }

log "安装基础工具与 sing-box..."
apt-get update -qq && apt-get install -y -qq openssl curl jq python3 >/dev/null 2>&1

# 生成 REALITY 密钥对与 Short ID
KEYS=$(docker run --rm ghcr.io/sagernet/sing-box:latest generate reality-keypair 2>/dev/null || curl -s https://sing-box.app/generate-keys)
PRIVATE_KEY=$(echo "$KEYS" | grep -i "PrivateKey" | awk '{print $2}')
PUBLIC_KEY=$(echo "$KEYS" | grep -i "PublicKey" | awk '{print $2}')
SHORT_ID=$(openssl rand -hex 8)

log "清理旧容器..."
docker rm -f sing-box-ss-reality 2>/dev/null || true

log "创建 sing-box 配置文件..."
mkdir -p /etc/sing-box

cat <<EOF > /etc/sing-box/config.json
{
  "log": {
    "level": "warn"
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": ${LISTEN_PORT},
      "users": [
        {
          "uuid": "00000000-0000-0000-0000-000000000000",
          "flow": ""
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${SNI_DOMAIN}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${SNI_DOMAIN}",
            "port": 443
          },
          "private_key": "${PRIVATE_KEY}",
          "short_id": ["${SHORT_ID}"]
        }
      }
    },
    {
      "type": "shadowsocks",
      "tag": "ss-in",
      "listen": "127.0.0.1",
      "listen_port": ${SS_PORT},
      "method": "2022-blake3-aes-128-gcm",
      "password": "${SS_KEY}"
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF

log "启动 sing-box 容器..."
docker run -d \
  --name sing-box-ss-reality \
  --restart always \
  --network host \
  -v /etc/sing-box/config.json:/etc/sing-box/config.json \
  ghcr.io/sagernet/sing-box:latest \
  run -c /etc/sing-box/config.json

sleep 2

SERVER_IP=$(curl -s --max-time 10 ipv4.icanhazip.com || curl -s --max-time 10 api.ipify.org)

# 生成 SS 链接（如果客户端支持节点配置中嵌入 TLS/REALITY 传输）
SS_B64=$(python3 -c "import base64; print(base64.urlsafe_b64encode('2022-blake3-aes-128-gcm:${SS_KEY}'.encode()).decode().rstrip('='))")
SS_LINK="ss://${SS_B64}@${SERVER_IP}:${SS_PORT}#SS_Local"

echo ""
echo "══════════════════════════════════════════════"
echo "  sing-box (SS + REALITY) 部署完成！"
echo "══════════════════════════════════════════════"
echo "  服务器 IP    : ${SERVER_IP}"
echo "  外层 REALITY 端口: ${LISTEN_PORT}"
echo "  Public Key   : ${PUBLIC_KEY}"
echo "  Short ID     : ${SHORT_ID}"
echo "  SNI 伪装域名 : ${SNI_DOMAIN}"
echo "══════════════════════════════════════════════"
