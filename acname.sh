# 1. 安装基础工具
apt update && apt install -y curl socat

# 2. 安装 acme.sh (请将 my@example.com 换成你的真实邮箱)
curl https://get.acme.sh | sh -s email=my@example.com
source ~/.bashrc

# 3. 停止占用 80 端口的服务 (如果是新机器可跳过，如果装了 Nginx/Apache 请先停止)
systemctl stop nginx || true

# 4. 申请证书 (请将 yourdomain.com 换成你的域名)
read -p "请输入解析到本机的域名: " MY_DOMAIN
~/.acme.sh/acme.sh --issue -d "$MY_DOMAIN" --standalone

# 5. 创建存放证书的文件夹
mkdir -p /etc/ssl/$MY_DOMAIN

# 6. 安装/拷贝证书到指定位置
~/.acme.sh/acme.sh --install-cert -d "$MY_DOMAIN" \
--key-file       /etc/ssl/$MY_DOMAIN/privkey.pem  \
--fullchain-file /etc/ssl/$MY_DOMAIN/fullchain.pem