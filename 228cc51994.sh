#!/bin/bash
# ================================================
# Trojan Docker 一键部署脚本 (修复版)
# 端口: 51994 | SNI: v.qq.com | 推送: Telegram
# ================================================

set -e

# ── 基础配置 ────────────────────────────────────
PASSWORD="AJOaaakkklldAABN"
PORT=51994
SNI="v.qq.com"
WORK_DIR="/opt/trojan"

# ── Telegram 配置 ───────────────────────────────
TG_TOKEN="7756669471:AAFstxnzCweHItNptwOf7UU-p6xj3pwnAI8"
TG_CHAT_ID="1792396794"

# ── 颜色输出 ────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[*]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[✗]${NC} $1"; exit 1; }

echo ""
echo -e "${BLUE}=================================================${NC}"
echo -e "${BLUE}      Trojan Docker 一键部署脚本 (修复版)       ${NC}"
echo -e "${BLUE}=================================================${NC}"
echo ""

# ── 检查 root ───────────────────────────────────
if [ "$EUID" -ne 0 ]; then
  error "请使用 root 权限运行此脚本: sudo bash $0"
fi

# ── 安装 Docker ─────────────────────────────────
install_docker() {
  if command -v docker &> /dev/null; then
    success "Docker 已安装，跳过"
    return
  fi
  info "安装 Docker..."
  apt-get update -y
  apt-get install -y ca-certificates curl gnupg lsb-release
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/debian $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io
  systemctl enable docker
  systemctl start docker
  success "Docker 安装完成"
}

# ── 安装 docker-compose ─────────────────────────
install_compose() {
  if command -v docker-compose &> /dev/null; then
    success "docker-compose 已安装，跳过"
    return
  fi
  info "安装 docker-compose..."
  curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
    -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
  success "docker-compose 安装完成"
}

# ── 生成自签证书（模拟 SNI）────────────────────
gen_cert() {
  info "生成模拟 ${SNI} 的自签证书..."
  mkdir -p ${WORK_DIR}/certs
  openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
    -keyout ${WORK_DIR}/certs/server.key \
    -out    ${WORK_DIR}/certs/server.crt \
    -subj "/CN=${SNI}" \
    -addext "subjectAltName=DNS:${SNI}" 2>/dev/null
  success "证书生成完成 (CN=${SNI}, 有效期10年)"
}

# ── Trojan 服务端配置 ───────────────────────────
write_config() {
  info "写入 Trojan 配置..."
  mkdir -p ${WORK_DIR}
  cat > ${WORK_DIR}/config.json <<EOF
{
  "run_type": "server",
  "local_addr": "0.0.0.0",
  "local_port": 443,
  "remote_addr": "trojan_nginx",
  "remote_port": 80,
  "password": ["${PASSWORD}"],
  "log_level": 1,
  "ssl": {
    "cert": "/etc/trojan/certs/server.crt",
    "key": "/etc/trojan/certs/server.key",
    "key_password": "",
    "cipher": "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384",
    "prefer_server_cipher": true,
    "alpn": ["h2", "http/1.1"],
    "sni": "${SNI}",
    "session_reuse": true,
    "session_timeout": 600,
    "curves": ""
  },
  "tcp": {
    "prefer_ipv4": true,
    "no_delay": true,
    "keep_alive": true,
    "fast_open": false,
    "fast_open_qlen": 20
  },
  "mysql": {
    "enabled": false
  }
}
EOF
  success "Trojan 配置写入完成"
}

# ── 伪装 Nginx（非 Trojan 流量回落）───────────
write_nginx() {
  info "写入伪装 Nginx 配置..."
  mkdir -p ${WORK_DIR}/nginx
  cat > ${WORK_DIR}/nginx/default.conf <<EOF
server {
    listen 80 default_server;
    server_name _;

    add_header Server "nginx";
    add_header X-Powered-By "";

    location / {
        return 301 https://v.qq.com\$request_uri;
    }

    location /health {
        return 200 'ok';
        add_header Content-Type text/plain;
    }
}
EOF
  success "Nginx 伪装配置写入完成"
}

