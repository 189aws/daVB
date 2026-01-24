#!/bin/bash

# 1. 创建独立目录
mkdir -p ~/singbox_isolated && cd ~/singbox_isolated

# 2. 创建隔离版 config.json (显式指定 DNS)
cat <<EOT > config.json
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "tag": "google-dns",
        "address": "8.8.8.8",
        "detour": "direct"
      }
    ]
  },
  "inbounds": [
    {
      "type": "shadowsocks",
      "tag": "ss-in",
      "listen": "::",
      "listen_port": 9966,
      "method": "chacha20-ietf-poly1305",
      "password": "AAAACchacha20chacha209AAAAA"
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOT

# 3. 创建桥接版 docker-compose.yml
# 显式映射端口，不再共享宿主机网络栈
cat <<EOT > docker-compose.yml
services:
  sing-box:
    image: ghcr.io/sagernet/sing-box:latest
    container_name: sing-box-isolated
    restart: always
    # 默认就是 bridge 模式，这里通过 ports 映射实现隔离
    ports:
      - "8388:8388/tcp"
      - "8388:8388/udp"
    dns:
      - 8.8.8.8
      - 1.1.1.1
    volumes:
      - ./config.json:/etc/sing-box/config.json
    command: -D /var/lib/sing-box -c /etc/sing-box/config.json run
EOT

# 4. 停止旧容器并启动新容器
docker stop sing-box 2>/dev/null || true
docker rm sing-box 2>/dev/null || true
docker compose up -d

echo "------------------------------------------------"
echo "隔离部署完成！"
echo "模式：Docker Bridge (端口映射)"
echo "容器 DNS：8.8.8.8 (已与宿主机 172.31.0.2 隔离)"
echo "------------------------------------------------"
EOF
