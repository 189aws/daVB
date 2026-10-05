#!/usr/bin/env bash

# ===============================================================
# Sing-box Docker 版 VLESS-Reality 部署与 TG 推送脚本 (抗封锁强化版)
# ===============================================================

set -e

# ========== TG 配置区 ==========
TG_TOKEN="8896559295:AAHWVHQVJfoWG9v4McFg2qJgACw0nEpMxJo"
TG_CHAT_ID="1417748881"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

log() {
    echo -e "${GREEN}[INFO] $1${PLAIN}"
}

warn() {
    echo -e "${YELLOW}[WARN] $1${PLAIN}"
}

err() {
    echo -e "${RED}[ERROR] $1${PLAIN}"
}

if [[ $EUID -ne 0 ]]; then
   err "错误：请使用 root 权限运行此脚本！"
   exit 1
fi

echo -e "${GREEN}=== 开始部署 Sing-box Docker VLESS-Reality 服务 ===${PLAIN}"

# 0. 自动开启系统 BBR 拥塞控制
log "0. 检查并开启系统 BBR 拥塞控制..."
if ! sysctl net.ipv4.tcp_congestion_control | grep -q bbr; then
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p &>/dev/null || true
    log "BBR 拥塞控制已成功开启！"
else
    log "系统 BBR 拥塞控制已处于开启状态。"
fi

# 1. 检查并安装 Docker 环境（自动修复包名/源问题）
log "1. 检查并配置 Docker 环境..."

if ! command -v docker &>/dev/null; then
    log "检测到未安装 Docker，开始自动安装 Docker 官方源..."
    if command -v apt &>/dev/null; then
        apt update -y && apt install -y ca-certificates curl gnupg
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg || true
        chmod a+r /etc/apt/keyrings/docker.gpg || true
        
        # 写入 Docker 官方 APT 源
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
        
        apt update -y
        apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin jq openssl
    elif command -v yum &>/dev/null; then
        yum install -y curl jq openssl yum-utils
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi
else
    log "Docker 已安装，安装辅助工具 (jq, openssl)..."
    if command -v apt &>/dev/null; then
        apt update -y && apt install -y jq openssl curl
    elif command -v yum &>/dev/null; then
        yum install -y jq openssl curl
    fi
fi

systemctl enable docker --now &>/dev/null || true

# 2. 从优化后的精简池中并发筛选可用 SNI 域名
log "2. 正在并发测试并筛选高质量伪装 SNI 域名..."

TMP_POOL=$(mktemp)
# 精简为海外大厂且支持 TLS 1.3 / H2 的高稳定域名池
cat << 'EOF' > "$TMP_POOL"
www.apple.com
gateway.icloud.com
itunes.apple.com
swdist.apple.com
www.microsoft.com
azure.microsoft.com
EOF

check_domain() {
    local domain=$1
    # 强制要求支持 TLS 1.3 且 ALPN 协商包含 h2 或 http/1.1
    if timeout 3 bash -c "openssl s_client -connect '${domain}:443' -servername '${domain}' -tls1_3 -alpn h2,http/1.1 -brief 2>&1" | grep -iq "ACCEPT\|established"; then
        echo "$domain"
    fi
}
export -f check_domain

VALID_DOMAINS=()
while IFS= read -r domain; do
    [ -n "$domain" ] && VALID_DOMAINS+=("$domain")
done < <(xargs -P 10 -I {} bash -c 'check_domain "$@"' _ {} < "$TMP_POOL")

rm -f "$TMP_POOL"

