#!/usr/bin/env bash
set -e

APP_NAME="nodepassdash"
APP_USER="nodepassdash"
INSTALL_DIR="/opt/${APP_NAME}"
SERVICE_NAME="nodepassdash"
DOWNLOAD_URL="https://github.com/NodePassProject/NodePassDash/releases/download/v3.3.1/NodePassDash_Linux_x86_64.tar.gz"

echo "==> 更新软件源并安装依赖..."
sudo apt-get update
sudo apt-get install -y curl wget tar

echo "==> 创建运行用户（如已存在会跳过）..."
if ! id -u "${APP_USER}" >/dev/null 2>&1; then
  sudo useradd -r -s /usr/sbin/nologin "${APP_USER}"
fi

echo "==> 创建安装目录..."
sudo mkdir -p "${INSTALL_DIR}"
sudo chown "${APP_USER}:${APP_USER}" "${INSTALL_DIR}"

cd /tmp

echo "==> 下载 NodePassDash arm64 压缩包..."
wget -O NodePassDash_Linux_arm64.tar.gz "${DOWNLOAD_URL}"

echo "==> 解压文件..."
sudo tar -xzf NodePassDash_Linux_arm64.tar.gz -C "${INSTALL_DIR}"

echo "==> 赋予执行权限..."
sudo chmod +x "${INSTALL_DIR}/nodepassdash"

echo "==> 创建 systemd 服务..."
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

sudo bash -c "cat > ${SERVICE_FILE}" <<EOF
[Unit]
Description=NodePassDash Dashboard
After=network.target

[Service]
Type=simple
User=${APP_USER}
Group=${APP_USER}
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/nodepassdash
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo "==> 重新加载 systemd 配置..."
sudo systemctl daemon-reload

echo "==> 启用并启动服务..."
sudo systemctl enable "${SERVICE_NAME}"
sudo systemctl restart "${SERVICE_NAME}"

echo "==> 完成！默认监听 http://localhost:3000"
echo "查看状态： sudo systemctl status ${SERVICE_NAME}"
echo "查看日志： journalctl -u ${SERVICE_NAME} -f"
