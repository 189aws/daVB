#!/usr/bin/env bash
# NodePass 一键安装脚本 - 完全直连版（无任何代理/镜像）
# 版本: 2026-01-04 v1.14.0 (稳定) / v1.10.3 (开发&LTS)

SCRIPT_VERSION='0.0.6-straight'
export DEBIAN_FRONTEND=noninteractive

# === 真实版本号（2026年1月4日确认） ===
STABLE_LATEST_VERSION="v1.14.0"
DEV_LATEST_VERSION="v1.10.3" 
LTS_LATEST_VERSION="v1.10.3"
STABLE_VERSION_NUM="1.14.0"
DEV_VERSION_NUM="1.10.3"
LTS_VERSION_NUM="1.10.3"
REMOTE_VERSION="Stable: v1.14.0
Development: v1.10.3
LTS: v1.10.3"

# 强制直连，无代理
GH_PROXY=""

TEMP_DIR='/tmp/nodepass'
WORK_DIR='/etc/nodepass'

# 彩色输出函数
warning() { echo -e "\033[31m\033[01m$*\033[0m"; }
error() { echo -e "\033[31m\033[01m$*\033[0m" && exit 1; }
info() { echo -e "\033[32m\033[01m$*\033[0m"; }
hint() { echo -e "\033[33m\033[01m$*\033[0m"; }

trap "rm -rf $TEMP_DIR >/dev/null 2>&1 ; echo -e '\n' ;exit" INT QUIT TERM EXIT
mkdir -p $TEMP_DIR $WORK_DIR

# 跳过CDN检查（直连版）
check_cdn() { return 0; }

# 检查root权限
[ "$(id -u)" != 0 ] && error "必须以root权限运行 (sudo -i)"

# 检测架构
case "$(uname -m)" in
  x86_64|amd64) ARCH=amd64 ;;
  armv8|arm64|aarch64) ARCH=arm64 ;;
  armv7l) ARCH=armv7 ;;
  *) error "不支持的架构: $(uname -m)" ;;
esac

# 安装依赖
if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
  apt-get update -qq && apt-get install -y curl tar procps >/dev/null 2>&1 ||
  yum update -y >/dev/null 2>&1 && yum install -y curl tar procps-ng >/dev/null 2>&1 ||
  apk update >/dev/null 2>&1 && apk add --no-cache curl tar procps >/dev/null 2>&1
fi

DOWNLOAD_TOOL="curl"
[ ! -x "$(command -v curl)" ] && DOWNLOAD_TOOL="wget"

# 可靠下载函数（先下载再解压）
download_file() {
  local url="$1" name="$2" dest="$3"
  info "下载 $name..."
  if [ "$DOWNLOAD_TOOL" = "curl" ]; then
    curl -sL -o "$TEMP_DIR/temp.tar.gz" "$url" || return 1
  else
    wget -q --timeout=30 -O "$TEMP_DIR/temp.tar.gz" "$url" || return 1
  fi
  tar -xzf "$TEMP_DIR/temp.tar.gz" -C "$TEMP_DIR" || return 1
  rm -f "$TEMP_DIR/temp.tar.gz"
  [ -f "$TEMP_DIR/nodepass*" ] && mv "$TEMP_DIR/nodepass"* "$dest" && chmod +x "$dest"
}

# 后台下载所有版本
info "(1/5) 下载 NodePass 核心文件..."
{
  download_file "https://github.com/yosebyte/nodepass/releases/download/${STABLE_LATEST_VERSION}/nodepass_${STABLE_VERSION_NUM}_linux_${ARCH}.tar.gz" "稳定版" "$TEMP_DIR/np-stb" &
  download_file "https://github.com/NodePassProject/nodepass-core/releases/download/${DEV_LATEST_VERSION}/nodepass-core_${DEV_VERSION_NUM}_linux_${ARCH}.tar.gz" "开发版" "$TEMP_DIR/np-dev" &
  download_file "https://github.com/NodePassProject/nodepass-apt/releases/download/${LTS_LATEST_VERSION}/nodepass-apt_${LTS_VERSION_NUM}_linux_${ARCH}.tar.gz" "经典版" "$TEMP_DIR/np-lts" &
  wget -q --timeout=30 -O "$TEMP_DIR/qrencode" "https://github.com/fscarmen/client_template/raw/main/qrencode-go/qrencode-go-linux-${ARCH}" && chmod +x "$TEMP_DIR/qrencode" &
} && wait
info "✓ NodePass v1.14.0/v1.10.3 下载完成"