# ── docker-compose.yml（修复版：指定完整配置路径）──
write_compose() {
  info "写入 docker-compose.yml..."
  cat > ${WORK_DIR}/docker-compose.yml <<EOF
version: '3.8'

services:
  nginx:
    image: nginx:alpine
    container_name: trojan_nginx
    restart: always
    volumes:
      - ./nginx/default.conf:/etc/nginx/conf.d/default.conf:ro
    networks:
      - trojan_net

  trojan:
    image: trojangfw/trojan:latest
    container_name: trojan_server
    restart: always
    ports:
      - "${PORT}:443"
    volumes:
      - ./config.json:/etc/trojan/config.json:ro
      - ./certs:/etc/trojan/certs:ro
    command: ["trojan", "/etc/trojan/config.json"]
    depends_on:
      - nginx
    networks:
      - trojan_net

networks:
  trojan_net:
    driver: bridge
EOF
  success "docker-compose.yml 写入完成"
}

# ── 防火墙放行 ──────────────────────────────────
open_firewall() {
  info "配置防火墙，放行端口 ${PORT}..."
  if command -v ufw &> /dev/null; then
    ufw allow ${PORT}/tcp > /dev/null 2>&1 || true
  fi
  iptables -I INPUT -p tcp --dport ${PORT} -j ACCEPT 2>/dev/null || true
  if command -v netfilter-persistent &> /dev/null; then
    netfilter-persistent save > /dev/null 2>&1 || true
  fi
  success "防火墙端口 ${PORT} 已放行"
}

# ── 清理旧容器并启动服务 ────────────────────────
start_service() {
  info "清理旧容器..."
  docker rm -f trojan_server trojan_nginx 2>/dev/null || true

  info "拉取镜像并启动服务..."
  cd ${WORK_DIR}
  docker-compose pull
  docker-compose up -d

  sleep 3

  if docker ps | grep -q "trojan_server"; then
    success "Trojan 容器运行正常 ✅"
  else
    warn "Trojan 容器未正常启动，查看日志: docker logs trojan_server"
  fi

  if docker ps | grep -q "trojan_nginx"; then
    success "Nginx 容器运行正常 ✅"
  else
    warn "Nginx 容器未正常启动，查看日志: docker logs trojan_nginx"
  fi
}

# ── 验证 TLS 握手 ───────────────────────────────
verify_tls() {
  info "验证 TLS 握手..."
  sleep 2
  local RESULT
  RESULT=$(echo | openssl s_client -connect 127.0.0.1:${PORT} -servername ${SNI} 2>&1 | grep -E "subject|issuer|Verify|CONNECTED")
  if echo "$RESULT" | grep -q "CONNECTED"; then
    success "TLS 握手验证通过 ✅"
    echo "$RESULT"
  else
    warn "TLS 握手验证失败，请检查: docker logs trojan_server"
  fi
}

# ── 获取公网 IP ─────────────────────────────────
get_public_ip() {
  local IP=""
  IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null)       && [ -n "$IP" ] && echo "$IP" && return
  IP=$(curl -s --max-time 5 https://ifconfig.me 2>/dev/null)          && [ -n "$IP" ] && echo "$IP" && return
  IP=$(curl -s --max-time 5 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null) && [ -n "$IP" ] && echo "$IP" && return
  hostname -I | awk '{print $1}'
}

