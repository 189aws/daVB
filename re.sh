#!/bin/bash

# 检查是否为 Root 权限
if [ "$EUID" -ne 0 ]; then 
  echo "请使用 root 权限运行此脚本。"
  exit
fi

echo "正在开始安装 REALM 并配置转发..."

# 1. 自动识别系统架构
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    URL="https://github.com/zhboner/realm/releases/latest/download/realm-x86_64-unknown-linux-musl.tar.gz"
elif [ "$ARCH" = "aarch64" ]; then
    URL="https://github.com/zhboner/realm/releases/latest/download/realm-aarch64-unknown-linux-musl.tar.gz"
else
    echo "暂不支持的架构: $ARCH"
    exit 1
fi

# 2. 安装依赖并下载 REALM
apt-get update && apt-get install -y wget tar
cd /usr/local/bin
wget -O realm.tar.gz $URL
tar -xvf realm.tar.gz
chmod +x realm
rm realm.tar.gz

# 3. 创建配置目录和文件
mkdir -p /etc/realm
cat <<EOF > /etc/realm/config.toml
[[endpoints]]
listen = "0.0.0.0:19555"
remote = "52.41.71.14:20092"
EOF

# 4. 写入 Systemd 服务
cat <<EOF > /etc/systemd/system/realm.service
[Unit]
Description=Realm Port Forwarding Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/realm -c /etc/realm/config.toml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 5. 开启内核转发 (如果是跨机转发，建议开启)
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -p
fi

# 6. 尝试放行防火墙 (针对常见防火墙)
ufw allow 19555/tcp >/dev/null 2>&1
ufw allow 19555/udp >/dev/null 2>&1
firewall-cmd --permanent --add-port=19555/tcp >/dev/null 2>&1
firewall-cmd --permanent --add-port=19555/udp >/dev/null 2>&1
firewall-cmd --reload >/dev/null 2>&1

# 7. 启动并设置开机自启
systemctl daemon-reload
systemctl enable realm
systemctl restart realm

echo "------------------------------------------------"
echo "恭喜！REALM 转发配置成功。"
echo "本机监听端口: 19555"
echo "转发至目标: 52.41.71.14:20092"
echo "可以通过 'systemctl status realm' 查看运行状态。"
echo "------------------------------------------------"