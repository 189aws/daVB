#!/bin/bash
# 交互式 acme.sh Let's Encrypt 证书一键安装脚本
# 纯原生，无外部依赖，standalone 模式

set -e

# 颜色输出
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
RESET="\e[0m"

info()  { echo -e "${GREEN}[INFO]${RESET} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${RESET} $*"; }
error() { echo -e "${RED}[ERROR]${RESET} $*"; }

clear
cat << "EOF"
╔══════════════════════════════════════════════════════╗
║           🎉 acme.sh Let's Encrypt 一键证书         ║
║                纯原生 • 无外部依赖 • HTTPS           ║
╚══════════════════════════════════════════════════════╝
EOF

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
    error "请使用 root 或 sudo 执行此脚本"
    exit 1
fi

# 获取用户输入
echo
read -p "👤 请输入邮箱 (续期通知用): " EMAIL
read -p "🌐 请输入域名 (已解析到本机公网IP): " DOMAIN

if [[ -z "$EMAIL" || -z "$DOMAIN" ]]; then
    error "邮箱和域名不能为空！"
    exit 1
fi

info "配置信息："
echo "   邮箱: $EMAIL"
echo "   域名: $DOMAIN"
echo

read -p "确认信息正确? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    error "用户取消"
    exit 1
fi

# 1. 安装依赖
info "📦 安装依赖 (curl socat)..."
apt update -y
apt install -y curl socat cron

# 2. 完全删除旧 acme.sh
info "🧹 清理旧 acme.sh 配置..."
rm -rf ~/.acme.sh

# 3. 全新安装 acme.sh
info "🚀 全新安装 acme.sh (使用你的邮箱: $EMAIL)..."
curl https://get.acme.sh | sh -s email="$EMAIL"
source ~/.bashrc 2>/dev/null || true

ACME_SH="$HOME/.acme.sh/acme.sh"

# 4. 验证账号注册
info "✅ 验证 Let's Encrypt 账号..."
"$ACME_SH" --register-account --server letsencrypt

# 5. 设置默认 CA
info "🎯 设置默认 CA 为 Let's Encrypt..."
"$ACME_SH" --set-default-ca --server letsencrypt

# 6. 停止占用80端口的服务
info "🔌 停止占用80端口的服务..."
for service in nginx apache2 httpd; do
    systemctl stop "$service" 2>/dev/null || true
done

# 7. 检查80端口
if ss -tlnp | grep -q ":80 "; then
    error "80端口仍被占用，请手动停止服务后重试"
    exit 1
fi

info "✅ 80端口已空闲"

# 8. 签发证书
info "📜 开始签发证书: $DOMAIN"
"$ACME_SH" --issue -d "$DOMAIN" --standalone

# 9. 安装证书到标准位置
CERT_DIR="/etc/ssl/$DOMAIN"
info "📁 创建证书目录: $CERT_DIR"
mkdir -p "$CERT_DIR"

info "💾 安装证书..."
"$ACME_SH" --install-cert -d "$DOMAIN" \
    --key-file "$CERT_DIR/privkey.pem" \
    --fullchain-file "$CERT_DIR/fullchain.pem" \
    --reloadcmd "systemctl reload nginx 2>/dev/null || true"

# 设置权限
chmod 600 "$CERT_DIR/privkey.pem"
chmod 644 "$CERT_DIR/fullchain.pem"

# 10. 显示成功结果
clear
cat << EOF

${GREEN}🎉 证书签发成功完成！${RESET}

📁 证书位置:
├── 目录: ${CERT_DIR}
├── 私钥: ${CERT_DIR}/privkey.pem      (chmod 600)
└── 证书: ${CERT_DIR}/fullchain.pem    (chmod 644)

${YELLOW}🌐 Nginx 配置示例:${RESET}
\`\`\`nginx
server {
    listen 443 ssl http2;
    server_name ${DOMAIN};
    
    ssl_certificate      ${CERT_DIR}/fullchain.pem;
    ssl_certificate_key  ${CERT_DIR}/privkey.pem;
}
\`\`\`

${YELLOW}🐳 NodePassDash Docker 配置:${RESET}
\`\`\`yaml
services:
  nodepassdash:
    image: ghcr.io/nodepassproject/nodepassdash:latest
    ports:
      - "443:443"
    volumes:
      - ./db:/app/db
      - ${CERT_DIR}:/certs:ro
    command: ["./nodepassdash","--port","443","--cert","/certs/fullchain.pem","--key","/certs/privkey.pem"]
\`\`\`

${GREEN}🔄 自动续期:${RESET}
└── acme.sh 已配置 cron，每天凌晨2点自动续期

${GREEN}✅ 验证证书:${RESET}
EOF

# 验证证书
if [ -f "$CERT_DIR/fullchain.pem" ]; then
    echo "📋 证书详情:"
    openssl x509 -in "$CERT_DIR/fullchain.pem" -subject -dates -noout | sed 's/^/   /'
    echo
    info "你可以立即测试: https://${DOMAIN}"
else
    error "证书生成失败！"
    exit 1
fi

echo
read -p "按 Enter 键退出..."
