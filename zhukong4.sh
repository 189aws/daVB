#!/usr/bin/env bash
# NodePass 一键直连安装脚本 v1.14.0 - 最终修复版
set -euo pipefail

SCRIPT_VERSION='0.0.6-straight-final'

# === 真实版本（2026年1月4日确认） ===
STABLE_LATEST_VERSION="v1.14.0"
DEV_LATEST_VERSION="v1.10.3"
LTS_LATEST_VERSION="v1.10.3"
STABLE_VERSION_NUM="1.14.0"
DEV_VERSION_NUM="1.10.3"
LTS_VERSION_NUM="1.10.3"

TEMP_DIR='/tmp/nodepass'
WORK_DIR='/etc/nodepass'

# 颜色函数
red() { echo -e "\033[31m\033[01m$*\033[0m"; }
green() { echo -e "\033[32m\033[01m$*\033[0m"; }
yellow() { echo -e "\033[33m\033[01m$*\033[0m"; }
error() { red "错误: $1"; exit 1; }

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
green "架构: $ARCH ✓"

# 安装依赖
command -v curl >/dev/null 2>&1 || {
  apt-get update -qq && apt-get install -y -qq curl tar procps qrencode 2>/dev/null || \
  yum install -y -q curl tar procps-ng qrencode 2>/dev/null || \
  apk add --no-cache curl tar procps qrencode >/dev/null 2>&1 || \
  error "请手动安装 curl/tar/qrencode"
}

# 下载函数
download_nodepass() {
  local ver="$1" repo="$2" name="$3" dest="$4"
  local url="https://github.com/${repo}/releases/download/${ver}/${name}_${ver#v}_linux_${ARCH}.tar.gz"
  
  yellow "下载 ${name} ${ver}..."
  if curl -sL --connect-timeout 10 --max-time 30 -o "${dest}.tar.gz" "$url"; then
    if tar -tzf "${dest}.tar.gz" >/dev/null 2>&1; then
      tar -xzf "${dest}.tar.gz" -C "$TEMP_DIR"
      find "$TEMP_DIR" -name "${name}*" -type f -executable | head -1 | xargs -I {} mv {} "$dest"
      rm -f "${dest}.tar.gz"
      [ -f "$dest" ] && { green "✓ $name 下载成功"; return 0; }
    fi
  fi
  red "✗ $name 下载失败"; return 1
}

# 下载核心文件
green "=== 下载 NodePass 核心 (1/5) ==="
download_nodepass "$STABLE_LATEST_VERSION" "yosebyte/nodepass" "nodepass" "$TEMP_DIR/np-stb" || \
download_nodepass "$DEV_LATEST_VERSION" "NodePassProject/nodepass-core" "nodepass-core" "$TEMP_DIR/np-dev" || \
download_nodepass "$LTS_LATEST_VERSION" "NodePassProject/nodepass-apt" "nodepass-apt" "$TEMP_DIR/np-lts" || \
  download_nodepass "$STABLE_LATEST_VERSION" "yosebyte/nodepass" "nodepass" "$TEMP_DIR/np-stb"

[ ! -f "$TEMP_DIR/np-stb" ] && [ ! -f "$TEMP_DIR/np-dev" ] && [ ! -f "$TEMP_DIR/np-lts" ] && 
  error "所有版本下载失败，请检查 GitHub 连通性"

# 选择版本
echo "
=== 选择版本 (2/5) ===
1. 稳定版 ${STABLE_LATEST_VERSION} ($( [ -f "$TEMP_DIR/np-stb" ] && echo "✓" || echo "✗" ))
2. 开发版 ${DEV_LATEST_VERSION} ($( [ -f "$TEMP_DIR/np-dev" ] && echo "✓" || echo "✗" ))
3. 经典版 ${LTS_LATEST_VERSION} ($( [ -f "$TEMP_DIR/np-lts" ] && echo "✓" || echo "✗" ))"
read -r -p "请选择 [1]: " choice
choice=${choice:-1}

