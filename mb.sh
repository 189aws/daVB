#!/usr/bin/env bash
set -e

APP_NAME="nodepassdash"
APP_USER="nodepassdash"
INSTALL_DIR="/opt/${APP_NAME}"
SERVICE_NAME="nodepassdash"
DOWNLOAD_URL="https://github.com/NodePassProject/NodePassDash/releases/download/v3.3.1/NodePassDash_Linux_x86_64.tar.gz"

FIXED_USER="nodepass"
FIXED_PASS="nodepassnodepass"
BASE_URL="http://localhost:3000"

echo "==> 更新软件源并安装依赖..."
sudo apt-get update
sudo apt-get install -y curl wget tar apache2-utils sqlite3

echo "==> 创建运行用户（如已存在会跳过）..."
if ! id -u "${APP_USER}" >/dev/null 2>&1; then
  sudo useradd -r -s /usr/sbin/nologin "${APP_USER}"
fi

echo "==> 创建安装目录..."
sudo mkdir -p "${INSTALL_DIR}"
sudo chown "${APP_USER}:${APP_USER}" "${INSTALL_DIR}"

cd /tmp
echo "==> 下载 NodePassDash 压缩包..."
wget -O NodePassDash_Linux_x86_64.tar.gz "${DOWNLOAD_URL}"

echo "==> 解压文件..."
sudo tar -xzf NodePassDash_Linux_x86_64.tar.gz -C "${INSTALL_DIR}"

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

echo "==> 启动服务，等待初始化..."
sudo systemctl daemon-reload
sudo systemctl enable "${SERVICE_NAME}"
sudo systemctl start "${SERVICE_NAME}"

for i in $(seq 1 20); do
  sleep 1
  if curl -s "${BASE_URL}/api/auth/login" >/dev/null 2>&1; then
    echo "    服务已就绪（${i}s）"
    break
  fi
  echo "    等待中... ${i}s"
done
sleep 2

echo "==> 生成密码哈希并写入数据库..."
HASH=$(htpasswd -bnBC 10 "" "${FIXED_PASS}" | tr -d ':\n' | sed 's/^\$2y/\$2a/')
sudo sqlite3 "${INSTALL_DIR}/db/database.db" "UPDATE system_configs SET value='${HASH}' WHERE key='admin_password_hash';"
sudo sqlite3 "${INSTALL_DIR}/db/database.db" "UPDATE system_configs SET value='${FIXED_USER}' WHERE key='admin_username';"

echo "==> 重启服务..."
sudo systemctl restart "${SERVICE_NAME}"
sleep 3

echo "==> 验证登录..."
RESULT=$(curl -s -X POST "${BASE_URL}/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"${FIXED_USER}\",\"password\":\"${FIXED_PASS}\"}")
echo "    ${RESULT}"

echo ""
echo "==> 全部完成！"
echo "    访问地址： ${BASE_URL}"
echo "    登录账号： ${FIXED_USER}"
echo "    登录密码： ${FIXED_PASS}"
echo ""
echo "查看状态： sudo systemctl status ${SERVICE_NAME}"
echo "查看日志： journalctl -u ${SERVICE_NAME} -f"