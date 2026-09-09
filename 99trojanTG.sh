#!/bin/bash

# =========================================================
# Trojan 节点自动搭建脚本 (Debian 12 - 随机子域名 + 远程 DNS + TG 推送)
# 用法: bash 99trojan.sh <主域名>
# 示例: bash 99trojan.sh mx2-qq-com.baby
# =========================================================

set -e

# 清理 Windows CRLF 换行符隐患
sed -i 's/\r$//' "$0" 2>/dev/null || true

# 1. 检查传入的主域名参数
MAIN_DOMAIN="$1"

if [ -z "$MAIN_DOMAIN" ]; then
    echo "=================================================="
    echo "❌ 错误: 未传入主域名参数！"
    echo "💡 正确用法: bash 99trojan.sh mx2-qq-com.baby"
    echo "=================================================="
    exit 1
fi

# 自动生成 8 位随机前缀 (NAME)
RANDOM_PREFIX=$(tr -dc 'a-z0-9' < /dev/urandom | head -c 8)
FULL_DOMAIN="${RANDOM_PREFIX}.${MAIN_DOMAIN}"

echo "=================================================="
echo "🎯 主域名 (DOMAIN): ${MAIN_DOMAIN}"
echo "🎲 自动生成随机主机名 (NAME): ${RANDOM_PREFIX}"
echo "🚀 节点完整域名: ${FULL_DOMAIN}"
echo "=================================================="

# 2. 安装基础依赖组件 (包含 sshpass)
echo "📦 [1/6] 正在更新系统并安装必要组件..."
apt update -y
apt install -y curl wget jq unzip socat cron net-tools dnsutils sshpass

# 获取本机真实公网 IP
SERVER_IP=$(curl -s4 https://api.ipify.org || curl -s4 https://ifconfig.me)
echo "🌐 本机公网 IP: ${SERVER_IP}"

# 3. 远程连接 DNS 机器自动写入 A 记录并重启 Bind9
DNS_SERVER_IP="47.83.150.97"
DNS_SERVER_PORT="22"
DNS_SERVER_PASS="Bk7xY2cR5tV9bN!"

echo "🌐 [2/6] 正在连接远程 Bind9 服务器 (${DNS_SERVER_IP}) 写入 A 记录..."

# 构造在远程 DNS 机器上执行的命令
REMOTE_CMD="echo '${RANDOM_PREFIX} IN A ${SERVER_IP}' >> '/etc/bind/zones/${MAIN_DOMAIN}.zone' && systemctl restart bind9"

# 使用 sshpass 远程执行
if sshpass -p "${DNS_SERVER_PASS}" ssh -p ${DNS_SERVER_PORT} -o StrictHostKeyChecking=no root@${DNS_SERVER_IP} "${REMOTE_CMD}"; then
    echo "✅ 远程 DNS 记录 [ ${RANDOM_PREFIX} IN A ${SERVER_IP} ] 添加成功并已重启 Bind9！"
else
    echo "⚠️ 远程 DNS 写入失败，请检查远程 IP/密码 是否有效。"
fi

# 4. 安装 acme.sh 并申请 TLS 证书
echo "🔒 [3/6] 正在申请 Let's Encrypt TLS 证书..."
mkdir -p /etc/trojan-cert

curl https://get.acme.sh | sh -s email="admin@${MAIN_DOMAIN}"
~/.acme.sh/acme.sh --upgrade --auto-upgrade >/dev/null 2>&1 || true
~/.acme.sh/acme.sh --set-default-ca --server letsencrypt

# 释放 80 端口
systemctl stop nginx 2>/dev/null || true

# 申请证书
~/.acme.sh/acme.sh --issue -d "${FULL_DOMAIN}" --standalone --listen-v4

# 安装证书到指定路径
~/.acme.sh/acme.sh --install-cert -d "${FULL_DOMAIN}" \
    --key-file       /etc/trojan-cert/privkey.pem  \
    --fullchain-file /etc/trojan-cert/fullchain.pem \
    --reloadcmd     "systemctl restart xray 2>/dev/null || true"

# 赋予证书文件权限，确保 nobody 用户可读
chmod -R 755 /etc/trojan-cert
chmod 644 /etc/trojan-cert/fullchain.pem
chmod 644 /etc/trojan-cert/privkey.pem

# 5. 安装 Xray 官方核心
echo "⚙️ [4/6] 正在安装 Xray 官方核心..."
bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh) install

# 6. 配置并启动 Trojan 节点
echo "📝 [5/5] 正在配置 Xray Trojan 服务..."
PASSWORD=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 16)
PORT=443

mkdir -p /usr/local/etc/xray
cat << XRAYCONFIG > /usr/local/etc/xray/config.json
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": ${PORT},
      "protocol": "trojan",
      "settings": {
        "clients": [
          {
            "password": "${PASSWORD}"
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "alpn": [
            "h2",
            "http/1.1"
          ],
          "certificates": [
            {
              "certificateFile": "/etc/trojan-cert/fullchain.pem",
              "keyFile": "/etc/trojan-cert/privkey.pem"
            }
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
XRAYCONFIG

# 确保证书权限无误并重启服务
chmod -R 755 /etc/trojan-cert
chmod 644 /etc/trojan-cert/*

systemctl daemon-reload
systemctl enable xray
systemctl restart xray

sleep 2
if systemctl is-active --quiet xray; then
    STATUS="✅ 运行中"
else
    STATUS="❌ 启动失败"
fi

TROJAN_LINK="trojan://${PASSWORD}@${FULL_DOMAIN}:${PORT}?peer=${FULL_DOMAIN}#Trojan-${FULL_DOMAIN}"

# 7. 推送纯链接到 Telegram Bot
TG_TOKEN="8896559295:AAHUtZw-Q2luP3oki7UQYRmekFfVlA-o5I8"
TG_CHAT_ID="1417748881"

echo "📱 [6/6] 正在推送纯链接到 Telegram..."
curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
    -d "chat_id=${TG_CHAT_ID}" \
    --data-urlencode "text=${TROJAN_LINK}" >/dev/null

echo ""
echo "════════════════════════════════════════════════════════════"
echo "🎉 Trojan 节点一键搭建完成！"
echo "════════════════════════════════════════════════════════════"
echo "节点域名: ${FULL_DOMAIN}"
echo "监听端口: ${PORT}"
echo "连接密码: ${PASSWORD}"
echo "运行状态: ${STATUS}"
echo "------------------------------------------------------------"
echo "🔗 Trojan 客户端节点链接 (已推送至 TG):"
echo "${TROJAN_LINK}"
echo "════════════════════════════════════════════════════════════"
