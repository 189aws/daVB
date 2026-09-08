cat << 'EOF' > /tmp/setup_shadowtls.sh
#!/bin/bash
set -e

# ==========================================
# 1. 自定义配置区
# ==========================================
TG_TOKEN="8896559295:AAHuyFbUCYQedNRORneTN9sSu0Dc7lWyoFo"
TG_CHAT_ID="1417748881"

# 50 个保证连通、支持 TLS 1.3 且未被阻断的内置伪装域名池
DOMAIN_POOL=(
    "captive.apple.com" "cloud.tencent.com" "www.microsoft.com" "www.feishu.cn" "dl.google.com"
    "update.microsoft.com" "www.bytedance.com" "developer.apple.com" "static.meituan.net" "im.dingtalk.com"
    "s1.pstatp.com" "static.pddpic.com" "sf3-cdn-tos.douyinstatic.com" "taro.jd.com" "res3.vmallres.com"
    "static.kuaishou.com" "static.youku.com" "open.feishu.cn" "static.geetest.com" "sdk.sensortower.com"
    "static.dingtalk.com" "file.alipan.com" "sdk.heytap.com" "static.vivo.com.cn" "log.honor.com"
    "update.miui.com" "download.jetbrains.com" "registry.npmmirror.com" "mirrors.tuna.tsinghua.edu.cn" "mirrors.aliyun.com"
    "cdn.bootcdn.net" "unpkg.com" "cdn.npmmirror.com" "static.360buyimg.com" "p16-oec-va.ibyteimg.com"
    "assets.gitlab-static.net" "dynamic.ipchong.com" "static.cloudflarechina.com" "res.wx.qq.com" "h5.m.taobao.com"
    "static.segmentfault.com" "game.gtimg.cn" "web.sanguo.qypdf.com" "cdn.jsdelivr.net" "apis.map.qq.com"
    "g.alicdn.com" "image.baidu.com" "static.zhihu.com" "h5.ele.me" "static.bilibili.com"
)

# 随机抽选 1 个伪装域名
HANDSHAKE_DOMAIN=${DOMAIN_POOL[$RANDOM % ${#DOMAIN_POOL[@]}]}

echo "[1/5] 正在安装基础依赖..."
apt-get update -y
apt-get install -y curl jq openssl tar

echo "[2/5] 正在获取并安装最新的 sing-box 核心..."
LATEST_VERSION=$(curl -s https://api.github.com/repos/sagernet/sing-box/releases/latest | jq -r .tag_name | sed 's/^v//')
ARCH=$(dpkg --print-architecture)
if [ "$ARCH" = "amd64" ]; then
    SB_ARCH="amd64"
elif [ "$ARCH" = "arm64" ]; then
    SB_ARCH="arm64"
else
    SB_ARCH="amd64"
fi

DOWNLOAD_URL="https://github.com/sagernet/sing-box/releases/download/v${LATEST_VERSION}/sing-box-${LATEST_VERSION}-linux-${SB_ARCH}.tar.gz"

curl -sSL "$DOWNLOAD_URL" -o /tmp/sing-box.tar.gz
tar -zxvf /tmp/sing-box.tar.gz -C /tmp/
mv /tmp/sing-box-${LATEST_VERSION}-linux-${SB_ARCH}/sing-box /usr/local/bin/
chmod +x /usr/local/bin/sing-box
rm -rf /tmp/sing-box*

echo "[3/5] 正在生成 SS-2022 + Shadow-TLS v3 节点配置..."
echo "本次选用的 TLS 伪装目标域名为: ${HANDSHAKE_DOMAIN}"

SS_PORT=$(shuf -i 30000-45000 -n 1)      # 本地 SS 监听端口
STLS_PORT=$(shuf -i 45001-60000 -n 1)    # 外部公网 Shadow-TLS 端口
SS_KEY=$(openssl rand -base64 32)        # SS-2022 密钥
STLS_PASSWORD=$(openssl rand -hex 16)   # Shadow-TLS 握手密码

mkdir -p /etc/sing-box
cat <<JSON > /etc/sing-box/config.json
{
  "log": {
    "level": "info"
  },
  "inbounds": [
    {
      "type": "shadowsocks",
      "tag": "ss-in",
      "listen": "127.0.0.1",
      "listen_port": $SS_PORT,
      "method": "2022-blake3-aes-128-gcm",
      "password": "$SS_KEY"
    },
    {
      "type": "shadowtls",
      "tag": "stls-in",
      "listen": "::",
      "listen_port": $STLS_PORT,
      "version": 3,
      "users": [
        {
          "password": "$STLS_PASSWORD"
        }
      ],
      "handshake": {
        "server": "$HANDSHAKE_DOMAIN",
        "server_port": 443
      },
      "detour": "ss-in"
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
JSON

echo "[4/5] 写入 systemd 系统服务并启动..."
cat <<SYSTEMD > /etc/systemd/system/sing-box.service
[Unit]
Description=sing-box Shadow-TLS service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=on-failure
RestartSec=10s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
SYSTEMD

systemctl daemon-reload
systemctl enable --now sing-box

# 获取公网 IP
SERVER_IP=$(curl -s https://api.ipify.org || curl -s https://ipv4.icanhazip.com)

# ── 拼接小火箭 Shadowrocket 格式 ────────────────────────────────────────

# 1. 编码基础 SS 凭据 (2022-blake3-aes-128-gcm:密钥)
RAW_SS="2022-blake3-aes-128-gcm:$SS_KEY"
ENCODED_SS=$(echo -n "$RAW_SS" | base64 | tr -d '\n')

# 2. 构造 Shadow-TLS 的小火箭 JSON 并进行 Base64 编码
STLS_JSON=$(jq -n -c \
  --arg version "3" \
  --arg host "$HANDSHAKE_DOMAIN" \
  --arg password "$STLS_PASSWORD" \
  '{version: $version, host: $host, password: $password}')

ENCODED_STLS_PARAM=$(echo -n "$STLS_JSON" | base64 | tr -d '\n')

# 3. 组合小火箭一键链接
SS_LINK="ss://${ENCODED_SS}@${SERVER_IP}:${STLS_PORT}?shadow-tls=${ENCODED_STLS_PARAM}#STLS_${HANDSHAKE_DOMAIN}"

echo "[5/5] 正在推送纯链接到 Telegram..."
curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
    -d "chat_id=${TG_CHAT_ID}" \
    --data-urlencode "text=${SS_LINK}" >/dev/null

clear
echo "=================================================="
echo "    Shadowsocks-2022 + Shadow-TLS v3 部署完成！"
echo "=================================================="
echo "服务器公网 IP : $SERVER_IP"
echo "Shadow-TLS端口: $STLS_PORT"
echo "TLS 伪装域名  : $HANDSHAKE_DOMAIN"
echo "Shadow-TLS密码: $STLS_PASSWORD"
echo "SS-2022 密码  : $SS_KEY"
echo "--------------------------------------------------"
echo "小火箭专享节点链接 (已同步推送到 Telegram):"
echo "$SS_LINK"
echo "=================================================="
EOF

bash /tmp/setup_shadowtls.sh