# 选择版本
echo "
(2/5) 请选择 NodePass 内核：
 1. 稳定版 v1.14.0 (yosebyte/nodepass) - 生产环境 (默认)
 2. 开发版 v1.10.3 (NodePassProject/nodepass-core) 
 3. 经典版 v1.10.3 (NodePassProject/nodepass-apt)"
read -p "请选择 [1]: " choice
choice=${choice:-1}
case $choice in 1) ln -sf "$TEMP_DIR/np-stb" "$WORK_DIR/nodepass" ;; 2) ln -sf "$TEMP_DIR/np-dev" "$WORK_DIR/nodepass" ;; 3) ln -sf "$TEMP_DIR/np-lts" "$WORK_DIR/nodepass" ;; *) ln -sf "$TEMP_DIR/np-stb" "$WORK_DIR/nodepass" ;; esac
mv "$TEMP_DIR/np-stb" "$TEMP_DIR/np-dev" "$TEMP_DIR/np-lts" "$TEMP_DIR/qrencode" "$WORK_DIR/"

# 获取IP
info "(3/5) 获取机器IP..."
SERVER_IP=$(curl -s4 ip.sb || curl -s6 ip.sb || curl -s ifconfig.me || hostname -I | awk '{print $1}')
[ -z "$SERVER_IP" ] && SERVER_IP="127.0.0.1"

# 配置端口和API
read -p "端口 (1024-65535，回车随机): " PORT
PORT=${PORT:-0}
while [[ ! "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1024 ] || [ "$PORT" -gt 65535 ]; do
  read -p "无效端口，请输入1024-65535: " PORT
done
[ "$PORT" = "0" ] && PORT=$((RANDOM%5000+20000))

read -p "API前缀 (默认 api): " PREFIX
PREFIX=${PREFIX:-api}

# 检查端口
if command -v nc >/dev/null; then nc -z 0.0.0.0 "$PORT" 2>/dev/null && read -p "端口 $PORT 被占用，请换一个: " PORT; fi

# 创建配置和服务
mkdir -p "$WORK_DIR/gob"
cat > "$WORK_DIR/data" << EOF
CMD="master://0.0.0.0:${PORT}/${PREFIX}?tls=0"
SERVER_IP="$SERVER_IP"
PORT="$PORT"
PREFIX="$PREFIX"
EOF

# systemd服务
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
systemctl enable nodepass
systemctl start nodepass

# 创建快捷方式
cat > /usr/local/bin/np << 'EOF'
#!/usr/bin/env bash
cd /etc/nodepass && bash np.sh "$@"
EOF
chmod +x /usr/local/bin/np
ln -sf "$WORK_DIR/nodepass" /usr/local/bin/nodepass

# 生成密钥和URI
sleep 3
KEY=$(timeout 5 "$WORK_DIR/nodepass" genkey | grep -o '[0-9a-f]\{32\}' || openssl rand -hex 32)
API_URL="http://${SERVER_IP}:${PORT}/${PREFIX}/v1"
URI="np://master?url=$(echo -n "$API_URL" | base64 -w0)&key=$(echo -n "$KEY" | base64 -w0)"

cat > "$WORK_DIR/gob/nodepass.gob" << EOF
$KEY
EOF

info "
$(cat <<- EOF
✓ NodePass 安装成功！

API信息:
${API_URL}
${KEY}

一键连接URI:
$URI

快捷命令:
np - 管理面板
nodepass - 直接运行
np -s - 显示API信息
np -o - 开关服务

$(command -v qrencode >/dev/null && echo "$WORK_DIR/qrencode \"$URI\"" || echo "安装 qrencode 查看二维码: apt install qrencode")
EOF
)"
