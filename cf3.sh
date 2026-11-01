#!/bin/sh
set -e
cd /home

# ==========================================
# 1. 美西 (us-west-2) 优化的高性能/隐私 DNS 池 (共10组)
# ==========================================
DNS_POOL=(
    "1.1.1.2 1.0.0.2"             # 1. Cloudflare (安全恶意拦截)
    "9.9.9.9 149.112.112.112"     # 2. Quad9 (安全防护优先)
    "94.140.14.14 94.140.15.15"   # 3. AdGuard DNS (去广告隐私)
    "8.8.8.8 8.8.4.4"             # 4. Google Public DNS (美西直连极快)
    "208.67.222.222 208.67.220.220" # 5. OpenDNS (Cisco 安全稳定)
    "76.76.19.19 76.76.2.0"       # 6. Alternate DNS
    "64.6.64.6 64.6.65.6"         # 7. Verisign Public DNS
    "77.88.8.8 77.88.8.1"         # 9. Yandex.DNS (安全模式)
    "185.228.168.9 185.228.169.9" # 10. CleanBrowsing (成人内容过滤/安全)
)

# 随机从池中挑选一组 DNS
SELECTED_DNS=$(printf "%s\n" "${DNS_POOL[@]}" | shuf -n 1)
DNS1=$(echo "$SELECTED_DNS" | awk '{print $1}')
DNS2=$(echo "$SELECTED_DNS" | awk '{print $2}')

echo "===> 本次在美西机房随机抽选的 DNS: $DNS1 和 $DNS2"

# ==========================================
# 2. 写入 systemd-resolved 配置
# ==========================================
sudo mkdir -p /etc/systemd/resolved.conf.d
sudo tee /etc/systemd/resolved.conf.d/doh.conf > /dev/null <<EOF
[Resolve]
DNS=$DNS1 $DNS2
LLMNR=no
DNSOverTLS=yes
EOF

sudo systemctl restart systemd-resolved
sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf

# ==========================================
# 3. 自动识别当前网卡并应用 (适配 AWS 的 ens5/eth0 等)
# ==========================================
DEFAULT_INTERFACE=$(ip -4 route show default | awk '{print $5}' | head -n1)

if [ -n "$DEFAULT_INTERFACE" ]; then
    echo "===> 检测到当前网卡: $DEFAULT_INTERFACE，正在绑定 DNS..."
    sudo resolvectl dns "$DEFAULT_INTERFACE" "$DNS1" "$DNS2"
else
    echo "===> 未能自动检测到默认网卡，跳过 resolvectl 绑定"
fi

sudo systemctl restart systemd-resolved

# ==========================================
# 4. 输出当前状态验证
# ==========================================
resolvectl status
