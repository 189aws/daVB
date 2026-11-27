#!/usr/bin/env bash
set -euo pipefail

# 若文件意外包含 \r，先清理换行干扰
if grep -q $'\r' "$0" 2>/dev/null; then
  sed -i 's/\r$//' "$0"
  exec bash "$0" "$@"
fi

# ================= Telegram 参数（支持位置参数或环境变量） =================
TG_BOT_TOKEN="${1:-${TG_BOT_TOKEN:-}}"
TG_CHAT_ID="${2:-${TG_CHAT_ID:-}}"
# =====================================================================

rand_port() {
  local exclude="${1:-}"
  local p
  while true; do
    p=$(( (RANDOM * 32768 + RANDOM) % 50001 + 10000 ))
    case " $exclude " in
      *" $p "*) continue ;;
    esac
    if ! ss -tuln 2>/dev/null | awk '{print $5}' | grep -qE "[:.]${p}$"; then
      echo "$p"
      return 0
    fi
  done
}

rand_wg_subnet() {
  local host_nets
  host_nets="$(ip -4 route show 2>/dev/null | tr -d '\r' | awk '{print $1}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+' || true)"

  local oct2 oct3 cand_net cand_srv cand_cli conflict rnet r_prefix c_prefix base
  while true; do
    if (( RANDOM % 2 == 0 )); then
      oct2=$(( RANDOM % 250 + 1 ))
    else
      oct2=$(( RANDOM % 16 + 16 ))
    fi
    oct3=$(( RANDOM % 254 + 1 ))

    if (( oct2 >= 16 && oct2 <= 31 )); then
      cand_net="172.${oct2}.${oct3}.0/24"
    else
      cand_net="10.${oct2}.${oct3}.0/24"
    fi

    base="${cand_net%.0/24}"
    cand_srv="${base}.1/24"
    cand_cli="${base}.2/32"
    c_prefix="${base%.*}"

    conflict=0
    while IFS= read -r rnet; do
      rnet="$(printf '%s' "$rnet" | tr -d '\r\n ')"
      [ -z "$rnet" ] && continue
      r_prefix="${rnet%.*}"
      if [ "$r_prefix" = "$c_prefix" ]; then
        conflict=1
        break
      fi
    done <<EOF
$host_nets
EOF

    if (( conflict == 0 )); then
      printf '%s|%s|%s\n' "$cand_net" "$cand_srv" "$cand_cli"
      return 0
    fi
  done
}

html_escape() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

send_tg_link() {
  local link="$1"
  if [ -z "$TG_BOT_TOKEN" ] || [ -z "$TG_CHAT_ID" ]; then
    echo "[提示] 未提供 TG Bot Token 或 Chat ID，跳过 Telegram 推送。"
    return 0
  fi

  local escaped_link html_text api_url resp
  escaped_link="$(html_escape "$link")"
  html_text="<code>${escaped_link}</code>"
  api_url="https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage"

  resp="$(curl -4 -fsSL --max-time 15 -X POST "$api_url" \
    --data-urlencode "chat_id=${TG_CHAT_ID}" \
    --data-urlencode "parse_mode=HTML" \
    --data-urlencode "text=${html_text}" \
    --data-urlencode "disable_web_page_preview=true" 2>&1)" || {
    echo "[警告] Telegram 消息推送失败: ${resp:-网络或接口异常}"
    return 0
  }

  if echo "$resp" | jq -e '.ok == true' >/dev/null 2>&1; then
    echo "[完成] 已推送节点链接至 Telegram。"
  else
    echo "[警告] Telegram API 返回异常: ${resp}"
  fi
}

# ================= 可选环境变量覆盖（未传则每次随机） =================
PORT="${PORT:-$(rand_port "")}"
SNI="${SNI:-gyym.jp}"
UUID="${UUID:-$(cat /proc/sys/kernel/random/uuid)}"
PRIV_KEY="${PRIV_KEY:-}"
PUB_KEY="${PUB_KEY:-}"
SHORT_ID="${SHORT_ID:-$(openssl rand -hex 4)}"

TUNNEL_MODE="${TUNNEL_MODE:-local_forward}"
LOCAL_TUNNEL_PORT="${LOCAL_TUNNEL_PORT:-$(rand_port "$PORT")}"

WG_IF="${WG_IF:-wg$(( RANDOM % 89 + 10 ))}"
WG_PORT="${WG_PORT:-$(rand_port "$PORT $LOCAL_TUNNEL_PORT")}"

