cat <<'EOF' > ss.sh
#!/bin/bash

# 1. 安装 Docker
echo "正在安装 Docker..."
curl -fsSL https://get.docker.com | bash -s docker
systemctl enable --now docker

# 2. 创建目录
mkdir -p ~/singbox
cd ~/singbox

# 3. 创建 Sing-box 配置文件
echo "创建 config.json..."
cat <<EOT > config.json
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "shadowsocks",
      "tag": "ss-in",
      "listen": "::",
      "listen_port": 8388,
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

# 4. 创建 Docker Compose 配置文件
echo "创建 docker-compose.yml..."
cat <<EOT > docker-compose.yml
services:
  sing-box:
    image: ghcr.io/sagernet/sing-box:latest
    container_name: sing-box
    restart: always
    network_mode: host
    volumes:
      - ./config.json:/etc/sing-box/config.json
    command: -D /var/lib/sing-box -c /etc/sing-box/config.json run
EOT

# 5. 启动容器
echo "正在启动 Sing-box..."
docker compose up -d

echo "------------------------------------------------"
echo "部署完成！"
echo "协议：Shadowsocks (SS)"
echo "端口：8388"
echo "加密：chacha20-ietf-poly1305"
echo "密码：AAAACchacha20chacha209AAAAA"
echo "------------------------------------------------"
EOF

# 给予执行权限并运行
chmod +x ss.sh
./ss.sh
