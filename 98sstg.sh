cat << 'EOF' > /tmp/setup_ss2022.sh
#!/bin/bash
set -e

# ==========================================
# 1. 自定义配置区
# ==========================================
TG_TOKEN="8896559295:AAHuyFbUCYQedNRORneTN9sSu0Dc7lWyoFo"
TG_CHAT_ID="1417748881"

echo "[1/5] 正在安装基础依赖..."
apt-get update -y
apt-get install -y curl jq openssl tar

echo "[2/5] 正在获取并安装最新的 sing-box 核心..."
LATEST_VERSION=$(curl -s https://api.github.com/repos/sagernet/sing-box/releases/latest | jq -r .tag_name | sed 's/^v//')
ARCH=$(dpkg --print-architecture)
if [ "$ARCH" = "amd64" ]; then
    SB_ARCH="amd64"
elif [ "$ARCH" = "arm64" ]; then
    SB_ARCH="arm64"
else
    SB_ARCH="amd64"
fi

DOWNLOAD_URL="https://github.com/sagernet/sing-box/releases/download/v${LATEST_VERSION}/sing-box-${LATEST_VERSION}-linux-${SB_ARCH}.tar.gz"

curl -sSL "$DOWNLOAD_URL" -o /tmp/sing-box.tar.gz
tar -zxvf /tmp/sing-box.tar.gz -C /tmp/
mv /tmp/sing-box-${LATEST_VERSION}-linux-${SB_ARCH}/sing-box /usr/local/bin/
chmod +x /usr/local/bin/sing-box
rm -rf /tmp/sing-box*

echo "[3/5] 正在生成 SS-2022 节点配置..."
PORT=$(shuf -i 20000-60000 -n 1)
KEY=$(openssl rand -base64 32)

mkdir -p /etc/sing-box
cat <<JSON > /etc/sing-box/config.json
{
  "log": {
    "level": "info"
  },
  "inbounds": [
    {
      "type": "shadowsocks",
      "tag": "ss-in",
      "listen": "::",
      "listen_port": $PORT,
      "method": "2022-blake3-aes-128-gcm",
      "password": "$KEY"
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
JSON

echo "[4/5] 写入 systemd 系统服务并启动..."
cat <<SYSTEMD > /etc/systemd/system/sing-box.service
[Unit]
Description=sing-box service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=on-failure
RestartSec=10s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
SYSTEMD

systemctl daemon-reload
systemctl enable --now sing-box

# 获取公网 IP
SERVER_IP=$(curl -s https://api.ipify.org || curl -s https://ipv4.icanhazip.com)

# 生成标准 ss:// 链接
RAW_CREDENTIALS="2022-blake3-aes-128-gcm:$KEY"
ENCODED_CREDENTIALS=$(echo -n "$RAW_CREDENTIALS" | base64 | tr -d '\n')
SS_LINK="ss://${ENCODED_CREDENTIALS}@${SERVER_IP}:${PORT}#Debian12_SS2022"

echo "[5/5] 正在推送纯链接到 Telegram..."
curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
    -d "chat_id=${TG_CHAT_ID}" \
    --data-urlencode "text=${SS_LINK}" >/dev/null

clear
echo "=================================================="
echo "      Shadowsocks-2022 部署完成！"
echo "=================================================="
echo "服务器 IP  : $SERVER_IP"
echo "服务端口   : $PORT"
echo "加密方式   : 2022-blake3-aes-128-gcm"
echo "密  码     : $KEY"
echo "--------------------------------------------------"
echo "导入节点链接 (已同步推送到 Telegram):"
echo "$SS_LINK"
echo "=================================================="
EOF

bash /tmp/setup_ss2022.sh