if [ -z "${WG_NET:-}" ] || [ -z "${WG_SRV_IP:-}" ] || [ -z "${WG_CLI_IP:-}" ]; then
  RAND_WG_INFO="$(rand_wg_subnet)"
  [ -z "${WG_NET:-}" ] && WG_NET="$(printf '%s' "$RAND_WG_INFO" | cut -d'|' -f1)"
  [ -z "${WG_SRV_IP:-}" ] && WG_SRV_IP="$(printf '%s' "$RAND_WG_INFO" | cut -d'|' -f2)"
  [ -z "${WG_CLI_IP:-}" ] && WG_CLI_IP="$(printf '%s' "$RAND_WG_INFO" | cut -d'|' -f3)"
fi

TARGET_MTU="${TARGET_MTU:-1500}"
# ====================================================================

[ "$EUID" -ne 0 ] && { echo "请使用 root 运行此脚本"; exit 1; }

echo "[1/5] 安装依赖并开启 BBR / IP 转发..."
apt-get update -y >/dev/null && apt-get install -y curl jq openssl ca-certificates wireguard-tools iptables iproute2 tar >/dev/null

MAIN_IF="$(ip route show default | awk '/default/ {print $5}' | head -n1)"
PRIV_IP="$(ip -4 addr show dev "$MAIN_IF" | awk '/inet / {print $2}' | cut -d/ -f1 | head -n1)"
[ -z "$MAIN_IF" ] || [ -z "$PRIV_IP" ] && { echo "无法获取主网卡或本机私网 IP"; exit 1; }

ip link set dev "$MAIN_IF" mtu "$TARGET_MTU" 2>/dev/null || true

cat >/etc/sysctl.d/99-wg-full.conf <<SYSCTL
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.ip_forward = 1
net.ipv4.tcp_rmem = 4096 65535 16777216
net.ipv4.tcp_wmem = 4096 65535 16777216
SYSCTL
sysctl --system >/dev/null

echo "[2/5] 获取 EC2 公网 IPv4..."
PUB_IP="$(curl -4 -fsSL --max-time 8 https://api.ipify.org || curl -4 -fsSL --max-time 8 https://ifconfig.me)"
[ -z "$PUB_IP" ] && { echo "无法获取公网 IPv4"; exit 1; }

echo "[3/5] 从 GitHub Releases 安装最新版 sing-box..."
ARCH_RAW="$(uname -m)"
case "$ARCH_RAW" in
  x86_64|amd64) SB_ARCH="amd64" ;;
  aarch64|arm64) SB_ARCH="arm64" ;;
  *) echo "不支持的系统架构: $ARCH_RAW"; exit 1 ;;
esac

RELEASE_JSON="$(curl -fsSL --max-time 15 https://api.github.com/repos/SagerNet/sing-box/releases/latest)"
SB_TAG="$(echo "$RELEASE_JSON" | jq -r '.tag_name')"
SB_VER="${SB_TAG#v}"
DOWNLOAD_URL="$(echo "$RELEASE_JSON" | jq -r --arg arch "$SB_ARCH" --arg ver "$SB_VER" \
  '.assets[].browser_download_url | select(endswith("linux-" + $arch + ".tar.gz") and contains($ver))' | head -n1)"
[ -z "$DOWNLOAD_URL" ] && { echo "未能解析到 sing-box 下载链接"; exit 1; }

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
curl -fsSL --max-time 60 "$DOWNLOAD_URL" -o "$TMP_DIR/sing-box.tar.gz"
tar -zxf "$TMP_DIR/sing-box.tar.gz" -C "$TMP_DIR"
BIN_PATH="$(find "$TMP_DIR" -type f -name sing-box | head -n1)"
[ -z "$BIN_PATH" ] && { echo "未找到 sing-box 可执行文件"; exit 1; }
install -m 0755 "$BIN_PATH" /usr/local/bin/sing-box

cat >/etc/systemd/system/sing-box.service <<SERVICE
[Unit]
Description=sing-box service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=on-failure
RestartSec=3s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
SERVICE
systemctl daemon-reload

echo "[4/5] 生成密钥并配置 WireGuard (${WG_IF}) 与 sing-box..."
if [ -z "$PRIV_KEY" ] || [ -z "$PUB_KEY" ]; then
  KEY_PAIR="$(sing-box generate reality-keypair)"
  PRIV_KEY="$(echo "$KEY_PAIR" | awk '/PrivateKey/ {print $2}')"
  PUB_KEY="$(echo "$KEY_PAIR" | awk '/PublicKey/ {print $2}')"
fi

SRV_PRIV="$(wg genkey)"
SRV_PUB="$(echo "$SRV_PRIV" | wg pubkey)"
CLI_PRIV="$(wg genkey)"
CLI_PUB="$(echo "$CLI_PRIV" | wg pubkey)"