case $choice in 1) BINARY="$TEMP_DIR/np-stb" ;; 2) BINARY="$TEMP_DIR/np-dev" ;; 3) BINARY="$TEMP_DIR/np-lts" ;; *) BINARY="$TEMP_DIR/np-stb" ;; esac
[ ! -f "$BINARY" ] && { yellow "版本不可用，使用稳定版"; BINARY="$TEMP_DIR/np-stb"; }

# 安装文件
green "=== 安装文件 (3/5) ==="
for f in np-stb np-dev np-lts; do [ -f "$TEMP_DIR/$f" ] && mv "$TEMP_DIR/$f" "$WORK_DIR/" && chmod +x "$WORK_DIR/$f"; done
ln -sf "$BINARY" "$WORK_DIR/nodepass"
ln -sf "$WORK_DIR/nodepass" /usr/local/bin/nodepass

# 配置
green "=== 配置服务 (4/5) ==="
SERVER_IP=$(curl -s4 --connect-timeout 5 ip.sb || curl -s --connect-timeout 5 ifconfig.me || hostname -I | awk '{print $1}' | grep -E '^[0-9]' | head -1 || echo "127.0.0.1")
read -r -p "端口 (1024-65535，默认 15661): " PORT
PORT=${PORT:-15661}
while [[ ! "$PORT" =~ ^[0-9]{4,5}$ ]] || [ "$PORT" -lt 1024 ] || [ "$PORT" -gt 65535 ]; do
  read -r -p "无效端口 (1024-65535): " PORT
done

read -r -p "API前缀 (默认 api): " PREFIX
PREFIX=${PREFIX:-api}

# 检查端口
command -v nc >/dev/null 2>&1 && nc -z 0.0.0.0 "$PORT" 2>/dev/null && {
  yellow "端口 $PORT 被占用"; read -r -p "新端口: " PORT
}

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
systemctl start nodepass >/dev/null 2>&1

sleep 3

# np 管理脚本
cat > "$WORK_DIR/np.sh" << 'EOF'
#!/usr/bin/env bash
cd /etc/nodepass && bash $0 "$@"
EOF
chmod +x "$WORK_DIR/np.sh"
cat > /usr/local/bin/np << 'EOF'
#!/usr/bin/env bash
bash /etc/nodepass/np.sh "$@"
EOF
chmod +x /usr/local/bin/np

# 获取密钥
if systemctl is-active --quiet nodepass 2>/dev/null; then
  sleep 2
  KEY=$(timeout 5 curl -s --connect-timeout 5 "http://127.0.0.1:${PORT}/${PREFIX}/v1/key" 2>/dev/null | grep -o '[0-9a-f]\{32\}' | head -1)
fi
[ -z "$KEY" ] && KEY=$(openssl rand -hex 32 2>/dev/null || head -c32 /dev/urandom 2>/dev/null | md5sum | cut -d' ' -f1)

echo "$KEY" > "$WORK_DIR/gob/nodepass.gob"

# 最终输出 - 纯文本避免 Bash 替换问题
green "=== NodePass 安装完成 (5/5) ==="
echo ""
echo "🌐 API地址: http://${SERVER_IP}:${PORT}/${PREFIX}/v1"
echo "🔑 API密钥: ${KEY}"
echo ""
echo "📱 一键连接URI:"
echo "np://master?url=$(echo -n "http://${SERVER_IP}:${PORT}/${PREFIX}/v1" | base64 -w0)&key=$(echo -n "$KEY" | base64 -w0)"
echo ""
echo "⚡ 快捷命令:"
echo "  np                    # 管理面板"
echo "  nodepass              # 直接运行"
echo "  np -s                 # 显示API信息"
echo "  systemctl status nodepass  # 服务状态"
echo ""
echo "📲 二维码: ${WORK_DIR}/qrencode \"np://master?url=$(echo -n \"http://${SERVER_IP}:${PORT}/${PREFIX}/v1\" | base64 -w0)&key=$(echo -n \"$KEY\" | base64 -w0)\""
echo ""
echo "服务状态: $(systemctl is-active nodepass 2>/dev/null && echo "✅ 运行中" || echo "❌ 检查: journalctl -u nodepass -f")"
