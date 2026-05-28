#!/bin/bash

set -e

echo "========== ApoolMiner 自动更新安装脚本 (全自动终极修复版) =========="

# 默认账户和矿池配置
ACCOUNT="${1:-CP_desb91pu36}"
INSTALL_DIR="/opt/apoolminer"
SERVICE_FILE="/etc/systemd/system/apoolminer.service"
POOL="xmr.asia.apool.io:4334"
VERSION="v3.7.0"

# 1. 基础依赖与环境准备
echo "正在安装系统依赖..."
apt update
apt install -y wget tar jq curl ca-certificates libcurl4

# 2. 解决 Debian 12 缺少 libssl1.1 的兼容性问题
if ! dpkg -s libssl1.1 >/dev/null 2>&1; then
    echo "正在下载 libssl1.1 兼容包 (针对 Debian 12)..."
    wget -q http://nz2.archive.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.1f-1ubuntu2_amd64.deb
    dpkg -i libssl1.1_1.1.1f-1ubuntu2_amd64.deb || apt --fix-broken install -y
    rm libssl1.1_1.1.1f-1ubuntu2_amd64.deb
fi

# 3. 目录清理或创建
if [ -d "$INSTALL_DIR" ]; then
    echo "清理安装目录 $INSTALL_DIR..."
    rm -rf "$INSTALL_DIR"/*
else
    echo "创建安装目录 $INSTALL_DIR..."
    mkdir -p "$INSTALL_DIR"
fi
cd "$INSTALL_DIR"

# 4. 下载并精准解压官方最新稳定版
echo "开始下载官方原生 $VERSION 压缩包..."
DOWNLOAD_URL="https://github.com/apool-io/apoolminer/releases/download/${VERSION}/apoolminer_linux_${VERSION}.tar.gz"

# 显式利用 -L 跟踪重定向直连下载
curl -L -o apoolminer.tar.gz "$DOWNLOAD_URL"

echo "正在解压..."
tar -zxf apoolminer.tar.gz -C "$INSTALL_DIR"
rm -f apoolminer.tar.gz

# 【核心修复】如果解压出了套娃子文件夹，自动将里面的程序提到根目录
if [ -d "$INSTALL_DIR/apoolminer_linux_${VERSION}" ]; then
    echo "检测到官方子层级目录，正在自动整理结构..."
    mv "$INSTALL_DIR/apoolminer_linux_${VERSION}"/* "$INSTALL_DIR/"
    rm -rf "$INSTALL_DIR/apoolminer_linux_${VERSION}"
fi

# 强制赋予主程序执行权限
chmod +x "$INSTALL_DIR/apoolminer"
echo "Apoolminer 主程序和依赖库部署就绪。"

# 5. 写入纯净的 update.sh（防止盲目更新冲掉本地文件和配置）
echo "写入 update.sh..."
cat > "$INSTALL_DIR/update.sh" <<EOF
#!/bin/bash
echo "当前版本 $VERSION 已处于最稳定状态，跳过自动检测。"
exit 0
EOF
chmod +x "$INSTALL_DIR/update.sh"

# 6. 覆盖写入专属的 run.sh 启动脚本（精准绑定 XMR 算法与机器 IP）
echo "写入 run.sh..."
cat > "$INSTALL_DIR/run.sh" <<EOF
#!/bin/bash

# 获取公网 IP 作为 Worker 名称
raw_ip=\$(curl -s --connect-timeout 5 http://checkip.amazonaws.com | tr -d '.' | tr -d '\n')
worker=\$(echo \$raw_ip | cut -c 1-15)

if [ -z "\$worker" ]; then
    worker="node\${RANDOM}"
fi

echo "启动矿工，Worker名称: \$worker"

# 执行主程序，显式指定算法为 xmr 
exec "$INSTALL_DIR/apoolminer" --algo xmr --account "$ACCOUNT" --worker "\$worker" --pool "$POOL"
EOF
chmod +x "$INSTALL_DIR/run.sh"

# 7. 注册 Systemd 守护系统服务
echo "注册系统后台服务..."
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Apool Qubic Miner
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/run.sh
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

# 8. 彻底点火启动
systemctl daemon-reload
systemctl enable apoolminer
systemctl restart apoolminer

echo "========== 🥳 恭喜，全套部署完美完成！ =========="
echo "监控状态：systemctl status apoolminer"
echo "查看算力输出日志：journalctl -u apoolminer -f"
