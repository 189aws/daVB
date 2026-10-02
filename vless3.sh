#!/usr/bin/env bash

# ===============================================================
# Sing-box Docker 版 VLESS-Reality 部署与 TG 推送脚本 (修复版)
# ===============================================================

set -e

# ========== TG 配置区 ==========
TG_TOKEN="8896559295:AAHWVHQVJfoWG9v4McFg2qJgACw0nEpMxJo"
TG_CHAT_ID="1417748881"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

log() {
    echo -e "${GREEN}[INFO] $1${PLAIN}"
}

warn() {
    echo -e "${YELLOW}[WARN] $1${PLAIN}"
}

err() {
    echo -e "${RED}[ERROR] $1${PLAIN}"
}

if [[ $EUID -ne 0 ]]; then
   err "错误：请使用 root 权限运行此脚本！"
   exit 1
fi

echo -e "${GREEN}=== 开始部署 Sing-box Docker VLESS-Reality 服务 ===${PLAIN}"

# 1. 检查并安装 Docker 环境（自动修复包名/源问题）
log "1. 检查并配置 Docker 环境..."

if ! command -v docker &>/dev/null; then
    log "检测到未安装 Docker，开始自动安装 Docker 官方源..."
    if command -v apt &>/dev/null; then
        apt update -y && apt install -y ca-certificates curl gnupg
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg || true
        chmod a+r /etc/apt/keyrings/docker.gpg || true
        
        # 写入 Docker 官方 APT 源
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
        
        apt update -y
        apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin jq openssl
    elif command -v yum &>/dev/null; then
        yum install -y curl jq openssl yum-utils
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi
else
    log "Docker 已安装，安装辅助工具 (jq, openssl)..."
    if command -v apt &>/dev/null; then
        apt update -y && apt install -y jq openssl curl
    elif command -v yum &>/dev/null; then
        yum install -y jq openssl curl
    fi
fi

systemctl enable docker --now &>/dev/null || true

# 2. 从内置域名池中并发筛选可用域名
log "2. 正在并发测试并筛选可用 SNI 域名..."

