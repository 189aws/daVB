#!/bin/bash
set -e

# ========== 配置区 ==========
TG_TOKEN="8573396561:AAHR3UgpGXrk2WV-h6l9uAtWQKblySjybxQ"
TG_CHAT_ID="1417748881"
SNI_DOMAIN="aws.amazon.com"
TLS_PWD="FEW11CV6ADfds1fwe61c3298cdasee"
SS_PORT=30225
LISTEN_PORT=443
# ============================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# ── 1. 安装 Docker 与系统网络调优（优化 UDP 缓冲区） ──────────────
log "检查 Docker 环境与优化网络..."
if ! command -v docker &>/dev/null; then
    warn "Docker 未安装，正在安装..."
    apt-get update -qq && apt-get install -y -qq docker.io
    systemctl start docker && systemctl enable docker
fi
docker info &>/dev/null || err "Docker 守护进程未运行，请检查"

sysctl -w net.core.rmem_max=2500000 &>/dev/null || true
sysctl -w net.core.wmem_max=2500000 &>/dev/null || true

# ── 2. 深度清理旧容器和占用端口 ────────────────────────────────
log "清理旧容器..."
docker rm -f ss-rust shadow-tls 2>/dev/null || true
sleep 1
fuser -k ${LISTEN_PORT}/tcp 2>/dev/null || true
fuser -k ${LISTEN_PORT}/udp 2>/dev/null || true
fuser -k ${SS_PORT}/tcp     2>/dev/null || true
fuser -k ${SS_PORT}/udp     2>/dev/null || true
sleep 1

# ── 3. 固定 SS 2022 密钥 ────────────────────────────────────────
SS_KEY="6/1w4cDEC44111GlyRcc/w=="

# ── 4. 启动内层 Shadowsocks-Rust 容器（强化 UDP 支持） ──────────
log "启动 Shadowsocks-Rust 容器（启用完整 UDP 转发）..."
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

log "等待 Shadowsocks 启动..."
for i in $(seq 1 15); do
    if docker exec ss-rust ss -tlnp 2>/dev/null | grep -q "${SS_PORT}"; then
        log "Shadowsocks 已在 127.0.0.1:${SS_PORT} 监听"
        break
    fi
    sleep 1
done

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

SS_LINK="ss://${SS_B64}@${SERVER_IP}:${LISTEN_PORT}?shadow-tls=${STLS_B64}&udp=1#SS2022_ShadowTLS_UDP"

# ── 8. 推送节点链接到 Telegram (使用 HTML parse_mode 保证点击可复制) ────────
log "推送配置到 Telegram..."
TG_TEXT="<b>SS2022 + Shadow-TLS 节点部署成功</b>

<b>服务器 IP:</b> <code>${SERVER_IP}</code>
<b>监听端口:</b> <code>${LISTEN_PORT}</code>

<b>点击下方代码块即可一键复制节点链接:</b>
<code>${SS_LINK}</code>"

RESPONSE=$(curl -s --connect-timeout 10 -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
    -d "chat_id=${TG_CHAT_ID}" \
    -d "parse_mode=HTML" \
    --data-urlencode "text=${TG_TEXT}")

if echo "$RESPONSE" | grep -q '"ok":true'; then
    log "Telegram 推送成功！"
else
    warn "Telegram 推送失败，返回接口结果如下："
    echo "$RESPONSE"
fi

# ── 9. 本地输出汇总 ────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════"
echo "  部署完成汇总"
echo "══════════════════════════════════════════════"
echo "  服务器IP    : ${SERVER_IP}"
echo "  监听端口    : ${LISTEN_PORT}"
echo "  一键链接:"
echo "  ${SS_LINK}"
echo "══════════════════════════════════════════════"
