#!/bin/bash
[ "$1" ] && WALLET_ADDR="$1" || WALLET_ADDR="NDra2V4VA7R236T2fptbaPRo72pp3CFHHVxWkH59999"
INSTALL_DIR="/opt/bitz"
SERVICE_NAME="bitz"

[ ! "$(which wget)" ] && apt-get update && apt-get install -y wget

mkdir -p "$INSTALL_DIR"

[ -f "$INSTALL_DIR/OrionClient" ] && rm -rf "$INSTALL_DIR/OrionClient"

cd $INSTALL_DIR

wget -qO-  https://github.com/egg5233/OrionClient_tw/releases/download/1.6.0/OrionClient.tar.gz | tar -zxf - -C $INSTALL_DIR --strip-components=1

echo '''#!/bin/bash
ip="$(wget -T 3 -t 2 -qO- http://169.254.169.254/2021-03-23/meta-data/public-ipv4)"
[ -z "$ip" ] && exit 1

declare -A encrypt_dict=(
    ["0"]="a" ["1"]="b" ["2"]="c" ["3"]="d" ["4"]="e"
    ["5"]="f" ["6"]="g" ["7"]="h" ["8"]="i" ["9"]="j"
    ["."]="k"
)

encrypt_ip() {
    local ip=$1
    local result=""
    for (( i=0; i<${#ip}; i++ )); do
        char="${ip:$i:1}"
        result+="${encrypt_dict[$char]:-$char}"
    done
    echo "$result"
}

minerAlias=$(encrypt_ip "$ip")

''' > $INSTALL_DIR/start.sh

echo "$INSTALL_DIR/OrionClient mine -a --pool twbitz --key '$WALLET_ADDR' --worker \$minerAlias">> $INSTALL_DIR/start.sh

chmod +x $INSTALL_DIR/start.sh

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

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable $SERVICE_NAME
systemctl restart $SERVICE_NAME
