#!/bin/bash

docker rm -f socks5-proxy
# 随机选择内网网段类型
SEGMENT=$((RANDOM % 6))
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
  3)
    SUBNET1=100
    SUBNET2=$((RANDOM % 64 + 64))  # 100.64-127
    SUBNET="$SUBNET1.$SUBNET2.0.0/16"
    GATEWAY="$SUBNET1.$SUBNET2.0.1"
    IP="$SUBNET1.$SUBNET2.$((RANDOM % 254 + 2)).$((RANDOM % 254 + 2))"
    ;;
  4)
    SUBNET1=169
    SUBNET2=254
    SUBNET="$SUBNET1.$SUBNET2.0.0/16"
    GATEWAY="$SUBNET1.$SUBNET2.0.1"
    IP="$SUBNET1.$SUBNET2.$((RANDOM % 254 + 2)).$((RANDOM % 254 + 2))"
    ;;
  5)
    SUBNET1=198
    SUBNET2=$((RANDOM % 2 + 18))  # 198.18-19
    SUBNET="$SUBNET1.$SUBNET2.0.0/16"
    GATEWAY="$SUBNET1.$SUBNET2.0.1"
    IP="$SUBNET1.$SUBNET2.$((RANDOM % 254 + 2)).$((RANDOM % 254 + 2))"
    ;;
esac

# 创建随机网络
NETWORK_NAME="gost-net-$SUBNET1-$SUBNET2"
docker network rm $NETWORK_NAME 2>/dev/null
docker network create --driver bridge --subnet $SUBNET --gateway $GATEWAY $NETWORK_NAME

# 运行容器
docker run -d --restart=always \
  --name socks5-proxy \
  -p 12333:12333 \
  --network $NETWORK_NAME \
  --ip $IP \
  ginuerzh/gost \
  -L "socks5://:12333?udp=true&dns=https://dns.google/dns-query"

echo "Container started with IP: $IP, Gateway: $GATEWAY, Network: $SUBNET"


set -e

install_if_missing() {
    if ! dpkg -s "$1" >/dev/null 2>&1; then
        echo "安装缺少依赖 $1 ..."
        apt update -y
        apt install -y "$1"
    fi
}
install_if_missing iproute2
install_if_missing iptables

IFACE=$(ip route | grep '^default' | awk '{print $5}')
[ -z "$IFACE" ] && { echo "未检测到默认网卡"; exit 1; }

echo "ultra fingerprint 混淆 on $(hostname)"

# 随机种子：基于 hostname、ip、时间、/dev/urandom
HOST=$(hostname)
IP=$(hostname -I | awk '{print $1}')
SEED=$(echo -n "$HOST$IP$(date +%s)$(head -c8 /dev/urandom | base64)" | sha256sum | cut -c1-16)

rand_from_seed() {
    local mod=$1
    echo $(echo "$SEED$RANDOM$(date +%N)" | sha256sum | tr -dc '0-9' | head -c5 | awk -v m=$mod '{print ($1 % m)}')
}

# ========== 超随机循环多次 ==========
LOOP=$((2 + $(rand_from_seed 4)))  # 2~5 次
for ((i=0;i<$LOOP;i++)); do
    # 随机 sysctl
    [ $(( $(rand_from_seed 10) % 2)) -eq 0 ] && sysctl -w net.ipv4.tcp_timestamps=0 || sysctl -w net.ipv4.tcp_timestamps=1
    [ $(( $(rand_from_seed 20) % 2)) -eq 0 ] && sysctl -w net.ipv4.tcp_sack=0 || sysctl -w net.ipv4.tcp_sack=1
    [ $(( $(rand_from_seed 30) % 2)) -eq 0 ] && sysctl -w net.ipv4.tcp_window_scaling=0 || sysctl -w net.ipv4.tcp_window_scaling=1

    # 清理再设置 iptables
    iptables -t mangle -F

    TTL=$((50 + $(rand_from_seed 79)))    # 50~128
    MSS=$((1200 + $(rand_from_seed 260))) # 1200~1460
    TOS=$(rand_from_seed 256)

    echo "[$i] TTL=$TTL MSS=$MSS TOS=0x$(printf '%02x' $TOS)"
    iptables -t mangle -A POSTROUTING -j TTL --ttl-set $TTL
    iptables -t mangle -A PREROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss $MSS
    iptables -t mangle -A OUTPUT -p tcp -j TOS --set-tos $TOS

    sleep_time=$(awk -v min=0.5 -v max=2 'BEGIN{srand(); print min+rand()*(max-min)}')
    sleep $sleep_time
done

echo " ultra fingerprint 已完成 on $(hostname)"
echo "查看: iptables -t mangle -L -v"