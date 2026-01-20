# 1. 安装基础工具
apt update && apt install -y curl socat

# 2. 安装 acme.sh
curl https://get.acme.sh | sh -s email=my@example.com
source ~/.bashrc

# 3. 【关键：解决 405 问题的优化点】
# 强制将默认 CA 设置为 Let's Encrypt，它的兼容性在 standalone 模式下更好
~/.acme.sh/acme.sh --set-default-ca --server letsencrypt

# 4. 停止占用 80 端口的服务
systemctl stop nginx || true

# 5. 申请证书
read -p "请输入解析到本机的域名: " MY_DOMAIN
# 添加 --debug 2 参数可以让你看到具体的请求过程，如果报错能更清楚原因
~/.acme.sh/acme.sh --issue -d "$MY_DOMAIN" --standalone --debug 2

# 6. 安装/拷贝证书
mkdir -p /etc/ssl/$MY_DOMAIN
~/.acme.sh/acme.sh --install-cert -d "$MY_DOMAIN" \
--key-file       /etc/ssl/$MY_DOMAIN/privkey.pem  \
--fullchain-file /etc/ssl/$MY_DOMAIN/fullchain.pem