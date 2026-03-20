#!/bin/bash
set -e

# ==========================================
# 1. 自定义配置区
# ==========================================
TG_TOKEN="7756669471:AAFstxnzCweHItNptwOf7UU-p6xj3pwnAI8"
TG_CHAT_ID="1792396794"

TROJAN_PORT=55443
TROJAN_PASSWORD="GFD650G49DSF0G980gfdgfd"
SNI_DOMAIN="360.cn"
DOH_URL="https://223.5.5.5/dns-query"
SINGBOX_IMAGE="ghcr.io/sagernet/sing-box:v1.10.7"

# ==========================================
# 2. 系统深度优化 (解决 UDP 丢包与并发限制)
# ==========================================
echo ">>> 正在执行系统级 UDP 与并发优化..."

# 优化内核网络栈
sudo tee /etc/sysctl.d/99-singbox.conf <<EOF
net.ipv4.ip_forward=1
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.core.netdev_max_backlog=5000
net.ipv4.udp_rmem_min=8192
net.ipv4.udp_wmem_min=8192
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
EOF
sudo sysctl -p /etc/sysctl.d/99-singbox.conf

# 提升进程文件描述符上限
if ! grep -q "soft nofile 1048576" /etc/security/limits.conf; then
    sudo tee -a /etc/security/limits.conf <<EOF
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
EOF
fi

# ==========================================
# 3. 基础环境安装 (Docker 逻辑)
# ==========================================
echo ">>> 检查并安装 Docker 环境..."
sudo apt-get update -y && sudo apt-get install -y ca-certificates curl jq openssl

if ! command -v docker &>/dev/null; then
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update -y && sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
fi
sudo systemctl enable --now docker

# ==========================================
# 4. 准备工作目录与证书
# ==========================================
WORK_DIR=~/trojan_isolated
mkdir -p "$WORK_DIR/cert"
cd "$WORK_DIR"

if [ ! -f ./cert/server.crt ]; then
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout ./cert/server.key -out ./cert/server.crt -subj "/CN=$SNI_DOMAIN"
fi

# ==========================================
# 5. 生成 Sing-box 配置 (核心 UDP 优化)
# ==========================================
cat > config.json <<EOT
{
  "log": { "level": "info", "timestamp": true },
  "dns": {
    "servers": [{ "tag": "dns-remote", "address": "${DOH_URL}", "detour": "direct" }],
    "strategy": "prefer_ipv4"
  },
  "inbounds": [
    {
      "type": "trojan",
      "tag": "trojan-in",
      "listen": "::",
      "listen_port": ${TROJAN_PORT},
      "users": [{ "name": "user1", "password": "${TROJAN_PASSWORD}" }],
      "multiplex": { "enabled": true, "padding": true },
      "udp_timeout": 300,
      "tls": {
        "enabled": true,
        "server_name": "${SNI_DOMAIN}",
        "certificate_path": "/etc/sing-box/cert/server.crt",
        "key_path": "/etc/sing-box/cert/server.key"
      }
    }
  ],
  "outbounds": [
    { "type": "direct", "tag": "direct", "udp_fragment": true }
  ]
}
EOT

# ==========================================
# 6. Docker Compose 部署
# ==========================================
cat > docker-compose.yml <<EOT
services:
  sing-box:
    image: ${SINGBOX_IMAGE}
    container_name: trojan-isolated
    restart: always
    network_mode: host
    privileged: true
    volumes:
      - ./config.json:/etc/sing-box/config.json
      - ./cert:/etc/sing-box/cert
    command: -D /var/lib/sing-box -c /etc/sing-box/config.json run
EOT

sudo docker compose down 2>/dev/null || true
sudo docker compose up -d

# ==========================================
# 7. IP 获取与 TG 推送 (逻辑保持不变)
# ==========================================
IP=\$(curl -4 -s --max-time 5 https://api4.ipify.org || echo "YOUR_SERVER_IP")
RAW_LINK="trojan://${TROJAN_PASSWORD}@\${IP}:${TROJAN_PORT}?sni=${SNI_DOMAIN}&allowInsecure=1#SingBox_UDP_Plus_\${IP}"

curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TG_CHAT_ID}" \
    --data-urlencode "text=\${RAW_LINK}"

echo "======================================================="
echo "✅ Docker 部署完成且 UDP 已增强！"
echo "链接: \$RAW_LINK"
echo "======================================================="
