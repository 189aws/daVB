#!/bin/bash
set -e

# ==========================================
# 1. 自定义配置区
# ==========================================
TG_TOKEN="8896559295:AAHuyFbUCYQedNRORneTN9sSu0Dc7lWyoFo"
TG_CHAT_ID="1417748881"

LISTEN_PORT=443
DEST_TARGET="www.apple.com:443"
SERVER_NAME="www.apple.com"

WORK_DIR=~/vless_reality
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# 基础环境与 Docker 检查安装
if ! command -v docker &>/dev/null; then
    echo ">>> 安装 Docker..."
    sudo apt-get update -y
    sudo apt-get install -y ca-certificates curl jq openssl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/debian/gpg \
        -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
      https://download.docker.com/linux/debian \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update -y
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    sudo systemctl enable --now docker
fi

# 自动生成 UUID 和 REALITY 密钥对
echo ">>> 生成身份密钥与凭证..."
UUID=$(cat /proc/sys/kernel/random/uuid)

# 下载/运行 sing-box 生成密钥对
docker run --rm ghcr.io/sagernet/sing-box:latest generate reality-keypair > keypair.txt
PRIVATE_KEY=$(grep "PrivateKey" keypair.txt | awk '{print $2}')
PUBLIC_KEY=$(grep "PublicKey" keypair.txt | awk '{print $2}')

# 生成 8 位十六进制 Short ID
SHORT_ID=$(openssl rand -hex 4)

# ==========================================
# 2. 生成 sing-box 配置文件
# ==========================================
echo ">>> 生成 sing-box 配置..."
cat > config.json <<EOT
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": ${LISTEN_PORT},
      "users": [
        {
          "uuid": "${UUID}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${SERVER_NAME}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${SERVER_NAME}",
            "server_port": 443
          },
          "private_key": "${PRIVATE_KEY}",
          "short_id": [
            "${SHORT_ID}"
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "final": "direct",
    "auto_detect_interface": true
  }
}
EOT

# ==========================================
# 3. 生成 docker-compose.yml 并启动
# ==========================================
cat > docker-compose.yml <<EOT
services:
  sing-box:
    image: ghcr.io/sagernet/sing-box:latest
    container_name: vless-reality
    restart: always
    network_mode: host
    volumes:
      - ./config.json:/etc/sing-box/config.json
    command: -D /var/lib/sing-box -c /etc/sing-box/config.json run
EOT

echo ">>> 启动 VLESS + REALITY 服务..."
sudo docker compose down 2>/dev/null || true
sudo docker compose up -d

sleep 3

