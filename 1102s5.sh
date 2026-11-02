#!/bin/bash
set -e

# 确保以 root 权限运行
[ "$EUID" -ne 0 ] && { echo "请使用 root 权限运行此脚本 (sudo bash)"; exit 1; }

echo "=== 1. 清理错误的软件源并安装 Docker 依赖 ==="
rm -f /etc/apt/sources.list.d/docker.list
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release

# 添加 Docker 官方 GPG 密钥和正确的 Debian (bookworm) 软件源
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  bookworm stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "=== 2. 安装 Docker 及运行时 ==="
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable --now docker

echo "=== 3. 清理旧容器并创建安全网络 ==="
docker rm -f socks5-proxy 2>/dev/null || true

# 随机选择安全的内网网段类型 (排除冲突的 169.254 和 100.64)
SEGMENT=$((RANDOM % 3))
case $SEGMENT in
  0)
    SUBNET1=10
    SUBNET2=$((RANDOM % 256))
    SUBNET="$SUBNET1.$SUBNET2.0.0/16"
    GATEWAY="$SUBNET1.$SUBNET2.0.1"
    IP="$SUBNET1.$SUBNET2.$((RANDOM % 254 + 2)).$((RANDOM % 254 + 2))"
    ;;
  1)
    SUBNET1=172
    SUBNET2=$((RANDOM % 16 + 16))  # 172.16-31
    SUBNET="$SUBNET1.$SUBNET2.0.0/16"
    GATEWAY="$SUBNET1.$SUBNET2.0.1"
    IP="$SUBNET1.$SUBNET2.$((RANDOM % 254 + 2)).$((RANDOM % 254 + 2))"
    ;;
  2)
    SUBNET1=192
    SUBNET2=168
    SUBNET="$SUBNET1.$SUBNET2.0.0/16"
    GATEWAY="$SUBNET1.$SUBNET2.0.1"
    IP="$SUBNET1.$SUBNET2.$((RANDOM % 254 + 2)).$((RANDOM % 254 + 2))"
    ;;
esac

NETWORK_NAME="gost-net-$SUBNET1-$SUBNET2"
docker network rm $NETWORK_NAME 2>/dev/null || true
docker network create --driver bridge --subnet "$SUBNET" --gateway "$GATEWAY" "$NETWORK_NAME"

echo "=== 4. 启动 Gost SOCKS5 代理容器 ==="
docker run -d --restart=always \
  --name socks5-proxy \
  -p 12333:12333 \
  --network "$NETWORK_NAME" \
  --ip "$IP" \
  ginuerzh/gost \
  -L "socks5://:12333?udp=true&dns=https://1.1.1.2/dns-query"

echo "Container started with IP: $IP, Gateway: $GATEWAY, Network: $SUBNET"

echo "=== 5. 应用 ultra fingerprint 混淆配置 ==="
apt-get install -y iproute2 iptables

HOST=$(hostname)
HOST_IP=$(hostname -I | awk '{print $1}')
SEED=$(echo -n "$HOST$HOST_IP$(date +%s)$(head -c8 /dev/urandom | base64)" | sha256sum | cut -c1-16)

rand_from_seed() {
    local mod=$1
    echo $(echo "$SEED$RANDOM$(date +%N)" | sha256sum | tr -dc '0-9' | head -c5 | awk -v m=$mod '{print ($1 % m)}')
}

LOOP=$((2 + $(rand_from_seed 4)))
for ((i=0; i<LOOP; i++)); do
    [ $(( $(rand_from_seed 10) % 2)) -eq 0 ] && sysctl -w net.ipv4.tcp_timestamps=0 || sysctl -w net.ipv4.tcp_timestamps=1
    [ $(( $(rand_from_seed 20) % 2)) -eq 0 ] && sysctl -w net.ipv4.tcp_sack=0 || sysctl -w net.ipv4.tcp_sack=1
    [ $(( $(rand_from_seed 30) % 2)) -eq 0 ] && sysctl -w net.ipv4.tcp_window_scaling=0 || sysctl -w net.ipv4.tcp_window_scaling=1

    iptables -t mangle -F

    TTL=$((50 + $(rand_from_seed 79)))
    MSS=$((1200 + $(rand_from_seed 260)))
    TOS=$(rand_from_seed 256)

    echo "[$i] TTL=$TTL MSS=$MSS TOS=0x$(printf '%02x' $TOS)"
    iptables -t mangle -A POSTROUTING -j TTL --ttl-set $TTL
    iptables -t mangle -A PREROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss $MSS
    iptables -t mangle -A OUTPUT -p tcp -j TOS --set-tos $TOS

    sleep_time=$(awk -v min=0.5 -v max=2 'BEGIN{srand(); print min+rand()*(max-min)}')
    sleep $sleep_time
done

echo "ultra fingerprint 已完成 on $(hostname)"
echo "查看: iptables -t mangle -L -v"
