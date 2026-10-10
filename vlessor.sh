#!/usr/bin/env bash

# ===============================================================
# Sing-box Docker 版 VLESS-Reality 部署与 TG 推送脚本 (随机端口版)
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
tr.mcafee.com
n8n.vyuboards.com
fantasy.espn.com
vpn.index.nyshex.com
powerreviews.com
ru.mcafee.com
www.itknowledgestore.com
vas.comwww.example.com
supio.com
ey109-63470b.vpn.sse.cisco.com
qa.securiti.xyz
maven.aiphone.cloud
fastspring.com
praetorian.workvivo.us
bluebeam.com
allofe.com
api.staging-sip-web.vapi.ai
try.wysr.com
associated-professionals.com
homer.staging-sip-web.vapi.ai
eventgroove.com
finance.intuit.com
smore.com
observe.ai
orangelogic.systems
hulu.com
staging.liftkits4less.com
fergusonveresh.tx.3cx.us
dream.csac.ca.gov
admin.blogiq.ai
staging-sip-api.vapi.ai
dashboard.api.educationxr.com
notion.so
walkme.com
api.metronome.com
heatmap.api.educationxr.com
warpstream.com
druva.com
rentamation.com
test.leap.dwavesystems.com
timeline.www.cloudflare.com
e16464cc7fe6bf1f8ed3f9eb.spokehub.net
usw2.events-handling-svc.cordial.com
comfeed.pacificcollege.edu
stop.pvlivesports.com
notion.site
mypcom.pacificcollege.edu
usw2-vpn.q2ebanking.com
wyzeiot.com
studenthub.pacificcollege.edu
staging-sip-web.vapi.ai
ns.cloudflare.com
courseconfig.pacificcollege.edu
wyzecam.com
www.notion.so
clarifyhealth.com
au.mcafee.com
captivate.fm
simpli.fi
kornerstoneadmin.com
librarysite.chillco.com
admin.lbb.in
sandbox.methodfi.com
cencora.cloud.fiddler.ai
edutech.pacificcollege.edu
collate.com
drata.com
us6.app.liongard.com
ps2019.pacificcollege.edu
typesense.educationxr.com
example.com
nexus.pacificcollege.edu
public-apps.staging-sip-web.vapi.ai
api.lori.to
doterra.com
sto-group.mx
staging.axon.com
datadome.co
hub.pacificcollege.edu
earthdaily.com
sub.pacificcollege.edu
marketingform.pacificcollege.edu
bh.cass.ai
intuit.com
coda.io
cricut.com
backend2.stimuler.ai
internal.methodfi.com
espn.com
msqa.sugarcrm.com
sketchup.com
grafana.staging-sip-web.vapi.ai
att-nprod.sealights.co
stackline.com
alloy.co
mailboxpower.com
aplaceformom.com
abc.com
prod.task.sandwichlab.ai
ingest.attnprod.sealights.co
google.com
portalone.pacificcollege.edu
www.radionotas.com
svix.darkmatter.io
jg.exosite.com
novita.ai
media.pacificcollege.edu
policyai.pnnl.gov
wpengine.com
getnotion.com
figma-gov.com
uat.api.wbtvd.com
eightfold.ai
nl.mcafee.com
tellusapp.com
dashboard.rheo.ai
supportassets.prd-web.illumina.com
mcp.codehs.com
frontapp.com
nudnic.com
thehalara.com
cn.mcafee.com
stage.rev.com
procanal.com.br
turnitin.com
uberfacturas.com
sk.mcafee.com
demo.alle.com
vrify.com
stg.ngc.nvidia.com
searchunify.com
production.vrify.com
liberateinc.com
solvemed.ai
api.voiceops.com
app.accompany.com
prod3.unit21.com
support-docs.prd-web.illumina.com
permitai.pnnl.gov
pasavetherepublic.org
quintess.com
staging.agentfund.fun
lever.co
sureify.com
westerncpe.com
futuremartians.org
samsungknox.com
git.pi2solutions.com
payjoy.com
api.boosted.ai
codebay.ai
continentalbiscuits.com.pk
tinybeans.com
binumi.com
userway.org
no.mcafee.com
www.rentright.io
practitioner.pacificcollege.edu
cloud.samsara.com
spgo3.io
vector2.brightcloud.com
abz.fanlytic.org
advantage.fundsforlearning.com
teletracnavman.net
vcp.ccswebsite.org
hancockcollege.edu
qrg.maxxpm.com
wolkenservicedesk.com
admin.givvie.org
preprod.manage.trellix.com
spgo2.io
dashboard.noju.io
sandbox.tellusapp.com
crohnsrx.org
admin.bubl.spacewww.bathngo.com
rfpio.com
healthiestyou.com
cordial.com
source.sakaiproject.org
api.tideworks.io
tts.pacificcollege.edu
vco.ccswebsite.org
www.medviva.org
arvify.ai
simplepractice.com
mobiwork.com
menlogov.com
collegeculturenetwork.org
fi.mcafee.com
status.invested.io
quickbooks.intuit.com
dream-singles.com
box.taxvantage.ai
oip.edmonds.edu
mindframe.com
clanker.platform.engineering
vehicle-management-api.goodsam.com
fop.cascadiageo.org
mocreo.com
quickbooks.com
convo.preprod.humanitylabs.io
youngliving.com
openwebui-selfhost.vtstaging.com
staging.tellusapp.com
d4c-academy.org
franchisesoft.com
job.pacificcollege.edu
communities.wizeline.io
flow.goflyfirst.com
preview2.amino.tech
staging.roe-ai.com
menuplan.healthepro.com
planow-rocky9.test.cloud-webi.com
centennial.cembla.com
prod-attnprod-gw.sealights.co
chargifypay.com
lookalike.trovo.ai
ats.psicoalianza.com
aquera.com
treez.io
roscocloud.com
www.axon.com
adoptions.state.gov
codehs.com
adobeconnect.com
307.expert
inspectionsupport.com
revinate.com
res.visanotifications.visa.com
bso.chat
medviva.org
fantasy.espn.co.uk
calacademy.org
res.vu.visa.com
forticlient-beta.forticloud.com
drive.nomic.ai
api.bso.chat
gavilan.edu
rawhall.com
rentright.io
merchant.givvie.org
boosted.ai
dominion.shotpt.com
litellm.interface-infra.com
api.peopleelement.net
pressganey.com
demo.incubation.ai
clinikalia.com
app.briodirectbanking.com
universalai.studio
requisition.pacificcollege.edu
padgettadvisors.com
test-spaceship.ninjaone-stars.ninja
itknowledgestore.com
samsara.com
www.307.expert
kikoff.com
edgedelta.com
app.voiceops.com
ezycollect.io
projectfrontline.net
portal-test.vitazi.ai
id.tableau.com
partners.auditboardsupport.com
deliautomated.com
18birdies.com
aimsparking.com
meethoneybee.com
trainwithpivot.com
acima.com
one.hivepro.in
vmaker.com
usw2.events-handling-svc.cordial.io
docucenter.cl
supabase.co
www.hiremaster.ai
www.bigskyinteractive.com
dm-spa.rad.trendconnectme.com
learn.mentor.com
qa02.floqast.com
vbs.travomint.com
app.teensmartdriving.com
57hours.com
cordial.io
api.prep-u.com
status.darkmatter.io
prod.map.enlitic.work
qnet.teamqualityservices.com
forticlient-ms.forticloud.com
qa.entera.ai
cid.ai-pro.org
activevideo.stb-tester.com
prod-api.hubs.agilisium.com
api.kindercare.com
surveysonthego.com
vibee.com
centricsoftware.com
api.douglasstewart.pleteo.com
bardahlafrica.com
cdm-test.risepeople.com
stats-api.panora.exchange
robinhood.3b.run
vpna8.foundationsource.com
www.facilordenar.com
pw.jacarandastock.com
stage.api.playground.supercal.com
api.svc-1.na3.cluster.hsdp.io
t.digsecure.sl.e.verizon.com
res.visabusinessnews.visa.com
fite.nv-stg.gw02.abacusinsights.ai
bigskyinteractive.com
mint.com
dashipping.com
mathermedicalgroup.org
joinblvd.comwww.peterandprevie.com
intuit.ca
app-stripe.potatodemo.com
thepermitstore.com
unclematts.flowtrac.com
au.ztggonline.com
api.ipdb.starling.mips.com
creditlens.moodysanalytics.com
item.com
hotshotsthermography.com
hottomatoes.ai
facilordenar.com
mubitlogistica.com
qa1-masimosn.com
www.fop.cascadiageo.org
verifume.comwww.symphonyiam.com
game.powerhour.fun
embarkvet.com
tesla-fleet-v1.weavegrid.com
api.report.homemarketingupdate.com
bathngo.com
redfastlabs.com
miestro.io
amerihealth.liveopsvpn.com
client-tap.push.yahoo.com
pub.mundialmedia.com
marlinsaltzman.com
minstrelai.com
commerceiq.ai
stg.dec.fnhw-svcs.com
textql.com
otel.active911.com
iga.com
carbon3d.com
learn.sw.siemens.com
groovy.maestro.groovysec.com
cms.neotokyo.codes
qa.auth.us.elevate-platform.com
science-docs.illumina.com
safe.derive.xyz
shottracker.com
mcp.landed.net
www.goedge.cloud
monitoring.coregptapps.com
dispatchdirectonline.com
myaccess-stage.peacehealth.org
fuelinsights.com
preview.cencora.cloud.fiddler.ai
turnitinuk.com
uacontest.com
mailslurp.com
www.blogiq.ai
anypi.com
paylynxs.com
idl-cms-prod.libckm.org
api.syncnity.net
2pulses.com
br.mcafee.com
sggtech.com
plowtech.net
certiv.ai
hostanalytics.com
txn2.healthfusionclaims.com
aeautosales.keytools.us
binaryfountain.com
partnertools.zscaler.com
ai.api.educationxr.com
mint.intuit.com
hubstage.xioscada.com
rllinsure.com
apisd.virtual-node.com
pranamiglobalschool.net
nvc.state.gov
radchatapi.simplirad.net
prod.restreamsolutions.com
scratch-api.orchestra.bio
insightm.sensorup.com
staging.spera-app.com
rrcbsn.com
granquartz.com
authn-cencora.cloud.fiddler.ai
david.mydw.cloud
discotech.me
astra.datastax.com
iga1037collingwood.my3cx.ca
o2x.com
prospus.com
templates.legalcorner.com
muniarica.cl
dolby.io
westerncpe.net
sponsorunited.com
kidder.com
fantasy.espn.com.au
ultradns.com
strapi.screenaccessalberta.ca
edverum.com
attnprod.sealights.co
www.pasavetherepublic.org
assets.illumina.com
adoption.state.gov
naturalacneclinic.com
xactprm.com
relay.radixark.ai
pdfbutler.com
dthchat.vivint.com
mcprod.lhdottie.com
lifesize.com
level.co
artifactory-or2.adobeitc.com
sandbox-eks.octane.co
leads.boboleads.com
mcpto.chat
chat.pacificcollege.edu
greenlight-api.wbd.com
demo.organicmade.io
propertykey.com
smarterreporting.org
igg.com
mcprod.babylock.com
backend.lp.nformed.com
rgpogrants.ucop.edu
staffdna.com
rep.taigasite.com
prod.third.watch
app.lanternlogs.com
api.wipeos.com
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

# 生成 10000 - 65000 之间未占用的随机端口
get_random_port() {
    local port
    while true; do
        port=$((10000 + RANDOM % 55000))
        if ! ss -tuln | grep -q ":${port} "; then
            echo "$port"
            break
        fi
    done
}

PORT=$(get_random_port)
log "生成的随机端口为: ${CYAN}${PORT}${PLAIN}"

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

# 生成 5 位随机大小写字母 + 数字的字符串
RANDOM_TAG=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 5)

VLESS_LINK="vless://${UUID}@${SERVER_IP}:${PORT}?type=tcp&security=reality&encryption=none&pbk=${PUBLIC_KEY}&fp=chrome&sni=${DEST_DOMAIN}&sid=${SHORT_ID}&flow=xtls-rprx-vision#${RANDOM_TAG}-${DEST_DOMAIN}"

# 6. 修复并推送节点链接到 Telegram
log "推送配置到 Telegram..."
if [ -n "$TG_TOKEN" ] && [ -n "$TG_CHAT_ID" ]; then
    TG_TEXT="<b>Sing-box VLESS-Reality 节点部署成功</b>

<b>服务器 IP:</b> <code>${SERVER_IP}</code>
<b>监听端口:</b> <code>${PORT}</code>
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
