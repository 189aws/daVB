#!/bin/bash
set -e==============================================================================基础配置区==============================================================================TG_TOKEN="8896559295:AAE5gr8Rhy0I-E7ah5TGWY7IopiWfHGtQsE"
TG_CHAT_ID="1417748881"自动生成随机配置参数LISTEN_PORT=$(shuf -i 30000-45000 -n 1)      # 外部监听端口 (随机 30000-45000)
SS_KEY=$(openssl rand -base64 16)          # 精确生成 16 字节 Base64 密钥==============================================================================终端输出样式定义RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'log()  { echo -e "${GREEN}[✓]${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }------------------------------------------------------------------------------1. 检查基础环境与 Docker 状态------------------------------------------------------------------------------log "检查系统依赖与 Docker 环境..."
apt-get update -qq && apt-get install -y -qq openssl psmisc python3 curl >/dev/null 2>&1if ! command -v docker &>/dev/null; then
warn "未检测到 Docker，正在自动安装..."
apt-get install -y -qq docker.io
systemctl start docker && systemctl enable docker
log "Docker 安装完成！"
fidocker info &>/dev/null || err "Docker 守护进程未能正常运行，请检查服务状态。"------------------------------------------------------------------------------2. 清理历史容器与端口占用------------------------------------------------------------------------------log "清理历史容器与关联端口..."
docker rm -f ss-rust shadow-tls 2>/dev/null || true
sleep 1
fuser -k ${LISTEN_PORT}/tcp 2>/dev/null || true
sleep 1------------------------------------------------------------------------------3. 启动 Shadowsocks-Rust 容器------------------------------------------------------------------------------info "生成当前部署配置："
info "  - 外部监听端口 : ${LISTEN_PORT}"
info "  - SS 2022 密钥 : ${SS_KEY}"log "启动 Shadowsocks-Rust 容器..."
docker run -d --name ss-rust --restart always --network host ghcr.io/shadowsocks/ssserver-rust:latest ssserver --server-addr "0.0.0.0:${LISTEN_PORT}" \
--encrypt-method "2022-blake3-aes-128-gcm" \
--password "${SS_KEY}" --timeout 300 -Ulog "等待 Shadowsocks 服务启动..."
for i in $(seq 1 15); do
if docker exec ss-rust ss -tlnp 2>/dev/null | grep -q "${LISTEN_PORT}" || ss -tlnp 2>/dev/null | grep -q "${LISTEN_PORT}"; then
log "Shadowsocks 顺利在 0.0.0.0:${LISTEN_PORT} 监听"
break
fi
if [ $i -eq 15 ]; then
warn "服务响应超时，请使用 'docker logs ss-rust' 检查具体错误日志"
docker logs ss-rust 2>&1 | tail -20
fi
sleep 1
done------------------------------------------------------------------------------4. 验证容器运行状态------------------------------------------------------------------------------SS_STATUS=$(docker inspect -f '{{.State.Status}}' ss-rust 2>/dev/null)
if [ "$SS_STATUS" != "running" ]; then
warn "ss-rust 运行状态异常: $SS_STATUS"
docker logs ss-rust 2>&1 | tail -30
fi------------------------------------------------------------------------------5. 获取公网 IP 与生成标准节点链接------------------------------------------------------------------------------log "获取服务器公网 IP 地址..."
SERVER_IP=$(curl -s --max-time 10 ipv4.icanhazip.com || curl -s --max-time 10 api.ipify.org || curl -s --max-time 10 ifconfig.me)
[ -z "$SERVER_IP" ] && err "无法自动获取本机公网 IP"
log "服务器 IP: $SERVER_IP"Base64 构造标准 SS 链接 (无任何插件)SS_B64=$(python3 -c "
import base64
raw = '2022-blake3-aes-128-gcm:${SS_KEY}'
b64 = base64.urlsafe_b64encode(raw.encode()).decode().rstrip('=')
print(b64)
")SS_LINK="ss://${SS_B64}@${SERVER_IP}:${LISTEN_PORT}#SS2022_Standalone"------------------------------------------------------------------------------6. 推送至 Telegram 并打印配置汇总------------------------------------------------------------------------------log "推送节点信息至 Telegram..."
curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" -d "chat_id=${TG_CHAT_ID}" --data-urlencode "text=🚀 单体纯 SS 2022 节点部署成功！节点链接：
${SS_LINK}" >/dev/nullecho ""
echo "════════════════════════════════════════════════════════════"
echo "                部署完成汇总（单体纯 SS 节点）"
echo "════════════════════════════════════════════════════════════"
echo "  服务器 IP   : ${SERVER_IP}"
echo "  监听端口    : ${LISTEN_PORT}"
echo "  加密算法    : 2022-blake3-aes-128-gcm"
echo "  SS 密码     : ${SS_KEY}"
echo "════════════════════════════════════════════════════════════"
echo "  一键节点链接:"
echo "  ${SS_LINK}"
echo "════════════════════════════════════════════════════════════"
echo ""
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""
log "部署完全成功！导入小火箭后，即可在节点设置中找到并开启『代理通过』功能。"
