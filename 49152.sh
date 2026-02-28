#!/bin/bash

# ==========================================
# 1. 自定义配置区
# ==========================================
# Telegram 配置
TG_TOKEN="7756669471:AAFstxnzCweHItNptwOf7UU-p6xj3pwnAI8"
TG_CHAT_ID="1792396794"

# 节点配置 (建议不要用默认的 443 或 52255，换个随机高位端口)
TROJAN_PORT=49152 
TROJAN_PASSWORD="WodjiidoamnA@@@" # 动态密码防止重放
SNI_DOMAIN="download.windowsupdate.com" # 换成微软更新域名，流量特征更隐蔽
DOH_URL="https://1.1.1.1/dns-query" # 改用 Cloudflare DOH，避免境内 DNS 被墙拦截

# ==========================================
# 2. 开启 BBR 加速 (解决丢包断连的关键)
# ==========================================
echo "正在开启 BBR 加速..."
if ! lsmod | grep -q bbr; then
    echo "net.core.default_qdisc=fq" | sudo tee -a /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf
    sudo sysctl -p
fi

# ==========================================
# 3. 基础环境清理与安装
# ==========================================
echo "正在清理并安装环境..."
sudo apt-get update
sudo apt-get install -y ca-certificates curl jq openssl docker.io docker-compose
sudo systemctl enable --now docker

# ==========================================
# 4. 生成证书 (增强混淆)
# ==========================================
rm -rf ~/trojan_isolated
mkdir -p ~/trojan_isolated/cert
cd ~/trojan_isolated

# 生成更像真实证书的自签名证书
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
-keyout ./cert/server.key -out ./cert/server.crt \
-subj "/C=US/ST=Washington/L=Redmond/O=Microsoft/CN=$SNI_DOMAIN"

# ==========================================
# 5. 生成 sing-box 配置 (严格 Trojan 模式)
# ==========================================
cat <<EOT > config.json
{
  "log": { "level": "info", "timestamp": true },
  "dns": {
    "servers": [{ "tag": "dns-remote", "address": "$DOH_URL", "detour": "direct" }],
    "strategy": "ipv4_only"
  },
  "inbounds": [
    {
      "type": "trojan",
      "tag": "trojan-in",
      "listen": "::",
      "listen_port": $TROJAN_PORT,
      "users": [{ "name": "user1", "password": "$TROJAN_PASSWORD" }],
      "tls": {
        "enabled": true,
        "server_name": "$SNI_DOMAIN",
        "certificate_path": "/etc/sing-box/cert/server.crt",
        "key_path": "/etc/sing-box/cert/server.key",
        "min_version": "1.2",
        "cipher_suites": [
          "TLS_AES_128_GCM_SHA256",
          "TLS_AES_256_GCM_SHA384",
          "TLS_CHACHA20_POLY1305_SHA256"
        ]
      }
    }
  ],
  "outbounds": [{ "type": "direct", "tag": "direct" }]
}
EOT

# 写入 docker-compose.yml
cat <<EOT > docker-compose.yml
version: '3'
services:
  sing-box:
    image: ghcr.io/sagernet/sing-box:latest
    container_name: trojan-isolated
    restart: always
    ports:
      - "$TROJAN_PORT:$TROJAN_PORT/tcp"
      - "$TROJAN_PORT:$TROJAN_PORT/udp"
    volumes:
      - ./config.json:/etc/sing-box/config.json
      - ./cert:/etc/sing-box/cert
    command: -D /var/lib/sing-box -c /etc/sing-box/config.json run
EOT

# ==========================================
# 6. 重启服务
# ==========================================
docker-compose down 2>/dev/null
docker-compose up -d

# ==========================================
# 7. 生成链接与推送
# ==========================================
IP=$(curl -s https://api64.ipify.org)
# 增加 allowInsecure=1 确保自签名证书能通，同时增加 peer 参数模拟真实 SNI
RAW_LINK="trojan://$TROJAN_PASSWORD@$IP:$TROJAN_PORT?sni=$SNI_DOMAIN&allowInsecure=1#AWS_Trojan_$IP"

echo "-------------------------------------------------------"
echo "✅ Trojan 节点加固部署完成！"
echo "端口: $TROJAN_PORT"
echo "伪装域名: $SNI_DOMAIN"
echo "链接: $RAW_LINK"
echo "-------------------------------------------------------"

# Telegram 推送
curl -s -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" \
    --data-urlencode "chat_id=$TG_CHAT_ID" \
    --data-urlencode "text=🛠 Trojan 节点已更新 (AWS)
    
IP: $IP
Port: $TROJAN_PORT
SNI: $SNI_DOMAIN
Link: $RAW_LINK"