# ── 发送 Telegram 通知 ──────────────────────────
send_telegram() {
  local SERVER_IP="$1"
  local TROJAN_LINK="$2"
  local CLASH_CFG="$3"

  local REGION=$(curl -s --max-time 3 http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo "unknown")
  local INSTANCE_ID=$(curl -s --max-time 3 http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "unknown")
  local INSTANCE_TYPE=$(curl -s --max-time 3 http://169.254.169.254/latest/meta-data/instance-type 2>/dev/null || echo "unknown")
  local DEPLOY_TIME=$(date '+%Y-%m-%d %H:%M:%S %Z')

  local MSG="🚀 *Trojan 节点部署成功*

━━━━━━━━━━━━━━━━━━━━
📍 *服务器信息*
\`\`\`
公网IP     : ${SERVER_IP}
区域       : ${REGION}
实例ID     : ${INSTANCE_ID}
实例类型   : ${INSTANCE_TYPE}
部署时间   : ${DEPLOY_TIME}
\`\`\`

━━━━━━━━━━━━━━━━━━━━
⚙️ *节点配置*
\`\`\`
地址       : ${SERVER_IP}
端口       : ${PORT}
密码       : ${PASSWORD}
SNI        : ${SNI}
TLS        : 开启 (自签证书)
跳过验证   : 是
\`\`\`

━━━━━━━━━━━━━━━━━━━━
🔗 *Trojan 节点链接*
\`\`\`
${TROJAN_LINK}
\`\`\`

━━━━━━━━━━━━━━━━━━━━
📋 *Clash 配置片段*
\`\`\`yaml
${CLASH_CFG}
\`\`\`

━━━━━━━━━━━━━━━━━━━━
⚠️ 请确认 AWS 安全组已放行 TCP \`${PORT}\`
🐳 查看日志: \`docker logs trojan_server\`"

  info "推送节点信息到 Telegram..."

  local HTTP_CODE
  HTTP_CODE=$(curl -s -o /tmp/tg_resp.json -w "%{http_code}" \
    -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
    -H "Content-Type: application/json" \
    -d "{
      \"chat_id\": \"${TG_CHAT_ID}\",
      \"text\": $(python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' <<< "$MSG"),
      \"parse_mode\": \"Markdown\",
      \"disable_web_page_preview\": true
    }")

  if [ "$HTTP_CODE" = "200" ] && grep -q '"ok":true' /tmp/tg_resp.json; then
    success "Telegram 推送成功 ✅"
  else
    warn "Markdown 推送失败，尝试纯文本..."
    local PLAIN_MSG="Trojan节点部署完成
公网IP: ${SERVER_IP}  端口: ${PORT}
密码: ${PASSWORD}  SNI: ${SNI}
区域: ${REGION}  时间: ${DEPLOY_TIME}

节点链接:
${TROJAN_LINK}

Clash配置:
${CLASH_CFG}

请在AWS安全组放行TCP ${PORT}"

    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
      --data-urlencode "chat_id=${TG_CHAT_ID}" \
      --data-urlencode "text=${PLAIN_MSG}" \
      --data-urlencode "disable_web_page_preview=true" > /dev/null
    success "纯文本降级推送完成 ✅"
  fi
}

# ── 打印 & 推送节点信息 ─────────────────────────
print_and_notify() {
  info "获取公网 IP..."
  local SERVER_IP
  SERVER_IP=$(get_public_ip)
  success "公网 IP: ${SERVER_IP}"

  # 生成标准 Trojan 链接
  local ENCODED_PASSWORD
  ENCODED_PASSWORD=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${PASSWORD}', safe=''))")
  local NODE_NAME="AWS-Trojan-US-${SERVER_IP}"
  local ENCODED_NAME
  ENCODED_NAME=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${NODE_NAME}', safe=''))")
  local TROJAN_LINK="trojan://${ENCODED_PASSWORD}@${SERVER_IP}:${PORT}?sni=${SNI}&allowInsecure=1&peer=${SNI}#${ENCODED_NAME}"

  # 生成 Clash 配置片段
  local CLASH_CFG="- name: AWS-Trojan-US
  type: trojan
  server: ${SERVER_IP}
  port: ${PORT}
  password: ${PASSWORD}
  sni: ${SNI}
  skip-cert-verify: true
  udp: true"

  echo ""
  echo -e "${GREEN}=================================================${NC}"
  echo -e "${GREEN}         🎉 部署完成！节点信息如下              ${NC}"
  echo -e "${GREEN}=================================================${NC}"
  echo -e "  公网IP  : ${SERVER_IP}"
  echo -e "  端口    : ${PORT}"
  echo -e "  密码    : ${PASSWORD}"
  echo -e "  SNI     : ${SNI}"
  echo ""
  echo -e "  🔗 Trojan 节点链接:"
  echo -e "  ${YELLOW}${TROJAN_LINK}${NC}"
  echo ""
  echo -e "  📋 Clash 配置片段:"
  echo "${CLASH_CFG}"
  echo -e "${GREEN}=================================================${NC}"
  echo -e "  ⚠️  请在 AWS 控制台安全组放行 TCP ${PORT}"
  echo -e "  🐳 查看日志: docker logs trojan_server"
  echo -e "${GREEN}=================================================${NC}"
  echo ""

  send_telegram "${SERVER_IP}" "${TROJAN_LINK}" "${CLASH_CFG}"
}

# ================================================
#  主流程
# ================================================
install_docker
install_compose
gen_cert
write_config
write_nginx
write_compose
open_firewall
start_service
verify_tls
print_and_notify
