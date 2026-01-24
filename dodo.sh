#!/bin/bash

# ==========================================
# 1. 自定义配置区
# ==========================================
SS_PORT=6666
SS_PASSWORD="AAAACchacha20chacha209AAAAA"
SS_METHOD="chacha20-ietf-poly1305"
DOH_URL="https://223.5.5.5/dns-query"

# ==========================================
# 2. 基础环境安装 (修复 Debian 兼容性)
# ==========================================
echo "正在检测/安装 Docker 环境..."
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg lsb-release

# 卸载旧版本并安装最新引擎
sudo apt-get install -y docker.io docker-compose

# 确保 Docker 服务启动
sudo systemctl enable --now docker

# 开启内核转发
echo "开启内核 IPv4 转发..."
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf

# ==========================================
# 3. 部署目录与配置
# ==========================================
mkdir -p ~/singbox_isolated
cd ~/singbox_isolated

echo "生成 sing-box 配置..."
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
# 注意：Debian 下 docker-compose (v1) 和 docker compose (v2) 兼容性处理
cat <<EOT > docker-compose.yml
version: '3'
services:
  sing-box:
    image: ghcr.io/sagernet/sing-box:latest
    container_name: sing-box-isolated
    restart: always
    ports:
      - "$SS_PORT:$SS_PORT/tcp"
      - "$SS_PORT:$SS_PORT/udp"
    volumes:
      - ./config.json:/etc/sing-box/config.json
    command: -D /var/lib/sing-box -c /etc/sing-box/config.json run
EOT

# ==========================================
# 4. 启动服务
# ==========================================
echo "正在重启容器服务..."
# 尝试使用 v2 语法，如果不行则回退 v1
if docker compose version >/dev/null 2>&1; then
    docker compose down 2>/dev/null
    docker compose up -d
else
    docker-compose down 2>/dev/null
    docker-compose up -d
fi

# 自动获取公网IP
IP=$(curl -s ifconfig.me)

echo "------------------------------------------------"
echo "✅ 部署成功！"
echo "服务器地址: $IP"
echo "连接端口: $SS_PORT"
echo "加密方式: $SS_METHOD"
echo "连接密码: $SS_PASSWORD"
echo "------------------------------------------------"
