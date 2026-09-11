#!/bin/bash

DOMAIN=$1
if [ -z "$DOMAIN" ]; then
    echo "错误: 请传入需要申请证书的域名！"
    echo "用法: bash acme.sh <你的域名>"
    exit 1
fi

EMAIL="888888@qq.com"

echo "=========================================="
echo "准备为域名 [$DOMAIN] 一键申请 Let's Encrypt 证书"
echo "使用邮箱: $EMAIL"
echo "=========================================="

# 1. 安装依赖
if command -v apt-get &>/dev/null; then
    apt-get update -y && apt-get install -y curl socat cron
elif command -v yum &>/dev/null; then
    yum install -y curl socat crontabs
fi

systemctl start cron 2>/dev/null || systemctl start crond 2>/dev/null || service cron start 2>/dev/null

# 2. 安装 acme.sh
if [ ! -f "$HOME/.acme.sh/acme.sh" ]; then
    echo "正在安装 acme.sh 客户端..."
    curl https://get.acme.sh | sh -s email="$EMAIL"
fi

ACME="$HOME/.acme.sh/acme.sh"

# 3. 注册账号并切换 CA
$ACME --register-account -m "$EMAIL" --server letsencrypt >/dev/null 2>&1
$ACME --set-default-ca --server letsencrypt >/dev/null 2>&1

# 4. 放行 80 端口
if command -v ufw &>/dev/null; then
    ufw allow 80/tcp 2>/dev/null
fi
if command -v iptables &>/dev/null; then
    iptables -I INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null
fi

# 5. 签发证书（增加失败拦截）
echo "开始签发证书..."
$ACME --issue -d "$DOMAIN" --standalone --force

if [ $? -ne 0 ]; then
    echo "=========================================="
    echo "ERROR: 证书签发失败！"
    echo "失败原因：域名 DNS 解析尚未生效，或 80 端口被防火墙/其他程序占用。"
    echo "请检查："
    echo "1. ping $DOMAIN 是否能解析到当前 VPS 的公网 IP"
    echo "2. Cloudflare 是否关闭了小黄云代理 (改选 DNS only)"
    echo "=========================================="
    exit 1
fi

# 6. 安装证书
CERT_DIR="/etc/ssl/$DOMAIN"
mkdir -p "$CERT_DIR"

$ACME --install-cert -d "$DOMAIN" \
    --key-file       "$CERT_DIR/private.key" \
    --fullchain-file "$CERT_DIR/fullchain.crt"

if [ -f "$CERT_DIR/fullchain.crt" ] && [ -f "$CERT_DIR/private.key" ]; then
    echo "=========================================="
    echo "SUCCESS: 证书申请与安装成功！"
    echo "公钥路径 (Fullchain): $CERT_DIR/fullchain.crt"
    echo "私钥路径 (Private Key): $CERT_DIR/private.key"
    echo "=========================================="
else
    echo "ERROR: 证书导出失败。"
    exit 1
fi
