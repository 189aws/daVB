#!/bin/bash

# ==========================================
# 1. 自定义配置区 (在这里修改所有参数)
# ==========================================
SS_PORT=6666
SS_PASSWORD="AAAACchacha20chacha209AAAAA"
SS_METHOD="chacha20-ietf-poly1305"

# DNS 设置 (DoH 地址)
# 默认使用 Google 和 Cloudflare 的 DoH
DOH_URL="https://8.8.8.8/dns-query"
# 你也可以换成：https://1.1.1.1/dns-query 或 https://dns.puredns.org/dns-query

# ==========================================
# 2. 基础环境安装
# ==========================================
echo "正在检测/安装 Docker 环境..."
sudo apt-get update && sudo apt-get install -y curl docker.io docker-compose-plugin
sudo systemctl enable --now docker

# 开启内核转发 (隔离模式必须开启)
echo "开启内核 IPv4 转发..."
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf

# ==========================================
# 3. 部署目录与配置
# ==========================================
mkdir -p ~/singbox_isolated
cd ~/singbox_isolated

echo "生成 DoH 加密版配置 (端口: $SS_PORT)..."
# 写入 config.json
cat <<EOT > config.json
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "tag": "dns-remote",
        "address": "$DOH_URL",
        "detour": "direct"
      },
      {
        "tag": "dns-direct",
        "address": "8.8.8.8",
        "detour": "direct"
      }
    ],
    "rules": [
      {
        "outbound": "any",
        "server": "dns-remote"
      }
    ],
    "strategy": "ipv4_only"
  },
  "inbounds": [
    {
      "type": "shadowsocks",
      "tag": "ss-in",
      "listen": "::",
      "listen_port": $SS_PORT,
      "method": "$SS_METHOD",
      "password": "$SS_PASSWORD"
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOT

# 写入 docker-compose.yml
cat <<EOT > docker-compose.yml
services:
  sing-box:
    image: ghcr.io/sagernet/sing-box:latest
    container_name: sing-box-isolated
    restart: always
    ports:
      - "$SS_PORT:$SS_PORT/tcp"
      - "$SS_PORT:$SS_PORT/udp"
    # 容器系统层 DNS 保持 8.8.8.8 仅用于启动时解析 DoH 域名（如果有域名的话）
    dns:
      - 8.8.8.8
    volumes:
      - ./config.json:/etc/sing-box/config.json
    command: -D /var/lib/sing-box -c /etc/sing-box/config.json run
EOT

# ==========================================
# 4. 启动服务
# ==========================================
echo "正在重启容器服务..."
docker compose down 2>/dev/null
docker compose up -d

# 自动获取公网IP
IP=$(curl -s ifconfig.me)

echo "------------------------------------------------"
echo "✅ DoH 加密隔离环境部署成功！"
echo "服务器地址: $IP"
echo "连接端口: $SS_PORT"
echo "加密方式: $SS_METHOD"
echo "连接密码: $SS_PASSWORD"
echo "DoH服务器: $DOH_URL"
echo "------------------------------------------------"
echo "提示: 现在的 DNS 解析将全部通过 HTTPS 加密隧道，53 端口不再产生流量。"
EOF
