cat <<'EOF' > ss_isolated.sh
#!/bin/bash

# 1. 强化安装 Docker 和 Docker Compose 插件
echo "正在检查/安装 Docker 环境..."
curl -fsSL https://get.docker.com | bash -s docker
apt-get update && apt-get install -y docker-compose-plugin
systemctl enable --now docker

# 2. 创建并进入目录
mkdir -p ~/singbox_isolated
cd ~/singbox_isolated

# 3. 创建 Sing-box 配置文件 (独立 DNS 设置)
echo "创建隔离版 config.json..."
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
      "listen_port": 8788,
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

# 4. 创建 Docker Compose 配置文件 (桥接模式 + 独立 DNS)
echo "创建隔离版 docker-compose.yml..."
cat <<EOT > docker-compose.yml
services:
  sing-box:
    image: ghcr.io/sagernet/sing-box:latest
    container_name: sing-box-isolated
    restart: always
    # 不再使用 host 模式，使用默认 bridge 模式实现隔离
    ports:
      - "8388:8388/tcp"
      - "8388:8388/udp"
    # 容器系统层面的 DNS 独立
    dns:
      - 8.8.8.8
      - 1.1.1.1
    volumes:
      - ./config.json:/etc/sing-box/config.json
    command: -D /var/lib/sing-box -c /etc/sing-box/config.json run
EOT

# 5. 启动容器
echo "正在启动隔离版 Sing-box..."
# 停止可能存在的同名旧容器
docker compose down 2>/dev/null
docker compose up -d

echo "------------------------------------------------"
echo "部署完成 (网络隔离版)！"
echo "协议：Shadowsocks (SS)"
echo "端口：8788 (已通过 Docker 映射)"
echo "加密：chacha20-ietf-poly1305"
echo "密码：AAAACchacha20chacha209AAAAA"
echo "网络模式：Bridge (已与宿主机网络栈隔离)"
echo "容器 DNS：8.8.8.8"
echo "------------------------------------------------"
EOF

# 赋予权限并执行
chmod +x ss_isolated.sh
./ss_isolated.sh
