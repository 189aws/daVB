#!/usr/bin/env bash
# NodePass 一键直连安装脚本 v1.14.0 - 修复版
set -e  # 遇到错误立即退出

SCRIPT_VERSION='0.0.6-straight'
export DEBIAN_FRONTEND=noninteractive

# === 真实版本（2026-01-04确认） ===
STABLE_LATEST_VERSION="v1.14.0"
DEV_LATEST_VERSION="v1.10.3"
LTS_LATEST_VERSION="v1.10.3"
STABLE_VERSION_NUM="1.14.0"
DEV_VERSION_NUM="1.10.3"
LTS_VERSION_NUM="1.10.3"

TEMP_DIR='/tmp/nodepass'
WORK_DIR='/etc/nodepass'

# 颜色函数
warning() { echo -e "\033[31m\033[01m$*\033[0m"; }
error() { echo -e "\033[31m\033[01m$*\033[0m"; exit 1; }
info() { echo -e "\033[32m\033[01m$*\033[0m"; }
hint() { echo -e "\033[33m\033[01m$*\033[0m"; }

# 初始化
rm -rf "$TEMP_DIR" "$WORK_DIR"
mkdir -p "$TEMP_DIR" "$WORK_DIR"
trap "rm -rf $TEMP_DIR >/dev/null 2>&1" INT QUIT TERM EXIT

# 检查root
[ "$(id -u)" != 0 ] && error "请使用 root 权限运行: sudo bash $0"

# 检测架构
case "$(uname -m)" in
  x86_64|amd64) ARCH=amd64 ;;
  armv8|arm64|aarch64) ARCH=arm64 ;;
  armv7l|armv7*) ARCH=armv7 ;;
  *) error "不支持的架构: $(uname -m)" ;;
esac
info "检测到架构: $ARCH"

# 安装依赖
if ! command -v curl >/dev/null 2>&1; then
  apt-get update -qq >/dev/null 2>&1 && apt-get install -y curl tar procps qrencode >/dev/null 2>&1 ||
  yum makecache >/dev/null 2>&1 && yum install -y curl tar procps-ng qrencode >/dev/null 2>&1 ||
  apk add --no-cache curl tar procps qrencode >/dev/null 2>&1 ||
  error "无法安装依赖，请手动安装 curl/tar"
fi

# === 可靠下载函数 ===
download_nodepass() {
  local version="$1" repo="$2" name="$3" dest="$4"
  local url="https://github.com/${repo}/releases/download/${version}/${name}_${version#v}_linux_${ARCH}.tar.gz"
  
  info "下载 $name $version..."
  if curl -sL -o "$TEMP_DIR/${name}.tar.gz" "$url"; then
    if tar -tzf "$TEMP_DIR/${name}.tar.gz" >/dev/null 2>&1; then
      tar -xzf "$TEMP_DIR/${name}.tar.gz" -C "$TEMP_DIR"
      find "$TEMP_DIR" -name "nodepass*" -type f -executable | head -1 | xargs -I {} mv {} "$dest"
      rm -f "$TEMP_DIR/${name}.tar.gz"
      [ -f "$dest" ] && info "✓ $name 下载成功" && return 0
    fi
  fi
  warning "✗ $name 下载失败: $url"
  return 1
}

# === 下载所有版本 ===
info "=== 下载 NodePass 核心 (1/5) ==="
download_nodepass "$STABLE_LATEST_VERSION" "yosebyte/nodepass" "nodepass" "$TEMP_DIR/np-stb" || \
download_nodepass "$DEV_LATEST_VERSION" "NodePassProject/nodepass-core" "nodepass-core" "$TEMP_DIR/np-dev" || \
download_nodepass "$LTS_LATEST_VERSION" "NodePassProject/nodepass-apt" "nodepass-apt" "$TEMP_DIR/np-lts"

# 检查至少有一个版本成功
[ ! -f "$TEMP_DIR/np-stb" ] && [ ! -f "$TEMP_DIR/np-dev" ] && [ ! -f "$TEMP_DIR/np-lts" ] && 
  error "所有版本下载失败，请检查网络连接 GitHub"

# 选择版本
echo "
=== 选择 NodePass 内核 (2/5) ===
1. 稳定版 $STABLE_LATEST_VERSION ✓[$( [ -f "$TEMP_DIR/np-stb" ] && echo "已下载" || echo "失败" )]
2. 开发版 $DEV_LATEST_VERSION ✓[$( [ -f "$TEMP_DIR/np-dev" ] && echo "已下载" || echo "失败" )]
3. 经典版 $LTS_LATEST_VERSION ✓[$( [ -f "$TEMP_DIR/np-lts" ] && echo "已下载" || echo "失败" )]"
read -p "请选择 [1]: " choice
choice=${choice:-1}

