#!/bin/bash
# ═══════════════════════════════════════════════
#   VLESS + Reality + TProxy 一键部署脚本
# ═══════════════════════════════════════════════

# ── 配置区（按需修改）──────────────────────────
TG_TOKEN="8218154265:AAGotrfTH6mNxkMLPqV8HeOAqKWlcSkHVu8"
TG_CHAT_ID="1792396794"
DEST_SNI="www.bing.com"
LISTEN_PORT=443
# ────────────────────────────────────────────────

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()   { echo -e "${GREEN}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

[ "$EUID" -ne 0 ] && error "请以 root 权限运行"

log "═══════════════════════════════════════════"
log "   VLESS+Reality 服务端 + NAT特征消除"
log "═══════════════════════════════════════════"

# ── 1. 检查内核模块 ──────────────────────────────
log "[1/7] 检查内核模块..."
modprobe xt_TPROXY    2>/dev/null || error "内核不支持 xt_TPROXY"
modprobe xt_mark      2>/dev/null
modprobe nf_conntrack 2>/dev/null
log "内核模块 OK ✓"

# ── 2. 内核参数优化 ──────────────────────────────
log "[2/7] 优化内核参数..."
cat > /etc/sysctl.d/99-vless.conf <<'EOF'
net.ipv4.ip_forward = 1
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_default_ttl = 64
net.netfilter.nf_conntrack_max = 1048576
net.netfilter.nf_conntrack_tcp_timeout_established = 7440
net.ipv4.ip_local_port_range = 1024 65535
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
EOF
sysctl --system > /dev/null
log "内核参数 OK ✓"

# ── 3. 安装 sing-box ─────────────────────────────
log "[3/7] 安装 sing-box..."
if command -v sing-box &>/dev/null; then
  log "已安装: $(sing-box version | head -1)"
else
  ARCH=$(uname -m)
  [ "$ARCH" = "x86_64" ]  && ARCH="amd64"
  [ "$ARCH" = "aarch64" ] && ARCH="arm64"
  LATEST=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest \
    | grep tag_name | cut -d'"' -f4 | tr -d 'v')
  [ -z "$LATEST" ] && error "无法获取版本号"
  curl -Lo /tmp/sing-box.tar.gz \
    "https://github.com/SagerNet/sing-box/releases/latest/download/sing-box-${LATEST}-linux-${ARCH}.tar.gz" \
    || error "下载失败"
  tar -xzf /tmp/sing-box.tar.gz -C /tmp
  mv /tmp/sing-box-*/sing-box /usr/local/bin/
  chmod +x /usr/local/bin/sing-box
  rm -rf /tmp/sing-box*
  command -v sing-box &>/dev/null || error "安装失败"
  log "安装成功: $(sing-box version | head -1)"
fi