# ==========================================
# 4. 获取公网 IP 与服务器信息
# ==========================================
SERVER_IP=""
for API in "https://api.ipify.org" "https://ifconfig.me" "https://ipv4.icanhazip.com"; do
    SERVER_IP=$(curl -s -4 --max-time 5 "$API" 2>/dev/null)
    if [[ "$SERVER_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        break
    fi
    SERVER_IP=""
done

if [ -z "$SERVER_IP" ]; then
    SERVER_IP=$(curl -s --max-time 5 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null)
fi
[ -z "$SERVER_IP" ] && SERVER_IP="YOUR_SERVER_IP"

REGION=$(curl -s --max-time 3 http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo "unknown")
INSTANCE_ID=$(curl -s --max-time 3 http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "unknown")
INSTANCE_TYPE=$(curl -s --max-time 3 http://169.254.169.254/latest/meta-data/instance-type 2>/dev/null || echo "unknown")
DEPLOY_TIME=$(date '+%Y-%m-%d %H:%M:%S %Z')

# ==========================================
# 5. 构造节点链接 & Clash 配置
# ==========================================
NODE_NAME="AWS-VLESS-REALITY-${SERVER_IP}"
ENCODED_NAME=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${NODE_NAME}', safe=''))")

VLESS_LINK="vless://${UUID}@${SERVER_IP}:${LISTEN_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SERVER_NAME}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp#${ENCODED_NAME}"

CLASH_CFG="- name: ${NODE_NAME}
  type: vless
  server: ${SERVER_IP}
  port: ${LISTEN_PORT}
  uuid: ${UUID}
  network: tcp
  tls: true
  udp: true
  flow: xtls-rprx-vision
  servername: ${SERVER_NAME}
  reality-opts:
    public-key: ${PUBLIC_KEY}
    short-id: ${SHORT_ID}
  client-fingerprint: chrome"

# ==========================================
# 6. 本地输出汇总
# ==========================================
echo ""
echo "======================================================="
echo "🎉 VLESS + REALITY 部署成功！"
echo "======================================================="
echo "  服务器 IP : ${SERVER_IP}"
echo "  端口      : ${LISTEN_PORT}"
echo "  UUID      : ${UUID}"
echo "  Public Key: ${PUBLIC_KEY}"
echo "  Short ID  : ${SHORT_ID}"
echo "  SNI       : ${SERVER_NAME}"
echo ""
echo "  🔗 节点链接:"
echo "  ${VLESS_LINK}"
echo ""
echo "  📋 Clash 配置片段:"
echo "${CLASH_CFG}"
echo "======================================================="
echo "  ⚠️ 请确认 AWS 安全组已放行 TCP ${LISTEN_PORT}"
echo "======================================================="
echo ""

# ==========================================
# 7. 发送 Telegram 通知
# ==========================================
MSG="🚀 *VLESS + REALITY 节点部署成功*

━━━━━━━━━━━━━━━━━━━━
📍 *服务器信息*
\`\`\`
公网IP     : ${SERVER_IP}
区域       : ${REGION}
实例ID     : ${INSTANCE_ID}
实例类型   : ${INSTANCE_TYPE}
部署时间   : ${DEPLOY_TIME}
\`\`\`

━━━━━━━━━━━━━━━━━━━━
⚙️ *节点配置*
\`\`\`
地址       : ${SERVER_IP}
端口       : ${LISTEN_PORT}
UUID       : ${UUID}
SNI        : ${SERVER_NAME}
Public Key : ${PUBLIC_KEY}
Short ID   : ${SHORT_ID}
传输流控   : xtls-rprx-vision
客户端指纹 : chrome
\`\`\`

━━━━━━━━━━━━━━━━━━━━
🔗 *VLESS 节点链接*
\`\`\`
${VLESS_LINK}
\`\`\`

━━━━━━━━━━━━━━━━━━━━
📋 *Clash Meta 配置片段*
\`\`\`yaml
${CLASH_CFG}
\`\`\`

━━━━━━━━━━━━━━━━━━━━
⚠️ 请确认 AWS 安全组已放行 TCP \`${LISTEN_PORT}\`
🐳 查看日志: \`docker logs vless-reality\`"

echo ">>> 推送节点信息到 Telegram..."

HTTP_CODE=$(curl -s -o /tmp/tg_resp.json -w "%{http_code}" \
  -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
  -H "Content-Type: application/json" \
  -d "{
    \"chat_id\": \"${TG_CHAT_ID}\",
    \"text\": $(python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' <<< "$MSG"),
    \"parse_mode\": \"Markdown\",
    \"disable_web_page_preview\": true
  }")

if [ "$HTTP_CODE" = "200" ] && grep -q '"ok":true' /tmp/tg_resp.json; then
  echo "✅ Telegram 推送成功！"
else
  echo "⚠️ Markdown 推送失败，尝试纯文本降级推送..."
  PLAIN_MSG="VLESS + REALITY 节点部署完成
公网IP: ${SERVER_IP}  端口: ${LISTEN_PORT}
UUID: ${UUID}  SNI: ${SERVER_NAME}
Public Key: ${PUBLIC_KEY}
Short ID: ${SHORT_ID}
区域: ${REGION}  时间: ${DEPLOY_TIME}

节点链接:
${VLESS_LINK}

Clash配置:
${CLASH_CFG}

请在AWS安全组放行TCP ${LISTEN_PORT}"

  curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TG_CHAT_ID}" \
    --data-urlencode "text=${PLAIN_MSG}" \
    --data-urlencode "disable_web_page_preview=true" > /dev/null
  echo "✅ 纯文本降级推送完成！"
fi