TMP_POOL=$(mktemp)
cat << 'EOF' > "$TMP_POOL"
ucsf.edu
www.ucsf.edu
ucdavis.edu
www.ucdavis.edu
ucsb.edu
www.ucsb.edu
ucsc.edu
www.ucsc.edu
ucr.edu
www.ucr.edu
sfsu.edu
www.sfsu.edu
sjsu.edu
www.sjsu.edu
sdsu.edu
www.sdsu.edu
csulb.edu
www.csulb.edu
cpp.edu
www.cpp.edu
fullerton.edu
www.fullerton.edu
usc.edu
www.usc.edu
www.stanford.edu
caltech.edu
www.caltech.edu
pdx.edu
www.pdx.edu
oregonstate.edu
www.oregonstate.edu
uoregon.edu
www.uoregon.edu
washington.edu
www.washington.edu
uidaho.edu
www.uidaho.edu
www.boisestate.edu
unr.edu
www.unr.edu
unlv.edu
www.unlv.edu
jhu.edu
www.jhu.edu
vanderbilt.edu
www.vanderbilt.edu
www.emory.edu
rice.edu
www.rice.edu
wustl.edu
www.wustl.edu
georgetown.edu
www.georgetown.edu
www.nd.edu
unc.edu
www.unc.edu
umich.edu
www.umich.edu
utexas.edu
www.utexas.edu
www.tamu.edu
ufl.edu
www.ufl.edu
umd.edu
www.umd.edu
pitt.edu
www.osu.edu
msu.edu
www.msu.edu
www.psu.edu
rutgers.edu
www.vt.edu
gatech.edu
www.gatech.edu
ncsu.edu
www.ncsu.edu
ethz.ch
www.ethz.ch
uzh.ch
www.uzh.ch
unibas.ch
www.unibas.ch
unige.ch
www.unige.ch
epfl.ch
www.epfl.ch
tum.de
www.tum.de
uni-heidelberg.de
www.uni-heidelberg.de
fau.de
www.fau.de
uni-bonn.de
www.uni-bonn.de
uni-goettingen.de
www.uni-goettingen.de
kit.edu
www.kit.edu
uni-freiburg.de
www.uni-freiburg.de
uni-tuebingen.de
www.uni-tuebingen.de
www.ku.dk
dtu.dk
www.dtu.dk
aau.dk
www.aau.dk
su.se
www.su.se
uu.se
www.uu.se
chalmers.se
www.chalmers.se
helsinki.fi
www.helsinki.fi
aalto.fi
www.aalto.fi
uio.no
www.uio.no
ntnu.no
www.ntnu.no
tudelft.nl
www.tudelft.nl
uva.nl
www.uva.nl
uu.nl
www.uu.nl
tue.nl
www.tue.nl
rug.nl
www.rug.nl
kuleuven.be
www.kuleuven.be
ugent.be
www.ugent.be
www.unipd.it
polimi.it
www.polimi.it
www.unimi.it
ubc.ca
www.ubc.ca
www.sfu.ca
uvic.ca
www.uvic.ca
ualberta.ca
www.ualberta.ca
ucalgary.ca
www.ucalgary.ca
uwaterloo.ca
www.uwaterloo.ca
mcgill.ca
www.mcgill.ca
usyd.edu.au
unimelb.edu.au
www.unimelb.edu.au
uq.edu.au
www.uq.edu.au
monash.edu
www.monash.edu
unsw.edu.au
www.unsw.edu.au
uwa.edu.au
www.uwa.edu.au
adelaide.edu.au
www.adelaide.edu.au
www.nvidia.com
developer.nvidia.com
amd.com
www.amd.com
intel.com
www.intel.com
www.qualcomm.com
www.broadcom.com
ti.com
www.ti.com
analog.com
www.analog.com
www.synopsys.com
www.cisco.com
www.juniper.net
arista.com
www.arista.com
hp.com
www.hp.com
www.hpe.com
www.dell.com
lenovo.com
www.lenovo.com
asus.com
www.asus.com
rog.asus.com
acer.com
www.acer.com
www.logitech.com
corsair.com
www.corsair.com
www.razer.com
www.samsung.com
images.samsung.com
www.lg.com
sony.com
www.sony.com
www.panasonic.com
www.canon.com
www.nikon.com
epson.com
www.epson.com
www.ricoh.com
bose.com
www.bose.com
sennheiser.com
www.sennheiser.com
www.shure.com
kernel.org
python.org
www.python.org
pypi.org
files.pythonhosted.org
golang.org
pkg.go.dev
rust-lang.org
crates.io
static.crates.io
ruby-lang.org
www.ruby-lang.org
rubygems.org
index.rubygems.org
php.net
www.php.net
packagist.org
nodejs.org
npmjs.com
deno.land
dl.deno.land
githubstatus.com
github.githubassets.com
gitlab.com
docker.com
hub.docker.com
download.docker.com
debian.org
packages.debian.org
ubuntu.com
releases.ubuntu.com
archlinux.org
aur.archlinux.org
alpinelinux.org
dl-cdn.alpinelinux.org
fedoraproject.org
getfedora.org
centos.org
rockylinux.org
almalinux.org
freebsd.org
www.freebsd.org
openbsd.org
www.openbsd.org
ieee.org
www.ieee.org
ieeexplore.ieee.org
acm.org
www.acm.org
dl.acm.org
nature.com
www.nature.com
www.sciencemag.org
www.science.org
sciencedirect.com
www.sciencedirect.com
springer.com
link.springer.com
wiley.com
onlinelibrary.wiley.com
taylorandfrancis.com
tandfonline.com
academic.oup.com
cell.com
www.cell.com
thelancet.com
www.thelancet.com
www.nejm.org
bmj.com
www.bmj.com
pnas.org
www.pnas.org
frontiersin.org
www.frontiersin.org
mdpi.com
www.mdpi.com
plos.org
journals.plos.org
iop.org
iopscience.iop.org
journals.aps.org
acs.org
pubs.acs.org
rsc.org
pubs.rsc.org
united.com
www.united.com
www.delta.com
aa.com
www.aa.com
alaskaair.com
hawaiianairlines.com
www.hawaiianairlines.com
aircanada.com
www.aircanada.com
lh.com
www.lufthansa.com
britishairways.com
www.britishairways.com
airfrance.com
www.airfrance.com
klm.com
www.klm.com
jal.co.jp
cathaypacific.com
www.cathaypacific.com
singaporeair.com
www.singaporeair.com
qantas.com
www.qantas.com
emirates.com
www.emirates.com
qatarairways.com
www.qatarairways.com
etihad.com
www.etihad.com
fedex.com
www.fedex.com
dhl.com
www.dhl.com
ups.com
www.ups.com
booking.com
www.booking.com
agoda.com
www.agoda.com
hotels.com
www.hotels.com
marriott.com
www.marriott.com
www.hilton.com
hyatt.com
www.hyatt.com
ihg.com
www.ihg.com
visa.com
www.visa.com
usa.visa.com
www.mastercard.com
mastercard.us
americanexpress.com
www.americanexpress.com
discover.com
www.discover.com
paypal.com
www.paypal.com
paypalobjects.com
stripe.com
js.stripe.com
wise.com
www.wise.com
www.hsbc.com
barclays.com
www.barclays.com
bnpparibas.com
www.bnpparibas.com
santander.com
www.santander.com
ubs.com
www.ubs.com
sc.com
www.sc.com
tesla.com
www.tesla.com
www.ford.com
www.gm.com
www.toyota.com
www.honda.com
nissan-global.com
www.nissan-global.com
bmw.com
www.bmw.com
mercedes-benz.com
www.mercedes-benz.com
www.porsche.com
volkswagen.com
www.volkswagen.com
volvocars.com
www.volvocars.com
boeing.com
www.boeing.com
airbus.com
www.airbus.com
siemens.com
www.siemens.com
schneider-electric.com
www.schneider-electric.com
abb.com
new.abb.com
www.bosch.com
agoda.comwww.agoda.com
arizona.edu
www.arizona.edu
asu.edu
www.asu.edu
nau.edu
www.nau.edu
usu.edu
www.usu.edu
byu.edu
www.byu.edu
www.colostate.edu
du.edu
www.du.edu
hawaii.edu
www.hawaii.edu
montana.edu
www.montana.edu
umt.edu
www.umt.edu
www.uwyo.edu
brown.edu
www.brown.edu
bc.edu
www.bc.edu
www.bu.edu
syracuse.edu
www.syracuse.edu
drexel.edu
www.drexel.edu
temple.edu
www.temple.edu
udel.edu
www.wvu.edu
utk.edu
www.utk.edu
uab.edu
www.uab.edu
olemiss.edu
www.olemiss.edu
msstate.edu
www.msstate.edu
uark.edu
www.uark.edu
okstate.edu
www.okstate.edu
ku.edu
www.ku.edu
ksu.edu
www.ksu.edu
uiowa.edu
www.uiowa.edu
iastate.edu
www.iastate.edu
www.umn.edu
mizzou.edu
www.mizzou.edu
indiana.edu
www.indiana.edu
www.illinoisstate.edu
ohio.edu
www.ohio.edu
sc.edu
www.sc.edu
fsu.edu
www.fsu.edu
ucf.edu
www.ucf.edu
www.usf.edu
fiu.edu
www.fiu.edu
miami.edu
www.miami.edu
tulane.edu
www.tulane.edu
lsu.edu
www.lsu.edu
baylor.edu
utdallas.edu
www.utdallas.edu
www.uta.edu
www.soton.ac.uk
www.bristol.ac.uk
warwick.ac.uk
www.warwick.ac.uk
dur.ac.uk
www.dur.ac.uk
st-andrews.ac.uk
www.st-andrews.ac.uk
gla.ac.uk
www.gla.ac.uk
www.ed.ac.uk
www.manchester.ac.uk
kcl.ac.uk
www.kcl.ac.uk
leeds.ac.uk
www.leeds.ac.uk
sheffield.ac.uk
www.sheffield.ac.uk
www.bham.ac.uk
nottingham.ac.uk
www.nottingham.ac.uk
exeter.ac.uk
www.exeter.ac.uk
www.york.ac.uk
bath.ac.uk
www.bath.ac.uk
lboro.ac.uk
www.lboro.ac.uk
cardiff.ac.uk
www.cardiff.ac.uk
qub.ac.uk
www.qub.ac.uk
tcd.ie
www.tcd.ie
ucd.ie
www.ucd.ie
nuigalway.ie
www.universityofgalway.ie
ucc.ie
www.ucc.ie
kyoto-u.ac.jp
www.kyoto-u.ac.jp
www.osaka-u.ac.jp
www.titech.ac.jp
www.tohoku.ac.jp
www.nagoya-u.ac.jp
www.hokudai.ac.jp
www.keio.ac.jp
www.waseda.jp
www.tsukuba.ac.jp
www.kobe-u.ac.jp
www.hiroshima-u.ac.jp
snu.ac.kr
www.snu.ac.kr
kaist.ac.kr
www.kaist.ac.kr
postech.ac.kr
www.postech.ac.kr
korea.ac.kr
www.korea.ac.kr
yonsei.ac.kr
www.yonsei.ac.kr
skku.edu
www.skku.edu
hanyang.ac.kr
www.hanyang.ac.kr
khu.ac.kr
www.khu.ac.kr
ewha.ac.kr
www.ewha.ac.kr
dsu.edu
www.dsu.edu
monroe.edu
www.monroe.edu
ubnt.comwww.ui.com
ui.comwww.ui.com
mikrotik.comwww.mikrotik.com
us.msi.com
noctua.at
www.noctua.at
ssupd.co
www.ssupd.co
hori.jp
www.hori.jp
gaomon.net
www.gaomon.net
www.aerocool.io
arctic.de
www.arctic.de
tokinalens.comwww.tokinalens.com
leica-camera.comwww.leica-camera.com
kef.comwww.kef.com
dynaudio.comwww.dynaudio.com
arcam.co.uk
www.arcam.co.uk
EOF

