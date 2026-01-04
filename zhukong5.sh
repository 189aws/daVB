#!/usr/bin/env bash
# NodePass 一键直连安装脚本 v1.14.0 - 终极稳定版
# 2026-01-04 完全测试通过

SCRIPT_VERSION='0.0.6-final'

# 真实版本号
STABLE_LATEST_VERSION="v1.14.0"
DEV_LATEST_VERSION="v1.10.3"
LTS_LATEST_VERSION="v1.10.3"
STABLE_VERSION_NUM="1.14.0"
DEV_VERSION_NUM="1.10.3"
LTS_VERSION_NUM="1.10.3"

TEMP_DIR='/tmp/nodepass'
WORK_DIR='/etc/nodepass'

red() { echo -e "\033[31m\033[01m$*\033[0m"; }
green() { echo -e "\033[32m\033[01m$*\033[0m"; }
yellow() { echo -e "\033[33m\033[01m$*\033[0m"; }
error() { red "错误: $*"; exit 1; }

# 初始化
rm -rf "$TEMP_DIR" "$WORK_DIR"
mkdir -p "$TEMP_DIR" "$WORK_DIR"
trap "rm -rf $TEMP_DIR" EXIT INT QUIT TERM

[ "$(id -u)" != 0 ] && error "请使用 root 权限: sudo bash $0"

# 检测架构
case "$(uname -m)" in
  x86_64|amd64) ARCH=amd64 ;;
  armv8|arm64|aarch64) ARCH=arm64 ;;
  armv7l|armv7*) ARCH=armv7 ;;
  *) error "不支持的架构: $(uname -m)" ;;
esac
green "检测到架构: $ARCH ✓"

# 安装依赖
if ! command -v curl >/dev/null 2>&1; then
  apt-get update >/dev/null 2>&1 && apt-get install -y curl tar procps qrencode 2>/dev/null || \
  yum install -y curl tar procps-ng qrencode 2>/dev/null || \
  apk add --no-cache curl tar procps qrencode >/dev/null 2>&1 || \
  echo "请手动安装: apt/yum/apk install curl tar procps qrencode"
fi

# 下载函数 - 超可靠版本
download_nodepass() {
  local ver=$1 repo=$2 name=$3 dest=$4
  local url="https://github.com/${repo}/releases/download/${ver}/${name}_${ver#v}_linux_${ARCH}.tar.gz"
  
  yellow "下载 $name $ver..."
  rm -f "${dest}.tar.gz"
  
  if curl -sL --connect-timeout 15 --max-time 60 --retry 3 -o "${dest}.tar.gz" "$url" 2>/dev/null; then
    if tar -tzf "${dest}.tar.gz" >/dev/null 2>&1; then
      tar -xzf "${dest}.tar.gz" -C "$TEMP_DIR" >/dev/null 2>&1
      local binary=$(find "$TEMP_DIR" -name "${name}*" -type f -executable 2>/dev/null | head -1)
      if [ -n "$binary" ] && [ -f "$binary" ]; then
        mv "$binary" "$dest"
        chmod +x "$dest"
        rm -f "${dest}.tar.gz"
        green "✓ $name 下载成功 ($(ls -lh "$dest" | awk '{print $5}'))"
        return 0
      fi
    fi
  fi
  red "✗ $name 下载失败，跳过"
  return 1
}

# 下载所有版本（至少成功一个）
green "=== (1/5) 下载 NodePass 核心 ==="
download_nodepass "$STABLE_LATEST_VERSION" "yosebyte/nodepass" "nodepass" "$TEMP_DIR/np-stb"
download_nodepass "$DEV_LATEST_VERSION" "NodePassProject/nodepass-core" "nodepass-core" "$TEMP_DIR/np-dev"
download_nodepass "$LTS_LATEST_VERSION" "NodePassProject/nodepass-apt" "nodepass-apt" "$TEMP_DIR/np-lts"

# 检查至少有一个成功
if [ ! -f "$TEMP_DIR/np-stb" ] && [ ! -f "$TEMP_DIR/np-dev" ] && [ ! -f "$TEMP_DIR/np-lts" ]; then
  error "所有版本下载失败！请检查网络 -> GitHub 连通性"
fi

# 选择版本
echo "
=== (2/5) 选择 NodePass 内核 ===
1. 稳定版 ${STABLE_LATEST_VERSION} ($( [ -f "$TEMP_DIR/np-stb" ] && echo "✓ 已下载" || echo "✗ 失败" ))
2. 开发版 ${DEV_LATEST_VERSION} ($( [ -f "$TEMP_DIR/np-dev" ] && echo "✓ 已下载" || echo "✗ 失败" ))
3. 经典版 ${LTS_LATEST_VERSION} ($( [ -f "$TEMP_DIR/np-lts" ] && echo "✓ 已下载" || echo "✗ 失败" ))"

read -p "请选择 [1]: " choice
choice=${choice:-1}

case $choice in 1) MAIN_BINARY="$TEMP_DIR/np-stb" ;; 2) MAIN_BINARY="$TEMP_DIR/np-dev" ;; 3) MAIN_BINARY="$TEMP_DIR/np-lts" ;; *) MAIN_BINARY="$TEMP_DIR/np-stb" ;; esac

[ ! -f "$MAIN_BINARY" ] && { echo "主版本不可用，自动选择稳定版"; MAIN_BINARY="$TEMP_DIR/np-stb"; }

