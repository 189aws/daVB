#!/usr/bin/env bash

# 提示输入域名
read -p "请输入要申请证书的域名: " DOMAIN

if [ -z "$DOMAIN" ]; then
    echo "域名不能为空！"
    exit 1
fi

# 1. 自动检查并安装 cron 依赖
if ! command -v crontab &> /dev/null; then
    echo "正在安装 cron 服务..."
    if command -v apt &> /dev/null; then
        apt update && apt install -y cron
        systemctl enable --now cron
    elif command -v yum &> /dev/null; then
        yum install -y crontabs
        systemctl enable --now crond
    fi
fi

# 2. 确保 acme.sh 已安装（不传邮箱）
if [ ! -f "$HOME/.acme.sh/acme.sh" ]; then
    echo "正在安装 acme.sh..."
    curl https://get.acme.sh | sh
fi

ALIAS_CMD="$HOME/.acme.sh/acme.sh"

# 3. 设置默认 CA 为 Let's Encrypt（免邮箱极速签发）
$ALIAS_CMD --set-default-ca --server letsencrypt

# 4. 申请证书 (无需注册邮箱，直接申请)
$ALIAS_CMD --issue -d "$DOMAIN" --standalone --server letsencrypt

# 5. 安装并复制证书到固定路径
$ALIAS_CMD --install-cert -d "$DOMAIN" \
  --key-file       /root/XXX.key \
  --fullchain-file /root/XXX.crt \
  --reloadcmd      "echo '证书申请完成，已存至 /root/XXX.crt 和 /root/XXX.key'"