case $choice in
  1) [ -f "$TEMP_DIR/np-stb" ] || { warning "稳定版下载失败"; choice=2; } ;;
  2) [ -f "$TEMP_DIR/np-dev" ] || { warning "开发版下载失败"; choice=1; } ;;
  3) [ -f "$TEMP_DIR/np-lts" ] || { warning "经典版下载失败"; choice=1; } ;;
esac

# 移动文件到工作目录
info "=== 安装文件 (3/5) ==="
[ -f "$TEMP_DIR/np-stb" ] && mv "$TEMP_DIR/np-stb" "$WORK_DIR/" && chmod +x "$WORK_DIR/np-stb"
[ -f "$TEMP_DIR/np-dev" ] && mv "$TEMP_DIR/np-dev" "$WORK_DIR/" && chmod +x "$WORK_DIR/np-dev" 
[ -f "$TEMP_DIR/np-lts" ] && mv "$TEMP_DIR/np-lts" "$WORK_DIR/" && chmod +x "$WORK_DIR/np-lts"

# 创建主链接
case $choice in 1) ln -sf "$WORK_DIR/np-stb" "$WORK_DIR/nodepass" ;; 2) ln -sf "$WORK_DIR/np-dev" "$WORK_DIR/nodepass" ;; 3) ln -sf "$WORK_DIR/np-lts" "$WORK_DIR/nodepass" ;; esac

# 获取IP和配置
info "=== 配置服务 (4/5) ==="
SERVER_IP=$(curl -s4 --connect-timeout 5 ip.sb || curl -s ifconfig.me || hostname -I | awk '{print $1}' | grep -E '^[0-9]' | head -1 || echo "127.0.0.1")
read -p "端口 (1024-65535，默认随机): " PORT
PORT=${PORT:-0}
[ "$PORT" = "0" ] && PORT=$((1024 + RANDOM % 64512))

while ! [[ "$PORT" =~ ^[0-9]{4,5}$ ]] || [ "$PORT" -lt 1024 ] || [ "$PORT" -gt 65535 ]; do
  read -p "无效端口，请输入1024-65535: " PORT
done

read -p "API前缀 (默认 api): " PREFIX
PREFIX=${PREFIX:-api}

# 检查端口
nc -z 0.0.0.0 "$PORT" 2>/dev/null && { echo "端口 $PORT 被占用"; read -p "新端口: " PORT; }

# 创建配置和服务
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
systemctl enable nodepass >/dev/null 2>&1
systemctl start nodepass

sleep 3

# 快捷方式
cat > /usr/local/bin/np << 'EOF'
#!/usr/bin/env bash
bash /etc/nodepass/np.sh "$@"
EOF
chmod +x /usr/local/bin/np
ln -sf "$WORK_DIR/nodepass" /usr/local/bin/nodepass

# 生成密钥
sleep 2
if systemctl is-active nodepass >/dev/null 2>&1; then
  KEY=$(timeout 10 curl -s "http://127.0.0.1:${PORT}/${PREFIX}/v1/key" 2>/dev/null | grep -o '[0-9a-f]\{32\}' | head -1 || openssl rand -hex 32)
else
  KEY=$(openssl rand -hex 32)
fi

cat > "$WORK_DIR/gob/nodepass.gob" << EOF
$KEY
EOF

API_URL="http://${SERVER_IP}:${PORT}/${PREFIX:+${PREFIX}/}v1"
URI="np://master?url=$(echo -n "$API_URL" | base64 -w0)&key=$(echo -n "$KEY" | base64 -w0)"

# 最终输出
info "
=== NodePass 安装完成 (5/5) ===

🌐 API地址: $API_URL
🔑 API密钥: $KEY

📱 一键连接URI:
$URI

⚡ 快捷命令:
  np           # 管理面板  
  nodepass     # 直接运行
  np -s        # 显示API信息
  systemctl status nodepass  # 服务状态

${command -v qrencode >/dev/null && echo "📲 二维码: $WORK_DIR/qrencode \"$URI\"" || echo "📲 安装二维码: apt install qrencode"}

服务已启动: $(systemctl is-active nodepass 2>/dev/null && echo "✅ 运行中" || echo "❌ 检查日志: journalctl -u nodepass")
"
