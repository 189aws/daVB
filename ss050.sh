#!/bin/bash
set -e

# ========== 配置区 ==========
FEISHU_WEBHOOK="[https://open.feishu.cn/open-apis/bot/v2/hook/83914acb-f50e-4aed-8bfc-b71f7f19ed3f](https://open.feishu.cn/open-apis/bot/v2/hook/83914acb-f50e-4aed-8bfc-b71f7f19ed3f)"
SNI_DOMAIN="[www.tesla.com](https://www.tesla.com)"

# 自动随机生成参数
SS_PORT=$(shuf -i 30000-45000 -n 1)        # 内部 SS 随机监听端口
LISTEN_PORT=51994
TLS_PWD=$(openssl rand -hex 16)            # 随机 32 位 Shadow-TLS 密码
SS_KEY=$(openssl rand -base64 16)          # 精确生成 16 字节 Base64 密钥
# ============================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# ── 0. 开启 BBR 与 Linux 内核 TCP 缓冲区深度调优 ───────────────────
log "优化系统内核 TCP 参数与开启 BBR..."
cat <<EOF> /etc/sysctl.d/99-shadowtls-speed.conf
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.rmem_max=67108864
net.core.wmem_max=67108864
net.ipv4.tcp_rmem=4096 87380 33554432
net.ipv4.tcp_wmem=4096 65536 33554432
net.core.somaxconn=65535
net.ipv4.tcp_max_syn_backlog=65535
EOF
sysctl --system >/dev/null 2>&1 || true

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
docker rm -f shadow-tls ss-rust 2>/dev/null || true
sleep 1
fuser -k ${LISTEN_PORT}/tcp 2>/dev/null || true
fuser -k ${SS_PORT}/tcp     2>/dev/null || true
sleep 1

# ── 3. 输出生成的随机密钥信息 ────────────────────────────────────
log "生成随机配置成功："
log "  - 外部监听端口 : ${LISTEN_PORT}"
log "  - 本地 SS 端口 : ${SS_PORT}"
log "  - SS 2022 密钥 : ${SS_KEY}"
log "  - Shadow-TLS密码: ${TLS_PWD}"

# ── 4. 启动 Shadow-TLS 主容器 ─────────────────────────────────────
log "启动 Shadow-TLS 主容器..."
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

# ── 5. 启动 SS-Rust 并嵌入 Shadow-TLS 网络空间 ─────────────────────
log "启动 SS-Rust 并嵌入 Shadow-TLS 网络空间..."
docker run -d \
    --name ss-rust \
    --restart always \
    --net=container:shadow-tls \
    ghcr.io/shadowsocks/ssserver-rust:latest \
    ssserver \
        --server-addr "127.0.0.1:${SS_PORT}" \
        --encrypt-method "2022-blake3-aes-128-gcm" \
        --password "${SS_KEY}" \
        --timeout 300 \
        -U

sleep 3

# ── 6. 验证容器状态 ─────────────────────────────────────────────
log "验证容器运行状态..."
TLS_STATUS=$(docker inspect -f '{{.State.Status}}' shadow-tls 2>/dev/null)
SS_STATUS=$(docker inspect -f '{{.State.Status}}' ss-rust 2>/dev/null)

if [ "$TLS_STATUS" != "running" ]; then
    warn "shadow-tls 状态异常: $TLS_STATUS"
    docker logs shadow-tls 2>&1 | tail -30
fi
if [ "$SS_STATUS" != "running" ]; then
    warn "ss-rust 状态异常: $SS_STATUS"
    docker logs ss-rust 2>&1 | tail -30
fi

# ── 7. 获取服务器公网 IP ────────────────────────────────────────
log "获取公网 IP..."
SERVER_IP=$(curl -s --max-time 10 ipv4.icanhazip.com || \
            curl -s --max-time 10 api.ipify.org || \
            curl -s --max-time 10 ifconfig.me)
[ -z "$SERVER_IP" ] && err "无法获取公网 IP"
log "服务器 IP：$SERVER_IP"

# ── 8. 生成 Shadowrocket 专用节点链接 ──────────────────────────
log "生成节点链接..."

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

SS_LINK="ss://${SS_B64}@${SERVER_IP}:${LISTEN_PORT}?shadow-tls=${STLS_B64}#SS2022_ShadowTLS_HighSpeed"

# ── 9. 发送一键复制格式到飞书 ─────────────────────────────────────
log "推送可一键复制的节点链接到飞书..."
python3 - <<PYEND " "" "card": "content": "div", "elements": "interactive", "lark_md", "msg_type": "tag": "text": "══════════════════════════════════════════════" "部署完成，链接已推送到飞书！" # ### ${SS_LINK}" 'application/json'}) **“复制” --- 10. Exception Icon/图标**，或者长按/双击直接选择整段链接，彻底解决折行和复制不全的问题！ PYEND [ ] ``` as data="json.dumps(payload).encode('utf-8')," e: echo except f"```\n{link}\n```" headers="{'Content-Type':" import json link="${SS_LINK}" log payload="{" print("飞书一键复制卡片推送成功！") print(f"推送失败: req="urllib.request.Request(webhook," timeout="10)" try: urllib.request urllib.request.urlopen(req, webhook="${FEISHU_WEBHOOK}" { {e}") } ── ──────────────────────────────────────────── 一键链接:" 在飞书中收到消息后，链接会被包裹在一个灰色的**代码卡片**中。鼠标移上去，右上角会直接出现一个 推送效果 本地输出汇总>