#!/bin/bash
# 一键部署脚本：下载文件、设置权限、配置 systemd 服务

# 定义工作目录
WORK_DIR="$HOME/ore-mine"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR" || exit

# 下载文件
wget https://raw.githubusercontent.com/189aws/daVB/refs/heads/main/zESmuban.sh -O zESmuban.sh
wget https://github.com/xintai6660707/ore-mine-pool/raw/refs/heads/main/ore-mine-pool-linux-avx512 -O ore-mine-pool-linux-avx512

# 设置执行权限
chmod +x zESmuban.sh
chmod +x ore-mine-pool-linux-avx512

# 创建 systemd 服务文件
sudo bash -c "cat > /etc/systemd/system/ore-mine.service" << EOF
[Unit]
Description=Ore Mine Pool Script
After=network.target

[Service]
Type=simple
ExecStart=$WORK_DIR/zESmuban.sh
WorkingDirectory=$WORK_DIR
Restart=always
RestartSec=10
StandardOutput=append:$WORK_DIR/start.log
StandardError=append:$WORK_DIR/start.log

[Install]
WantedBy=multi-user.target
EOF

# 设置服务文件权限
sudo chmod 644 /etc/systemd/system/ore-mine.service

# 重新加载 systemd 配置
sudo systemctl daemon-reload

# 启用并启动服务
sudo systemctl enable ore-mine.service
sudo systemctl start ore-mine.service

# 输出提示信息
echo "部署完成！服务已启动并设置为开机自启。"
echo "查看服务状态：sudo systemctl status ore-mine.service"
echo "查看日志：cat $WORK_DIR/start.log"