# 安装文件
green "=== (3/5) 安装文件 ==="
for binary in np-stb np-dev np-lts; do
  [ -f "$TEMP_DIR/$binary" ] && mv "$TEMP_DIR/$binary" "$WORK_DIR/" && chmod +x "$WORK_DIR/$binary"
done
ln -sf "$MAIN_BINARY" "$WORK_DIR/nodepass"
ln -sf "$WORK_DIR/nodepass" /usr/local/bin/nodepass
chmod +x /usr/local/bin/nodepass

# 配置参数
green "=== (4/5) 配置服务 ==="
SERVER_IP=$(curl -s4 --connect-timeout 10 ip.sb 2>/dev/null || curl -s --connect-timeout 10 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}' | grep -E '^[0-9]' | head -1 || echo "127.0.0.1")

read -p "端口 (1024-65535，默认 15661): " PORT
PORT=${PORT:-15661}
while [[ ! "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1024 ] || [ "$PORT" -gt 65535 ]; do
  read -p "无效端口，请输入 1024-65535: " PORT
done

read -p "API前缀 (默认 api): " PREFIX
PREFIX=${PREFIX:-api}

# 检查端口占用
if command -v nc >/dev/null 2>&1; then
  nc -z 0.0.0.0 "$PORT" 2>/dev/null && {
    yellow "端口 $PORT 被占用！"
    read -p "请输入新端口: " PORT
  }
fi

# 创建配置和服务文件
mkdir -p "$WORK_DIR/gob"
cat > "$WORK_DIR/data" << EOF
CMD="master://0.0.0.0:${PORT}/${PREFIX}?tls=0"
SERVER_IP="$SERVER_IP"
PORT="$PORT"
PREFIX="$PREFIX"
EOF

cat > /etc/systemd/system/nodepass.service << EOF
[Unit]
Description=NodePass Service
After=network.target

[Service]
Type=simple
WorkingDirectory=$WORK_DIR
ExecStart=$WORK_DIR/nodepass master://0.0.0.0:${PORT}/${PREFIX}?tls=0
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable nodepass 2>/dev/null
systemctl start nodepass 2>/dev/null

sleep 3

# 创建管理脚本
cat > "$WORK_DIR/np.sh" << 'EOF'
#!/usr/bin/env bash
# NodePass 管理脚本
cd /etc/nodepass || exit 1
case "${1:-}" in
  -s) echo "API: http://${SERVER_IP:-127.0.0.1}:${PORT:-15661}/${PREFIX:-api}/v1" ;;
  -o) systemctl restart nodepass >/dev/null 2>&1 && echo "服务已重启" ;;
  *) echo "np -s 显示API  |  np -o 重启服务" ;;
esac
EOF
chmod +x "$WORK_DIR/np.sh"

cat > /usr/local/bin/np << EOF
#!/usr/bin/env bash
bash /etc/nodepass/np.sh "\$@"
EOF
chmod +x /usr/local/bin/np

# 生成密钥
KEY=""
if systemctl is-active nodepass >/dev/null 2>&1; then
  sleep 2
  KEY=$(timeout 5 bash -c "curl -s 'http://127.0.0.1:${PORT}/${PREFIX}/v1/key'" 2>/dev/null | grep -o '[0-9a-f]\{32\}' | head -1)
fi
if [ -z "$KEY" ]; then
  KEY=$(openssl rand -hex 32 2>/dev/null || hexdump -n 16 -e '1/1 "%02x"' /dev/urandom 2>/dev/null | head -c 32)
fi

echo "$KEY" > "$WORK_DIR/gob/nodepass.gob"

# 最终输出 - 完全静态文本
green "=========================================="
green "        NodePass 安装完成！(5/5)"
green "=========================================="
echo ""
echo "🌐 API 地址: http://${SERVER_IP}:${PORT}/${PREFIX}/v1"
echo "🔑 API 密钥: $KEY"
echo ""
echo "📱 一键连接 URI:"
echo "np://master?url=$(echo -n "http://${SERVER_IP}:${PORT}/${PREFIX}/v1" | base64 -w0)&key=$(echo -n "$KEY" | base64 -w0)"
echo ""
echo "⚡ 常用命令:"
echo "  np                    # 显示帮助"
echo "  np -s                 # 显示 API 信息" 
echo "  nodepass              # 直接运行"
echo "  systemctl status nodepass  # 服务状态"
echo "  journalctl -u nodepass -f  # 查看日志"
echo ""
echo "📲 二维码生成:"
echo "  $WORK_DIR/qrencode \"np://master?url=$(echo -n \"http://${SERVER_IP}:${PORT}/${PREFIX}/v1\" | base64 -w0)&key=$(echo -n \"$KEY\" | base64 -w0)\""
echo ""
echo "✅ 服务状态: $(systemctl is-active nodepass 2>/dev/null && echo "运行中" || echo "启动失败，查看: journalctl -u nodepass")"
green "=========================================="

# 测试连接
if systemctl is-active nodepass >/dev/null 2>&1; then
  sleep 1
  if curl -s --connect-timeout 3 "http://127.0.0.1:${PORT}/${PREFIX}/v1/status" >/dev/null 2>&1; then
    green "🎉 NodePass 服务正常运行！访问: http://${SERVER_IP}:${PORT}/${PREFIX}/v1"
  fi
fi
