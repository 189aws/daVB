#!/bin/bash
# 检查是否有命令行参数，如果有则使用第一个参数作为钱包地址，否则使用默认地址
[ -n "$1" ] && WALLET_ADDR="$1" || WALLET_ADDR="NDra2V4VA7R236T2fptbaPRo72pp3CFHHVxWkH59999"
# 设置安装目录和服务名称
INSTALL_DIR="/opt/bitz"
SERVICE_NAME="bitz"

# 检查是否以root用户运行
if [ "$(id -u)" -ne 0 ]; then
    echo "错误：此脚本需要以root用户运行" >&2
    exit 1
fi

# 检查系统是否安装wget工具，如果没有则更新软件源并安装
if ! command -v wget &> /dev/null; then
    echo "正在安装wget..."
    apt-get update && apt-get install -y wget || {
        echo "错误：无法安装wget" >&2
        exit 1
    }
fi

# 创建安装目录（如果不存在）
mkdir -p "$INSTALL_DIR" || {
    echo "错误：无法创建目录 $INSTALL_DIR" >&2
    exit 1
}

# 删除旧的客户端程序（如果存在）
[ -f "$INSTALL_DIR/OrionClient" ] && rm -f "$INSTALL_DIR/OrionClient"

# 切换到安装目录
cd "$INSTALL_DIR" || {
    echo "错误：无法切换到目录 $INSTALL_DIR" >&2
    exit 1
}

# 从GitHub下载OrionClient挖矿程序并解压到安装目录
echo "正在下载OrionClient..."
wget -qO- https://github.com/egg5233/OrionClient_tw/releases/download/1.6.0/OrionClient.tar.gz | tar -zxf - -C "$INSTALL_DIR" --strip-components=1 || {
    echo "错误：下载或解压OrionClient失败" >&2
    exit 1
}

# 验证下载是否成功
if [ ! -f "$INSTALL_DIR/OrionClient" ]; then
    echo "错误：OrionClient未正确下载" >&2
    exit 1
fi

# 添加执行权限
chmod +x "$INSTALL_DIR/OrionClient"

# 创建启动脚本
echo "#!/bin/bash" > "$INSTALL_DIR/start.sh"
echo "set -euo pipefail" >> "$INSTALL_DIR/start.sh"  # 启用严格模式
echo "echo \"尝试获取公网IP...\"" >> "$INSTALL_DIR/start.sh"

# 修改IP获取逻辑，增加错误处理
cat >> "$INSTALL_DIR/start.sh" <<'EOF'
# 尝试从AWS元数据服务获取公网IP
ip=$(wget -T 3 -t 2 -qO- http://169.254.169.254/2021-03-23/meta-data/public-ipv4 || :)

if [ -z "$ip" ]; then
    echo "警告：无法从AWS元数据服务获取公网IP，使用默认矿工名"
    minerAlias="unknown-worker"
else
    # 定义IP地址加密映射表
    declare -A encrypt_dict=(
        ["0"]="a" ["1"]="b" ["2"]="c" ["3"]="d" ["4"]="e"
        ["5"]="f" ["6"]="g" ["7"]="h" ["8"]="i" ["9"]="j"
        ["."]="k"
    )

    # IP地址加密函数
    encrypt_ip() {
        local ip=$1
        local result=""
        for (( i=0; i<${#ip}; i++ )); do
            char="${ip:$i:1}"
            result+="${encrypt_dict[$char]:-$char}"
        done
        echo "$result"
    }

    # 生成矿工别名
    minerAlias=$(encrypt_ip "$ip")
    echo "使用矿工别名: $minerAlias"
fi

EOF

# 追加启动挖矿程序的命令到启动脚本
echo "$INSTALL_DIR/OrionClient mine -a --pool twbitz --key '$WALLET_ADDR' --worker \"\$minerAlias\"" >> "$INSTALL_DIR/start.sh"

# 添加错误处理
echo "echo \"启动挖矿程序: $INSTALL_DIR/OrionClient mine -a --pool twbitz --key '$WALLET_ADDR' --worker \$minerAlias\"" >> "$INSTALL_DIR/start.sh"
echo "$INSTALL_DIR/OrionClient mine -a --pool twbitz --key '$WALLET_ADDR' --worker \"\$minerAlias\" || { echo \"错误：挖矿程序启动失败\"; exit 1; }" >> "$INSTALL_DIR/start.sh"

# 给启动脚本添加可执行权限
chmod +x "$INSTALL_DIR/start.sh"

# 创建systemd服务配置文件
cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=BITZ Mining Pool Worker
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/start.sh
Restart=always
RestartSec=30
StandardOutput=syslog
StandardError=syslog
Environment="LD_LIBRARY_PATH=$INSTALL_DIR"
# 增加启动前检查
ExecStartPre=/bin/sh -c '[ -x "$INSTALL_DIR/OrionClient" ] || { echo "错误：OrionClient可执行文件不存在"; exit 1; }'

[Install]
WantedBy=multi-user.target
EOF

echo "重新加载systemd配置..."
systemctl daemon-reload || {
    echo "错误：重新加载systemd配置失败" >&2
    exit 1
}

echo "启用并启动$SERVICE_NAME服务..."
systemctl enable "$SERVICE_NAME" || echo "警告：无法设置$SERVICE_NAME服务开机自启"
systemctl restart "$SERVICE_NAME" || {
    echo "错误：启动$SERVICE_NAME服务失败" >&2
    echo "请检查服务状态：systemctl status $SERVICE_NAME" >&2
    echo "查看日志：journalctl -u $SERVICE_NAME -f" >&2
    exit 1
}

echo "安装完成！BITZ挖矿服务已启动。"
echo "检查服务状态：systemctl status $SERVICE_NAME"
echo "查看服务日志：journalctl -u $SERVICE_NAME -f"
