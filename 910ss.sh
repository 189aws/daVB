#!/bin/bash
set -e

# ========== 配置区 ==========
TG_TOKEN="8896559295:AAE5gr8Rhy0I-E7ah5TGWY7IopiWfHGtQsE"
TG_CHAT_ID="1417748881"

# 1. 优化 SNI 域名池（随机挑选海外知名支持 TLS 1.3 的域名，严禁使用国内域名）
SNI_LIST=(
    "gateway.icloud.com"
    "www.microsoft.com"
    "swdist.apple.com"
    "www.lovelive-anime.jp"
    "cdn.cloudflare.com"
)
SNI_DOMAIN=${SNI_LIST[$RANDOM % ${#SNI_LIST[@]}]}

# 2. 自动随机生成参数
SS_PORT=$(shuf -i 30000-45000 -n 1)         # 内部 SS 随机监听端口
LISTEN_PORT=$(shuf -i 10000-50000 -n 1)      # 外部随机监听端口（避免写死443被集中探测）
TLS_PWD=$(openssl rand -hex 16)             # 随机 32 位 Shadow-TLS 密码
SS_KEY=$(openssl rand -base64 16)           # 精确生成 16 字节 Base64 密钥
# ============================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# ── 1. 安装基础依赖与 Docker ─────────────────────────────────────
log "检查基础依赖与 Docker 环境..."
apt-get update -qq && apt-get install -y -qq openssl psmisc python3 curl >/dev/null 2>&1

if ! command -v docker &>/dev/null; then
    warn "Docker 未安装，正在安装..."
    apt-get install -y -qq docker.io
    systemctl start docker && systemctl enable docker
    log "Docker 安装完成"
fi
docker info &>/dev/null || err "Docker 守护进程未运行，请检查"

# ── 2. 深度清理旧容器 ─────────────────────────────────────────
log "清理旧容器..."
docker rm -f ss-rust shadow-tls 2>/dev/null || true
sleep 1

# ── 3. 输出生成的随机配置 ──────────────────────────────────────
log "生成随机配置成功："
log "  - 外部监听端口 : ${LISTEN_PORT}"
log "  - 本地 SS 端口 : ${SS_PORT}"
log "  - SNI 伪装域名 : ${SNI_DOMAIN}"
log "  - SS 2022 密钥 : ${SS_KEY}"
log "  - Shadow-TLS密码: ${TLS_PWD}"

# ── 4. 启动内层 Shadowsocks-Rust 容器 ──────────────────────────
log "启动 Shadowsocks-Rust 容器..."
docker run -d \
    --name ss-rust \
    --restart always \
    --network host \
    ghcr.io/shadowsocks/ssserver-rust:latest \
    ssserver \
        --server-addr "127.0.0.1:${SS_PORT}" \
        --encrypt-method "2022-blake3-aes-128-gcm" \
        --password "${SS_KEY}" \
        --timeout 300 \
        -U

# ── 5. 启动外层 Shadow-TLS 容器 ────────────────────────────────
log "启动 Shadow-TLS 容器..."
docker run -d \
    --name shadow-tls \
    --restart always \
    --network host \
    --entrypoint shadow-tls \
    ghcr.io/ihciah/shadow-tls:v0.2.23 \
    --v3 server \
    --listen "0.0.0.0:${LISTEN_PORT}" \
    --server "127.0.0.1:${SS_PORT}" \
    --tls "${SNI_DOMAIN}:443" \
    --password "${TLS_PWD}"

sleep 3

# ── 6. 获取服务器公网 IP ────────────────────────────────────────
log "获取公网 IP..."
SERVER_IP=$(curl -s --max-time 10 ipv4.icanhazip.com || \
            curl -s --max-time 10 api.ipify.org || \
            curl -s --max-time 10 ifconfig.me)
[ -z "$SERVER_IP" ] && err "无法获取公网 IP"

# ── 7. 生成 Shadowrocket 专用节点链接 ──────────────────────────
SS_B64=$(python3 -c "
import base64
raw = '2022-blake3-aes-128-gcm:${SS_KEY}'
b64 = base64.urlsafe_b64encode(raw.encode()).decode().rstrip('=')
print(b64)
")

STLS_B64=$(python3 -c "
import base64, json
obj = {'version': '3', 'host': '${SNI_DOMAIN}', 'password': '${TLS_PWD}'}
b64 = base64.urlsafe_b64encode(json.dumps(obj, separators=(',',':')).encode()).decode().rstrip('=')
print(b64)
")

SS_LINK="ss://${SS_B64}@${SERVER_IP}:${LISTEN_PORT}?shadow-tls=${STLS_B64}#SS2022_${SNI_DOMAIN}"

# ── 8. 推送配置到 Telegram ─────────────────────────────────────
curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
    -d "chat_id=${TG_CHAT_ID}" \
    --data-urlencode "text=节点配置部署完成：
${SS_LINK}" >/dev/null

echo "部署完成！链接已发送至 Telegram。"
