#!/bin/bash

echo "[+] 正在 AWS Linux 上安装必要组件..."
# AWS Linux 使用 dnf (AL2023) 或 yum (AL2)
dnf update -y
dnf install -y curl wget

# 创建工作目录
mkdir -p "/opt/email/mailstore"
mkdir -p "/opt/email/logs"

# 下载服务端程序
echo "[+] 下载 server 程序..."
wget -qO /opt/email/server https://raw.githubusercontent.com/chuben/script/main/email/server

# 赋予执行权限
chmod +x /opt/email/server

# 创建 Systemd 服务文件
cat > /etc/systemd/system/simple_mail_http.service <<EOF
[Unit]
Description=Simple Mail HTTP
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/email
ExecStart=/opt/email/server
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

# 重载并启动服务
echo "[+] 启动 simple_mail_http 服务..."
systemctl daemon-reload
systemctl enable simple_mail_http 
systemctl restart simple_mail_http

echo "[+] 配置完成！"