# ── 4. 生成密钥 ──────────────────────────────────
log "[4/7] 生成密钥..."
mkdir -p /etc/sing-box
UUID=$(sing-box generate uuid)
KEYS=$(sing-box generate reality-keypair)
PRIVATE_KEY=$(echo "$KEYS" | awk '/PrivateKey/ {print $2}')
PUBLIC_KEY=$(echo "$KEYS"  | awk '/PublicKey/  {print $2}')
SHORT_ID=$(openssl rand -hex 8)
PUBLIC_IP=$(curl -s --max-time 5 https://api64.ipify.org \
  || curl -s --max-time 5 https://ifconfig.me)

[ -z "$UUID" ]        && error "UUID 生成失败"
[ -z "$PRIVATE_KEY" ] && error "密钥生成失败"
[ -z "$PUBLIC_IP" ]   && error "获取公网IP失败"
log "公网IP: ${PUBLIC_IP} ✓"

# ── 5. 用 python3 生成配置文件（彻底避免引号冲突）──
log "[5/7] 写入配置文件..."
python3 - <<PYEOF
import json

config = {
    "log": {
        "level": "info",
        "timestamp": True
    },
    "inbounds": [
        {
            "type": "vless",
            "tag": "vless-in",
            "listen": "::",
            "listen_port": ${LISTEN_PORT},
            "users": [
                {
                    "uuid": "${UUID}",
                    "flow": "xtls-rprx-vision"
                }
            ],
            "tls": {
                "enabled": True,
                "server_name": "${DEST_SNI}",
                "reality": {
                    "enabled": True,
                    "handshake": {
                        "server": "${DEST_SNI}",
                        "server_port": 443
                    },
                    "private_key": "${PRIVATE_KEY}",
                    "short_id": ["${SHORT_ID}"]
                }
            }
        }
    ],
    "outbounds": [
        {"type": "direct", "tag": "direct"}
    ]
}

with open("/etc/sing-box/config.json", "w") as f:
    json.dump(config, f, indent=2, ensure_ascii=False)

print("配置文件写入成功")
PYEOF

sing-box check -c /etc/sing-box/config.json || error "配置文件语法错误"
log "配置文件 OK ✓"

# ── 6. NAT特征消除规则 ───────────────────────────
log "[6/7] 部署 NAT 特征消除规则..."
cat > /etc/sing-box/nat-stealth.sh <<'RULES'
#!/bin/bash
iptables -t mangle -F

# TTL 标准化
iptables -t mangle -A POSTROUTING -j TTL --ttl-set 64
# MSS 锁定
iptables -t mangle -A POSTROUTING -p tcp \
  --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1460
# DSCP 清零
iptables -t mangle -A POSTROUTING -j DSCP --set-dscp 0
RULES
chmod +x /etc/sing-box/nat-stealth.sh
bash /etc/sing-box/nat-stealth.sh
log "NAT特征消除 OK ✓"

# ── 7. systemd 服务 ──────────────────────────────
log "[7/7] 配置系统服务..."

command -v ufw &>/dev/null && ufw allow ${LISTEN_PORT}/tcp > /dev/null

cat > /etc/systemd/system/sing-box.service <<'EOF'
[Unit]
Description=sing-box VLESS Reality Service
After=network.target

[Service]
ExecStartPre=/etc/sing-box/nat-stealth.sh
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
ExecStopPost=/sbin/iptables -t mangle -F
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576
AmbientCapabilities=CAP_NET_BIND_SERVICE CAP_NET_ADMIN

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable sing-box
systemctl restart sing-box
sleep 3

systemctl is-active --quiet sing-box || {
  journalctl -u sing-box -n 30 --no-pager
  error "sing-box 启动失败"
}
log "服务运行正常 ✓"

# ── 推送 Telegram ────────────────────────────────
REMARK="AWS-Reality"
VLESS_LINK="vless://${UUID}@${PUBLIC_IP}:${LISTEN_PORT}?encryption=none&security=reality&sni=${DEST_SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&flow=xtls-rprx-vision#${REMARK}"

TG_MSG="✅ VLESS+Reality 节点部署成功

🌐 地址: ${PUBLIC_IP}
🔌 端口: ${LISTEN_PORT}
🔑 UUID: ${UUID}
🏠 SNI: ${DEST_SNI}
🔐 PublicKey: ${PUBLIC_KEY}
🆔 ShortID: ${SHORT_ID}

📱 一键导入:
${VLESS_LINK}"

TG_RESP=$(curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
  -H "Content-Type: application/json" \
  -d "$(python3 -c "
import json, sys
msg = sys.stdin.read()
print(json.dumps({'chat_id': '${TG_CHAT_ID}', 'text': msg}))
" <<< "$TG_MSG")")

echo "$TG_RESP" | grep -q '"ok":true' \
  && log "Telegram 推送成功 ✓" \
  || log "Telegram 推送失败，响应: ${TG_RESP}"

# ── 完成 ─────────────────────────────────────────
echo ""
log "═══════════════════════════════════════════"
log "            部署完成！"
log "═══════════════════════════════════════════"
echo ""
echo -e "${GREEN}节点链接：${NC}"
echo "$VLESS_LINK"
echo ""
echo -e "${YELLOW}Clash 配置：${NC}"
cat <<CLASH
proxies:
  - name: AWS-Reality
    type: vless
    server: ${PUBLIC_IP}
    port: ${LISTEN_PORT}
    uuid: ${UUID}
    network: tcp
    tls: true
    udp: true
    flow: xtls-rprx-vision
    servername: ${DEST_SNI}
    reality-opts:
      public-key: ${PUBLIC_KEY}
      short-id: ${SHORT_ID}
    client-fingerprint: chrome
CLASH
echo ""
echo -e "${YELLOW}常用命令：${NC}"
echo "  journalctl -u sing-box -f      # 实时日志"
echo "  systemctl restart sing-box     # 重启"
echo "  iptables -t mangle -L -n -v    # 查看规则"