#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "请使用 root 权限运行此脚本 (sudo bash 1.sh)"
  exit 1
fi

read -p "请输入你的域名 (例如 example.com): " DOMAIN
if [ -z "$DOMAIN" ]; then
  echo "域名不能为空！"
  exit 1
fi

UUID=$(cat /proc/sys/kernel/random/uuid)
SERVICE_PATH="grpc$(tr -dc "a-z0-9" < /dev/urandom | head -c 6)"

echo "正在清理可能存在的旧服务与配置..."
systemctl stop caddy sing-box 2>/dev/null || true

echo "正在更新系统并安装基础依赖..."
apt update && apt install -y debian-keyring debian-archive-keyring apt-transport-https curl jq

echo "正在安装 Caddy Web 服务器..."
curl -1sLf "https://dl.cloudsmith.io/public/caddy/stable/gpg.key" | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf "https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt" | tee /etc/apt/sources.list.d/caddy-stable.list
apt update && apt install -y caddy

echo "正在安装 sing-box..."
SB_VERSION="1.11.4"
curl -fsSL "https://github.com/SagerNet/sing-box/releases/download/v${SB_VERSION}/sing-box_${SB_VERSION}_linux_amd64.deb" -o sing-box.deb
dpkg -i sing-box.deb
rm -f sing-box.deb

echo "正在生成 sing-box 配置文件..."
mkdir -p /etc/sing-box
cat << CONFIG > /etc/sing-box/config.json
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-grpc-in",
      "listen": "127.0.0.1",
      "listen_port": 10000,
      "users": [
        {
          "uuid": "$UUID",
          "flow": ""
        }
      ],
      "transport": {
        "type": "grpc",
        "service_name": "$SERVICE_PATH"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
CONFIG

systemctl enable --now sing-box

echo "正在配置 Caddy 伪装前端..."
mkdir -p /var/www/html
echo "<!DOCTYPE html><html><head><title>Welcome</title></head><body><h1>System Maintenance in Progress</h1><p>Please check back later.</p></body></html>" > /var/www/html/index.html

cat << CADDYCONF > /etc/caddy/Caddyfile
$DOMAIN {
    root * /var/www/html
    file_server

    reverse_proxy /$SERVICE_PATH/* h2c://127.0.0.1:10000 {
        transport http {
            versions h2c
        }
    }
}
CADDYCONF

systemctl restart caddy

SHADOWROCKET_LINK="vless://${UUID}@${DOMAIN}:443?encryption=none&security=tls&type=grpc&serviceName=${SERVICE_PATH}&sni=${DOMAIN}#AWS-gRPC-Node"

echo "=================================================="
echo "          部署成功！请复制下方小火箭导入链接：          "
echo "=================================================="
echo "$SHADOWROCKET_LINK"
echo "=================================================="
EOF
'