#!/bin/bash

# 检查是否传入域名参数
DOMAIN=$1
if [ -z "$DOMAIN" ]; then
    echo "错误: 请传入需要申请证书的域名！"
    echo "用法: bash acme.sh <你的域名>"
    exit 1
fi

EMAIL="88888@qq.com"

echo "=========================================="
echo "准备为域名 [$DOMAIN] 一键申请 Let's Encrypt 证书"
echo "使用邮箱: $EMAIL"
echo "=========================================="

# 1. 检查并安装依赖工具 (socat, curl, cron)
if command -v apt-get &>/dev/null; then
    apt-get update -y && apt-get install -y curl socat cron
elif command -v yum &>/dev/null; then
    yum install -y curl socat crontabs
fi

# 确保 cron 服务已启动
systemctl start cron 2>/dev/null || systemctl start crond 2>/dev/null || service cron start 2>/dev/null

# 2. 安装 acme.sh 官方客户端
if [ ! -f "$HOME/.acme.sh/acme.sh" ]; then
    echo "正在安装 acme.sh 客户端..."
    curl https://get.acme.sh | sh -s email="$EMAIL"
fi

ACME="$HOME/.acme.sh/acme.sh"

# 3. 注册账号并切换 CA 为 Let's Encrypt
echo "注册账号并设置 CA 服务商为 Let's Encrypt..."
$ACME --register-account -m "$EMAIL" --server letsencrypt
$ACME --set-default-ca --server letsencrypt

# 4. 检查 80 端口占用情况并放行（针对 standalone 独立模式）
if command -v ufw &>/dev/null; then
    ufw allow 80/tcp 2>/dev/null
fi
if command -v iptables &>/dev/null; then
    iptables -I INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null
fi

# 5. 使用 standalone 80 端口模式强制申请证书 (--force 覆盖已有配置)
echo "开始签发证书..."
$ACME --issue -d "$DOMAIN" --standalone --force

# 6. 检查证书签发结果并安装到指定目录
CERT_DIR="/etc/ssl/$DOMAIN"
mkdir -p "$CERT_DIR"

if $ACME --install-cert -d "$DOMAIN" \
    --key-file       "$CERT_DIR/private.key" \
    --fullchain-file "$CERT_DIR/fullchain.crt"; then
    echo "=========================================="
    echo "SUCCESS: 证书申请与安装成功！"
    echo "公钥路径 (Fullchain): $CERT_DIR/fullchain.crt"
    echo "私钥路径 (Private Key): $CERT_DIR/private.key"
    echo "=========================================="
else
    echo "=========================================="
    echo "ERROR: 证书申请失败，请检查 80 端口是否被占用或域名 DNS 解析是否已指向本机。"
    echo "=========================================="
    exit 1
fi