mkdir -p /etc/wireguard /etc/sing-box
cat >/etc/wireguard/${WG_IF}.conf <<WGCFG
[Interface]
Address = ${WG_SRV_IP}
ListenPort = ${WG_PORT}
MTU = ${TARGET_MTU}
PrivateKey = ${SRV_PRIV}
PostUp = iptables -t nat -A POSTROUTING -s ${WG_NET} -o ${MAIN_IF} -j MASQUERADE; iptables -A FORWARD -i ${WG_IF} -o ${MAIN_IF} -j ACCEPT; iptables -A FORWARD -i ${MAIN_IF} -o ${WG_IF} -m state --state RELATED,ESTABLISHED -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -s ${WG_NET} -o ${MAIN_IF} -j MASQUERADE; iptables -D FORWARD -i ${WG_IF} -o ${MAIN_IF} -j ACCEPT; iptables -D FORWARD -i ${WG_IF} -o ${WG_IF} -m state --state RELATED,ESTABLISHED -j ACCEPT

[Peer]
PublicKey = ${CLI_PUB}
AllowedIPs = ${WG_CLI_IP}
WGCFG
chmod 600 /etc/wireguard/${WG_IF}.conf
systemctl enable --now wg-quick@${WG_IF}
systemctl restart wg-quick@${WG_IF}

if [ "$TUNNEL_MODE" = "local_forward" ]; then
  cat >/etc/sing-box/config.json <<SBCFG
{
  "log": { "level": "info", "timestamp": true },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "0.0.0.0",
      "listen_port": ${PORT},
      "users": [
        { "uuid": "${UUID}", "flow": "xtls-rprx-vision" }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${SNI}",
        "reality": {
          "enabled": true,
          "handshake": { "server": "${SNI}", "server_port": 443 },
          "private_key": "${PRIV_KEY}",
          "short_id": ["${SHORT_ID}"]
        }
      }
    },
    {
      "type": "socks",
      "tag": "local-tunnel-in",
      "listen": "127.0.0.1",
      "listen_port": ${LOCAL_TUNNEL_PORT}
    }
  ],
  "endpoints": [
    {
      "type": "wireguard",
      "tag": "wg-out",
      "address": ["${WG_CLI_IP}"],
      "private_key": "${CLI_PRIV}",
      "mtu": ${TARGET_MTU},
      "peers": [
        {
          "address": "${PRIV_IP}",
          "port": ${WG_PORT},
          "public_key": "${SRV_PUB}",
          "allowed_ips": ["0.0.0.0/0", "::/0"]
        }
      ]
    }
  ],
  "outbounds": [
    {
      "type": "socks",
      "tag": "to-local-tunnel",
      "server": "127.0.0.1",
      "server_port": ${LOCAL_TUNNEL_PORT}
    },
    {
      "type": "direct",
      "tag": "direct-out"
    }
  ],
  "route": {
    "final": "wg-out",
    "rules": [
      { "inbound": ["vless-in"], "outbound": "to-local-tunnel" },
      { "inbound": ["local-tunnel-in"], "outbound": "wg-out" }
    ]
  }
}
SBCFG
else
  cat >/etc/sing-box/config.json <<SBCFG
{
  "log": { "level": "info", "timestamp": true },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "0.0.0.0",
      "listen_port": ${PORT},
      "users": [
        { "uuid": "${UUID}", "flow": "xtls-rprx-vision" }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${SNI}",
        "reality": {
          "enabled": true,
          "handshake": { "server": "${SNI}", "server_port": 443 },
          "private_key": "${PRIV_KEY}",
          "short_id": ["${SHORT_ID}"]
        }
      }
    }
  ],
  "endpoints": [
    {
      "type": "wireguard",
      "tag": "wg-out",
      "address": ["${WG_CLI_IP}"],
      "private_key": "${CLI_PRIV}",
      "mtu": ${TARGET_MTU},
      "peers": [
        {
          "address": "${PRIV_IP}",
          "port": ${WG_PORT},
          "public_key": "${SRV_PUB}",
          "allowed_ips": ["0.0.0.0/0", "::/0"]
        }
      ]
    }
  ],
  "outbounds": [
    { "type": "direct", "tag": "direct-out" }
  ],
  "route": {
    "final": "wg-out"
  }
}
SBCFG
fi

echo "[5/5] 校验配置并启动服务..."
sing-box check -c /etc/sing-box/config.json
systemctl enable --now sing-box
systemctl restart sing-box

VLESS_LINK="vless://${UUID}@${PUB_IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=safari&pbk=${PUB_KEY}&sid=${SHORT_ID}&type=tcp#EC2-${WG_IF}-MTU${TARGET_MTU}"

printf '%s\n' "$VLESS_LINK"
send_tg_link "$VLESS_LINK"