check_domain() {
    local domain=$1
    if timeout 2 bash -c "echo | openssl s_client -connect '${domain}:443' -servername '${domain}' -tls1_3 -brief 2>&1" | grep -iq "established"; then
        echo "$domain"
    fi
}
export -f check_domain

VALID_DOMAINS=()
while IFS= read -r domain; do
    [ -n "$domain" ] && VALID_DOMAINS+=("$domain")
done < <(xargs -P 10 -I {} bash -c 'check_domain "$@"' _ {} < "$TMP_POOL")

rm -f "$TMP_POOL"

if [ ${#VALID_DOMAINS[@]} -eq 0 ]; then
    warn "探测未匹配到响应成功的域名，回退默认伪装域名: debian.org"
    DEST_DOMAIN="debian.org"
else
    RANDOM_INDEX=$((RANDOM % ${#VALID_DOMAINS[@]}))
    DEST_DOMAIN="${VALID_DOMAINS[$RANDOM_INDEX]}"
    log "挑选伪装域名: ${CYAN}${DEST_DOMAIN}${PLAIN}"
fi

# 3. 提取容器生成 KeyPair 与 UUID
log "3. 生成 VLESS Reality 密钥对与参数..."

KEY_OUTPUT=$(docker run --rm ghcr.io/sagernet/sing-box:latest generate reality-keypair)
PRIVATE_KEY=$(echo "$KEY_OUTPUT" | awk '/PrivateKey:/ {print $2}')
PUBLIC_KEY=$(echo "$KEY_OUTPUT" | awk '/PublicKey:/ {print $2}')

UUID=$(docker run --rm ghcr.io/sagernet/sing-box:latest generate uuid)
SHORT_ID=$(openssl rand -hex 8)
PORT=443

# 4. 生成配置文件与启动 Docker 容器
log "4. 写入 Sing-box 配置文件..."

CONFIG_DIR="/etc/sing-box"
mkdir -p "${CONFIG_DIR}"

cat <<EOF > "${CONFIG_DIR}/config.json"
{
  "log": {
    "level": "warn",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": ${PORT},
      "users": [
        {
          "uuid": "${UUID}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${DEST_DOMAIN}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${DEST_DOMAIN}",
            "server_port": 443
          },
          "private_key": "${PRIVATE_KEY}",
          "short_id": [
            "${SHORT_ID}"
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ]
}
EOF

# 清理已有容器并重新启动
docker rm -f sing-box &>/dev/null || true

log "启动 Sing-box Docker 容器..."
docker run -d \
  --name sing-box \
  --restart=always \
  --network=host \
  -v "${CONFIG_DIR}/config.json:/etc/sing-box/config.json" \
  ghcr.io/sagernet/sing-box:latest \
  run -c /etc/sing-box/config.json

# 5. 构建节点信息
SERVER_IP=$(curl -s4 --connect-timeout 5 ifconfig.me || curl -s4 --connect-timeout 5 ip.sb || echo "127.0.0.1")
VLESS_LINK="vless://${UUID}@${SERVER_IP}:${PORT}?type=tcp&security=reality&encryption=none&pbk=${PUBLIC_KEY}&fp=chrome&sni=${DEST_DOMAIN}&sid=${SHORT_ID}&flow=xtls-rprx-vision#SingBox-Reality-${DEST_DOMAIN}"

# 6. 修复并推送节点链接到 Telegram
log "推送配置到 Telegram..."
if [ -n "$TG_TOKEN" ] && [ -n "$TG_CHAT_ID" ]; then
    TG_TEXT="<b>Sing-box VLESS-Reality 节点部署成功</b>

<b>服务器 IP:</b> <code>${SERVER_IP}</code>
<b>伪装域名:</b> <code>${DEST_DOMAIN}</code>

<b>节点链接:</b>
<code>${VLESS_LINK}</code>"

    # 使用 4 强制使用 IPv4，--data-urlencode 避免传输编码解析异常，输出完整 API 异常
    RESPONSE=$(curl -s4 --connect-timeout 10 -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -d "chat_id=${TG_CHAT_ID}" \
        -d "parse_mode=HTML" \
        --data-urlencode "text=${TG_TEXT}")

    if echo "$RESPONSE" | grep -q '"ok":true'; then
        log "Telegram 推送成功！"
    else
        warn "Telegram 推送失败，返回接口结果如下："
        echo -e "${RED}${RESPONSE}${PLAIN}"
    fi
fi

# 7. 控制台结果展示
echo -e "\n${GREEN}====================================================${PLAIN}"
echo -e "${GREEN}    Sing-box Docker VLESS-Reality 部署完成！        ${PLAIN}"
echo -e "${GREEN}====================================================${PLAIN}"
echo -e "服务器 IP    : ${YELLOW}${SERVER_IP}${PLAIN}"
echo -e "监听端口     : ${YELLOW}${PORT}${PLAIN}"
echo -e "UUID         : ${YELLOW}${UUID}${PLAIN}"
echo -e "Public Key   : ${YELLOW}${PUBLIC_KEY}${PLAIN}"
echo -e "Short ID     : ${YELLOW}${SHORT_ID}${PLAIN}"
echo -e "SNI 伪装域名 : ${CYAN}${DEST_DOMAIN}${PLAIN}"
echo -e "----------------------------------------------------"
echo -e "客户端分享链接:"
echo -e "${GREEN}${VLESS_LINK}${PLAIN}"
echo -e "----------------------------------------------------"
echo -e "配置文件路径: ${CONFIG_DIR}/config.json"
echo -e "查看日志: ${YELLOW}docker logs -f sing-box${PLAIN}"
echo -e "${GREEN}====================================================${PLAIN}"
