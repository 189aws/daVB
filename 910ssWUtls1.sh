#!/bin/bash
set -e

# ========== 配置区 ==========
TG_TOKEN="8896559295:AAE5gr8Rhy0I-E7ah5TGWY7IopiWfHGtQsE"
TG_CHAT_ID="1417748881"

# 自动随机生成参数
LISTEN_PORT=443
SS_KEY=$(openssl rand -base64 16)          # 精确生成 16 字节 Base64 密钥
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

# ── 2. 深度清理旧容器和占用端口 ────────────────────────────────
log "清理旧容器及端口..."
docker rm -f ss-rust shadow-tls 2>/dev/null || true
sleep 1
fuser -k ${LISTEN_PORT}/tcp 2>/dev/null || true
sleep 1

# ── 3. 输出生成的随机密钥信息 ────────────────────────────────────
log "生成随机配置成功："
log "  - 外部监听端口 : ${LISTEN_PORT}"
log "  - SS 2022 密钥 : ${SS_KEY}"

# ── 4. 启动 Shadowsocks-Rust 容器 ───────────────────────────────
log "启动 Shadowsocks-Rust 容器..."
docker run -d \
    --name ss-rust \
    --restart always \
    --network host \
    ghcr.io/shadowsocks/ssserver-rust:latest \
    ssserver \
        --server-addr "0.0.0.0:${LISTEN_PORT}" \
        --encrypt-method "2022-blake3-aes-128-gcm" \
        --password "${SS_KEY}" \
        --timeout 300 \
        -U

log "等待 Shadowsocks 启动..."
for i in $(seq 1 15); do
    if docker exec ss-rust ss -tlnp 2>/dev/null | grep -q "${LISTEN_PORT}" || \
       ss -tlnp 2>/dev/null | grep -q "${LISTEN_PORT}"; then
        log "Shadowsocks 已在 0.0.0.0:${LISTEN_PORT} 监听"
        break
    fi
    if [ $i -eq 15 ]; then
        warn "等待超时，继续尝试（查看日志：docker logs ss-rust）"
        docker logs ss-rust 2>&1 | tail -20
    fi
    sleep 1
done

# ── 5. 验证容器状态 ─────────────────────────────────────────────
log "验证容器运行状态..."
SS_STATUS=$(docker inspect -f '{{.State.Status}}' ss-rust 2>/dev/null)

if [ "$SS_STATUS" != "running" ]; then
    warn "ss-rust 状态异常: $SS_STATUS"
    docker logs ss-rust 2>&1 | tail -30
fi

# ── 6. 获取服务器公网 IP ────────────────────────────────────────
log "获取公网 IP..."
SERVER_IP=$(curl -s --max-time 10 ipv4.icanhazip.com || \
            curl -s --max-time 10 api.ipify.org || \
            curl -s --max-time 10 ifconfig.me)
[ -z "$SERVER_IP" ] && err "无法获取公网 IP"
log "服务器 IP：$SERVER_IP"

# ── 7. 生成 标准 SS 节点链接 ────────────────────────────────────
log "生成节点链接..."

SS_B64=$(python3 -c "
import base64
raw = '2022-blake3-aes-128-gcm:${SS_KEY}'
b64 = base64.urlsafe_b64encode(raw.encode()).decode().rstrip('=')
print(b64)
")

SS_LINK="ss://${SS_B64}@${SERVER_IP}:${LISTEN_PORT}#SS2022_Node"

# ── 8. 推送节点链接到 Telegram ─────────────────────────────────
log "推送配置到 Telegram..."
curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
    -d "chat_id=${TG_CHAT_ID}" \
    --data-urlencode "text=
${SS_LINK}" >/dev/null

# ── 9. 本地输出汇总 ────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════"
echo "  部署完成汇总"
echo "══════════════════════════════════════════════"
echo "  服务器IP    : ${SERVER_IP}"
echo "  监听端口    : ${LISTEN_PORT}"
echo "  加密算法    : 2022-blake3-aes-128-gcm"
echo "  SS 密码     : ${SS_KEY}"
echo "══════════════════════════════════════════════"
echo "  一键链接:"
echo "  ${SS_LINK}"
echo "══════════════════════════════════════════════"
echo ""
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""
log "配置已推送到 Telegram，请查收！"