if [ ${#VALID_DOMAINS[@]} -eq 0 ]; then
    warn "探测未匹配到响应成功的域名，回退默认伪装域名: www.apple.com"
    DEST_DOMAIN="www.apple.com"
else
    RANDOM_INDEX=$((RANDOM % ${#VALID_DOMAINS[@]}))
    DEST_DOMAIN="${VALID_DOMAINS[$RANDOM_INDEX]}"
    log "挑选伪装域名: ${CYAN}${DEST_DOMAIN}${PLAIN}"
fi

# 3. 提取容器生成 KeyPair 与 UUID
log "3. 生成 VLESS Reality 密钥对与参数..."

KEY_OUTPUT=$(docker run --rm ghcr.io/sagernet/sing-box:latest generate reality-keypair)
PRIVATE_KEY=$(echo "$KEY_OUTPUT" | awk '/PrivateKey:/ {print $2}')
PUBLIC_KEY=$(echo "$KEY_OUTPUT" | awk '/PublicKey:/ {print $2}')

UUID=$(docker run --rm ghcr.io/sagernet/sing-box:latest generate uuid)
SHORT_ID=$(openssl rand -hex 8)
PORT=443

# 4. 生成配置文件与启动 Docker 容器
log "4. 写入 Sing-box 配置文件..."

CONFIG_DIR="/etc/sing-box"
mkdir -p "${CONFIG_DIR}"

cat <<EOF > "${CONFIG_DIR}/config.json"
{
  "log": {
    "level": "warn",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": ${PORT},
      "users": [
        {
          "uuid": "${UUID}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${DEST_DOMAIN}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${DEST_DOMAIN}",
            "server_port": 443
          },
          "private_key": "${PRIVATE_KEY}",
          "short_id": [
            "${SHORT_ID}",
            ""
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ]
}
EOF

# 清理已有容器并重新启动
docker rm -f sing-box &>/dev/null || true

log "启动 Sing-box Docker 容器..."
docker run -d \
  --name sing-box \
  --restart=always \
  --network=host \
  -v "${CONFIG_DIR}/config.json:/etc/sing-box/config.json" \
  ghcr.io/sagernet/sing-box:latest \
  run -c /etc/sing-box/config.json

# 5. 构建节点信息
SERVER_IP=$(curl -s4 --connect-timeout 5 ifconfig.me || curl -s4 --connect-timeout 5 ip.sb || echo "127.0.0.1")
VLESS_LINK="vless://${UUID}@${SERVER_IP}:${PORT}?type=tcp&security=reality&encryption=none&pbk=${PUBLIC_KEY}&fp=chrome&sni=${DEST_DOMAIN}&sid=${SHORT_ID}&flow=xtls-rprx-vision#SingBox-Reality-${DEST_DOMAIN}"

# 6. 修复并推送节点链接到 Telegram
log "推送配置到 Telegram..."
if [ -n "$TG_TOKEN" ] && [ -n "$TG_CHAT_ID" ]; then
    TG_TEXT="<b>Sing-box VLESS-Reality 节点部署成功</b>

<b>服务器 IP:</b> <code>${SERVER_IP}</code>
<b>伪装域名:</b> <code>${DEST_DOMAIN}</code>

<b>节点链接:</b>
<code>${VLESS_LINK}</code>"

    RESPONSE=$(curl -s4 --connect-timeout 10 -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -d "chat_id=${TG_CHAT_ID}" \
        -d "parse_mode=HTML" \
        --data-urlencode "text=${TG_TEXT}")

    if echo "$RESPONSE" | grep -q '"ok":true'; then
        log "Telegram 推送成功！"
    else
        warn "Telegram 推送失败，返回接口结果如下："
        echo -e "${RED}${RESPONSE}${PLAIN}"
    fi
fi

# 7. 控制台结果展示
echo -e "\n${GREEN}====================================================${PLAIN}"
echo -e "${GREEN}    Sing-box Docker VLESS-Reality 部署完成！        ${PLAIN}"
echo -e "${GREEN}====================================================${PLAIN}"
echo -e "服务器 IP    : ${YELLOW}${SERVER_IP}${PLAIN}"
echo -e "监听端口     : ${YELLOW}${PORT}${PLAIN}"
echo -e "UUID         : ${YELLOW}${UUID}${PLAIN}"
echo -e "Public Key   : ${YELLOW}${PUBLIC_KEY}${PLAIN}"
echo -e "Short ID     : ${YELLOW}${SHORT_ID}${PLAIN}"
echo -e "SNI 伪装域名 : ${CYAN}${DEST_DOMAIN}${PLAIN}"
echo -e "----------------------------------------------------"
echo -e "客户端分享链接:"
echo -e "${GREEN}${VLESS_LINK}${PLAIN}"
echo -e "----------------------------------------------------"
echo -e "配置文件路径: ${CONFIG_DIR}/config.json"
echo -e "查看日志: ${YELLOW}docker logs -f sing-box${PLAIN}"
echo -e "${GREEN}====================================================${PLAIN}"
