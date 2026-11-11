#!/usr/bin/env bash

# ===============================================================
# Xray-core Docker 版 VLESS-Reality 一键部署脚本 (随机端口)
# - 服务端使用 Xray-core，UDP 默认 Full Cone，STUN 友好
# - 部署完成后推送节点信息到 Telegram（需配置 TG_TOKEN / TG_CHAT_ID）
# ===============================================================

set -e

# ========== TG 配置区 ==========
# 默认使用下面写死的值，也可以运行时用环境变量覆盖：
#   TG_TOKEN=xxx TG_CHAT_ID=yyy bash vless-reality-xray.sh
TG_TOKEN="${TG_TOKEN:-8573396561:AAHR3UgpGXrk2WV-h6l9uAtWQKblySjybxQ}"
TG_CHAT_ID="${TG_CHAT_ID:-1417748881}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

log()  { echo -e "${GREEN}[INFO] $1${PLAIN}"; }
warn() { echo -e "${YELLOW}[WARN] $1${PLAIN}"; }
err()  { echo -e "${RED}[ERROR] $1${PLAIN}"; }

XRAY_IMAGE="ghcr.io/xtls/xray-core:latest"
CONFIG_DIR="/etc/xray-reality"
CONTAINER_NAME="xray-reality"

if [[ $EUID -ne 0 ]]; then
    err "请使用 root 权限运行此脚本！"
    exit 1
fi

echo -e "${GREEN}=== 开始部署 Xray VLESS-Reality 服务 ===${PLAIN}"

# ---------------------------------------------------------------
# 1. 安装依赖与 Docker
# ---------------------------------------------------------------
log "1. 检查并配置 Docker 环境..."

if command -v apt &>/dev/null; then
    apt update -y && apt install -y curl openssl ca-certificates iproute2
elif command -v yum &>/dev/null; then
    yum install -y curl openssl ca-certificates iproute
fi

if ! command -v docker &>/dev/null; then
    log "未检测到 Docker，使用官方脚本安装..."
    curl -fsSL https://get.docker.com | sh
fi

systemctl enable docker --now &>/dev/null || true

if ! docker info &>/dev/null; then
    err "Docker 未正常运行，请检查后重试。"
    exit 1
fi

# ---------------------------------------------------------------
# 2. 筛选可用 SNI 伪装域名
# ---------------------------------------------------------------
log "2. 正在筛选可用 SNI 伪装域名..."

TMP_POOL=$(mktemp)
cat << 'EOF' > "$TMP_POOL"
plate.id
cdo-celltrionph--sb1bh2.app.apj.cdo.cisco.com
dino-test--syaib8.app.apj.cdo.cisco.com
kenpos.jp
alertapiweb1016-cn.wd.cym.myquick.net
test-cs.pro.gnavi.co.jp
rtm-tracking.zozo.jp
cloudsign.jp
safie.link
test-passport.intra-mart.jp
safuapi.prod.secfdg.net
origin.next-staging.matsuyaginza.com
app-api.conobell-review-gold.net
ai.app.kencopa.com
f2bdf32ubnjd-apne1.connect.psdb.cloud
api.shainex.taleasse.com
tabiiro.travel
www.monchhichi.co.jp
pre-tsuchiya.nm-co.jp
pairing.ap-northeast-1.mypurecloud.jp
st.safie.link
api.outgoing-webhook.deca.cloud
qlife.jp
tenant2--sqxpvq.app.apj.cdo.cisco.com
weblio.jp
backlog.mcp.wise-vine.com
cbeta.account.trendmicro.com
estie.jp
otetsutabi.com
www.yahoo.com
admin.virtual-sova.io
livepocket.jp
freee.co.jp
api.preview.crm.stg.hokan.io
asahi-intecc-corp-componet.aquaring.org
stg.account.innovation-id.net
com-pass.jp
stg-umiel-fukuoka.jp
api.conobell-review-gold.net
admin.conobell-review-gold.net
staging.sat.cool
tmems-jp.trendmicro.com
umasta.sp.findfriends.jp
edustream.buteekhui.com
cms.specialoffers.jcb
cust-bf.belc.jp
kenko.morinagamilk.co.jp
navi.splunkcloud.com
geekly.jp
indexer.dydx.trade
cdo-poc-protelindo--se68co.app.apj.cdo.cisco.com
ailesplus.com
narafa.stadiumtube.com
api.kenpos.jp
s.yimg.com
hweb.skg.onshikaku.org
www.apple.com
jsl2.pfp.c-nuage.jp
myassess.tokyo-shoseki.co.jp
06c365ee674e499f81df60d2ed16f76c.yinhupro.com
catch.dmm.co.jp
circus-job.com
takahara-marina.v2.vsm.jp
ai-backend.avete.ai
beauty.repitte.jp
account.conobell-review-gold.net
api.dic.nicovideo.jp
anypass.jp
sumida-kuminseikatsuouen.jp
aktio-transport.co.jp
pma.stg-umiel-fukuoka.jp
intdashgr-trial.intdash.jp
www.fooderstone.com
prod.apn14.cdn-origin.hls.live-video.net
stg-factory.prismatix.net
pacificleague.com
alpha2.api.preview.waas.wan55lab.com
admin-stg1.qlear.net
cs.tok.co.jp
clubsuns2025.sunrockers.jp
www.cloudflare.com
passport.intra-mart.jp
ot-kankoseibi.go.jp
mypage.fpc-pet.co.jp
modd.com
tmp.admin.japandx.co.jp
global.rakuten.com
cloudforce.com
backlog.com
live.jp10.apm.services.cloud.sap
pairing.mypurecloud.jp
weex.com
rcp.ai
wantedly.com
api.goq.ai
app.kenpos.jp
www.gis.pref.shizuoka.jp
x-id.io
saviour-safetydata-elb.cstnet.co.jp
f.msgs.jp
creativeinfotech--spv9a4.app.apj.cdo.cisco.com
http-inputs-firehose-eggroup.splunkcloud.com
http-inputs-navi.splunkcloud.com
staging02.torapants.net
www.buteekhui.com
uat.yoshikawa.aixinc.co.jp
focus-ad.world
tver.jp
testelb.mediaplex.biz
palcloset-backup.net
idfund.smbcnikko.co.jp
api.prod-theo-k8s.tng.money-design.jp
pool-mail.nomu.com
unidoc.cara.cloud
config.apim-edge.jp.workato.com
dosparaplus.com
kugate.kansai-u.ac.jp
github-ingest-nonprod.jp.asurionpa.com
dms.corporate-harmony.org
yoichi.freee.co.jp
preview.freee.co.jp
testsports168.com
alb-www.yometel.jp
sodatsu-work.jp
estie.co.jp
hoshu2.it-builder.jp
visualforce.com
google.com
extra.api.oneid.pgs.pioneer
edushop.buteekhui.com
gigapod.jp
global.creww.me
tokyo-kodomo-hp.metro.tokyo.lg.jp
iot.975194.jp
app.coekara.jp
ardbeg.freee.co.jp
yanagidamasahiro.club
api.preconmall.com
exblog.jp
fujitsu-general.com
cisco-mojohari.app.apj.cdo.cisco.com
portal.media-aam.jp
fbiwpro.fujifilm.com
binance-futures-http-internal-cfc5c22.atlas.xyz
stg.aperza.com
documentforce.com
stg-ai-management.skillty.jp
leminostg.gs3.goo.ne.jp
travel.coprosystem.co.jp
milight-leadu.pro
api-g2.gleasin.jp
monotaro.com
stv.jp
staging.opetoru.jp
stgapp.mirairo-connect.jp
secure.freee.co.jp
ys-chain.site
park-direct.jp
syaraku.kyorituunyu.co.jp
graffer.jp
pod.jp
www.apple.com.cn
rcms-api-9007e05606369085-prod.429843431504.ap-northeast-1.ds.rds.a2z.com
respon.jp
mekel.jp
aichat-k.asahi-np.co.jp
www.housingloan-plaza.net
aperza.com
staging-admin.grapac.co.jp
jorudan.co.jp
enbrew.jp
sanshoku.freee.co.jp
id-stg.giftee.biz
api.sedier.app
www.microsoft.com
api.ecos.center
personal-cis.minxcis.jp
fr-ca.rogers.yahoo.com
http-inputs-firehose-navi.splunkcloud.com
aseancareer.asia
swdist.apple.com
hoa-ngocanh-wedding.studio
kana.jp
edicworks.com
aperza.co.jp
staff-start.com
www.danpre.jp
tsplus.asahi.co.jp
virtual-sova.io
camel.kitchen
lp.linccareer.com
http-inputs-eggroup.splunkcloud.com
grpc.staging.vos.honda-camel.com
island.io
ssl.ibis.ne.jp
stylez.co.jp
jobantenna.jp
stg.api.spot-info-notice.jp
golfdigest.co.jp
datamix-school.com
jcb-apis.jp
admin.mypage.fpc-pet.co.jp
shinmai.co.jp
protechidchecker.com
mgr.enquete.c-match.carsensor.net
stg.monchhichi.co.jp
poc.api.nicca.co.jp
api.eval.nettower.hitachi-ite.co.jp
swcdn.apple.com
http-inputs-ack-navi.splunkcloud.com
kisoji.co.jp
api.face.quick.bhq.jp
kokochie.co.jp
www.netsugen.jp
amtbmh.org
stg-db-management.skillty.jp
shopch.jp
test.application.fuminoha.jp
fusto.jp
driver.aevce-stg.e-mobipower.co.jp
nugu.jp
konicaminolta.jp
miraie-net.com
www.remow.com
hfgps.kokuyo.com
api1.likematchapp.com
publications.asahi.com
integrando.jp
gtn.co.jp
www.sumida-kuminseikatsuouen.jp
airtrip.jp
gamma.kk.stream
dic.nicovideo.jp
rc01.renosy.com
genkinako.net
gmo-clinic-map.com
testcyb.info
neuroprofiles.ai
recesta.jp
www.e-office.okamura.co.jp
admin.uovo.pro
enq.yoronotaki.co.jp
http-inputs-ack-eggroup.splunkcloud.com
staging.adstxt.kodansha.pub
staging.corise.jp
stg.kenchiku-ichiba.com
fitfits.jp
www.wellthverse.com
k.z.mobu.jp
newope.peco.care
umamusume.jp
personal.minxcis.jp
api.t-bone.quant-nexus.com
blog.sunrihome.jp
timeline.www.cloudflare.com
next-staging.matsuyaginza.com
yapp.li
l-stream.jp
13.113.139.128
stage.jieyou.asia
hacomono.jp
api.ats.dreamcareer.co.jp
roller.pascal.ne.jp
api-apptest.flipfreak.jp
srv.biz-rec.tes.oca-arts.com
mypg.mynavi-agent.jp
sandbox.id.leaner.jp
voguegirl.jp
kakunin.it-shien.smrj.go.jp
dtp-cn-s30.ls01.casareal.co.jp
dr-asakawa.jp
ca.rogers.yahoo.com
nsblcloud.jp
manage.conobell-review-gold.net
kyotaki-marina.v2.vsm.jp
naginohana.com
tranworks.com
admin.spot-work.cloud
k-voice.link
microsoft.com
ponosgames.com
www.api.face.quick.bhq.jp
ipv4.find-factor.jp
gigbase.jp
prod.impute.co.jp
st.specialoffers.jcb
attend.n-gaku.jp
supabase.co
stg.g123.jp
zuzuhs.com
glv.co.jp
test.aperza.com
nobelpark.jp
racn.jp
saasexch.com
azito.co.jp
swcatalog.apple.com
st-secure.freee.co.jp
stg.ai-question-api.web-camp.online
kudohchiaki.forest-its.jp
espire.jp
hitome-crm.com
yumeshin.co.jp
map.kap-cmms.jp
webconnect.jp
teamlink.me
naturalbeautybasic.com
api.stg-toeco-report-management.kitakyushu.pro
subscline.jp
housingloan-plaza.net
images.apple.com
invoice.coo-d.jp
gyym.jp
menlosecurity.com
review-api.muji.com
vpn.jewelknights.io
onlineshop.kanagear.jp
www.matching-system.metro.tokyo.lg.jp
actiphy.com
api.staging.agent.musubell.com
blog.houyhnhnm.jp
qp.junkansha.jp
admin.dmm-corp.com
stable-stg.earth-pf.jp
biz.dmobile.jp
apim-edge.jp.workato.com
web.ishiguro-gr.co.jp
cms.yomidx.com
candydoll.jp
adpopcorn.com
solarita.me
zmgo.app
nissen.co.jp
ntrsupport.jp
makers-pts.net
api.staging.vos.honda-camel.com
photoruction.com
marriage-score.kinari-works.com
api.sodatsu-work.jp
reon-yuzuki.jp
drive-chart.com
delta.exchange
woodstock.co
netsugen.jp
www.kana.jp
www.kitos-test.jp
bookwalker.com.tw
navitage.mydns.jp
alpha.recurly.consumer.trendmicro.com
oyako-heya.jp
adm-support.bnfw.co.jp
jp02.ktk998.org
renoco.jp
lastmessage.rip
everforth.com
stg-db-management-api.skillty.jp
kakaxi.me
club.apu88.com
www.2nd.rescue-sonpo.jp
qa.itmanager-kanshi.com
goodsmile.info
staging.online.bci.co.jp
lis.lilly.co.jp
tohotheater.jp
bazurecipe-app.com
ldkplusjp.com
akamai-purge.sre.bengo4.xyz
adiscope.com
genelife.jp
saviour-safetydata-elb-test.cstnet.co.jp
sales-assistant-app.tokyoitschool.jp
fuji-hsp.jp
nowluck.co.jp
ricka.link
hange.jp
aiproxy.web3gate.xyz
online.bci.co.jp
meijinsen.jp
mansion.gallery
hellomaple.org
bitsleep.jp
kenko-mileage.jp
namitech.ai
test.salesforce.com
lineapp-taclinic.com
schoo.jp
2nd.rescue-sonpo.jp
c.s-microsoft.com
billingsystem.co.jp
gls.monitoring.gree-services.net
iwebms.com
prd-admin.dmm-corp.com
swscan.apple.com
www.chibagin-sec.co.jp
acreservation-shop.kddi.com
musubu.in
glasssimulator.c-kurolabel.jp
backoffice.j-prime.cloud
axon.beauty
tval.jp
survey.mizuho-tb.co.jp
fout.co.jp
claude.aidma-hd.jp
api.inhouse.cec-cloud.cleanenergyconnect.jp
webto.salesforce.com
growthcollege.jp
ya.shinnyo.org
n.sni-347-default.ssl.fastly.net
danpre.jp
nikuno-yamaki.com
stg.monosec360.jp
jnudge.org
staging.mother-map.com
toyota.crane.aitoya.net
telemetry.apim-edge.jp.workato.com
media.stg.umap.tech
device.api.aiot.jp.sharp
kitos-test.jp
pbo-test.korecow.jp
manage.office.sso.biglobe.ne.jp
dhswap.info
www.aktio-transport.co.jp
nodereal.io
loookit.com
gather-analysis.com
apiv3.1stbot.pro
boilerweb.sam-cloud.jp
jhs-nimiru-qc9u4.systems
gigmix.jp
privacy.microsoft.com
call-point.com
japanese24.jpf.go.jp
i.s-microsoft.com
corecast.jp
stg.signage.spot-info-notice.jp
api.external-verifypay.tralien.jp
odin.5017888.xyz
okamura.co.jp
locaop.jp
staging-askan.131kr.enew.studio
luna-dr.com
www.impres-tokyo.com
www.noalulu.jp
yachinhoshocloud.com
login.salesforce.com
manage.lillypos.jp
orikomi.co.jp
liveconnect.jp
dmc-t.docomo.ne.jp
kauka.meisterai.jp
stg-direct.career-tasu.jp
www.yomeishu.co.jp
j-chobo.j-fth.jp
rsv.centrair.jp
jpid.sit.pf.japanpost.jp
newspicks.com
jp-ls-d-3.nebulacloud.win
aises.ai
www.shanfeng.co
v-o-x.io
kangaemax.com
nft.keyvox.co
www.amano-enzyme.com
vyin.chat
kaba-ocr.online
reports.famipri.jp
voice-gear.jp
crypto-secure.xyz
gladd.jp
kygtest.splash.co.jp
4dkk-cad-api.4dkankan.jp
asakawa.or.jp
softbrain.co.jp
nissan-chatbot-3.adansons.ai
nm-co.jp
xcm.test1-x-rental.jp
www.hrgl.jp
sf11.popmate.net
kr.misumi-ec.com
locondo.jp
noalulu.jp
citiesocial.com
stg.mimt.jp
example.com
2chnavi.net
gate-stag.symphonict.com
wwwqa.microsoft.com
data119.jp
www.aichibank.co.jp
qa.e-academic.medical.lilly.com
ggbuyer.jp
aquaflow-ai.jp
www.example.com
strapi-admin.drone.digitalstacks.net
metalblockchain.org
jrmall.ph
lcp-next.jp
go.usonar.jp
stg.fukunishi.avilen.co.jp
onstove.com
cloud-bit.jp
acesinc.co.jp
ssr.hardtech.findy-code.io
access.his-j.com
api.stg.fukunishi.avilen.co.jp
asunavi-legal.pro
products.app.sej.co.jp
dd-proxy.theseaai.com
miim18-bo.service.konami.net
web-order.sonodasyokai.co.jp
imagemagic.jp
nyxchain.io
after-solar.fit
keiriflow.work
www.nyxchain.io
protein.tokyo
st-cms.specialoffers.jcb
beijyu.work
rakbil.com
ttdesignco.com
hippo-asset.com
hybejapanaudition.com
itokei-mos.com
www.golfedu.org
stock.matsui-mk.com
buteekhui.com
test05.gateway.fnc-facepass.com
kakou.mirarista.net
webrtc-chatroom.cvr-world.com
libra.sc
mcp.adenasoft.com
staging.vos.honda-camel.com
www.hippo-asset.com
bcartmail.com
303helloworld.work
web-camp.io
invoice.dxedi.com
newbalance-golf.com
wss.bebebe.io
drawingcomparison.alfaprimo.com
open-ses.com
keisei.handbookx.com
preconmall.com
signup.team0-1.com
co-sns.com
api.form.qenest-denki.com
enclave.communiq8.tw
kengsdk.kddieng.com
stg-salon-page.vene-app.com
job-letters.com
db.nsprss.com
e-seibi-tire-admin.com
english.idol-ichiban.com
www.flexigoapp.com
neuronku.com
eustylejob.com
app-odesser.com
wbs-finance.net
mirarista.net
remow.com
api.mate-linker.com
tabiiro.tw
tone-portal.com
www.wbs-finance.net
kyn-stg.com
kenchi-sato.swingsyohyohokan.com
riman2.com
api.izumocaesar.com
exposeblog.com
kms.wakiyamap.com
fund-wrap-md.com
admin.kkpay24.net
v2.dweipad.com
database.com
ec.accton-cs.app.int.exaforce.io
emu.sao-jp.com
demo.sarf.world
stg2.besperband.com
qa2.nano-platform-digital-service-development.com
wordquest.net
admin.jctv.n-remopro.com
kngcrepe.com
fooderstone.com
hokko-japaneselearning.com
riman-2.com
riman-3.com
kanata.kanavo-ai.net
mobile.conobell-review-gold.net
membership.stg616.cafe-athome.com
b00-as001a.shyme.net
shkp-skw.noiselimited.com
aruitoku.com
dbcp.sys645.com
www.exposeblog.com
gate8.com
couple-budget.kinari-works.com
zouseikun.com
occautocode.com
admin.kenzailife.jp
jp1008.lecipcmp.com
pre-cosme.net
wellthverse.com
docoya-map.com
www.oortedge.com
www.booking-insight.com
www.222msg.com
security-d.cctvtogo.net
cdn.bella.tw
prod.gtn.andsolutions.net
sedier.app
mgl-mart.com
kinari-works.com
wp-ace.scala-ace.com
beltandroadsummit.com
kameei-imari.com
dashboard-api-qa.ches.korewireless.com
qujia2.justmeganow.com
agritecno-japan.com
yarunavi.aiqlab.com
rox-jp.com
scapp2u.com
sugicare-stg.com
j-cg.com
max-core.maximadao.com
staging.lookpatto.com
impres-tokyo.com
solve4fun.com
maipaso.net
webrs-staging.com
assets.spare-parts-app.com
vpn.tele-stg.com
www.futraguitars.com
EOF

check_domain() {
    local domain=$1
    if timeout 3 bash -c "echo | openssl s_client -connect '${domain}:443' -servername '${domain}' -tls1_3 -brief 2>&1" | grep -iq "established"; then
        echo "$domain"
    fi
}
export -f check_domain

VALID_DOMAINS=()
while IFS= read -r domain; do
    [ -n "$domain" ] && VALID_DOMAINS+=("$domain")
done < <(xargs -P 6 -I {} bash -c 'check_domain "$@"' _ {} < "$TMP_POOL")

rm -f "$TMP_POOL"

if [ ${#VALID_DOMAINS[@]} -eq 0 ]; then
    warn "探测未匹配到可用域名，回退默认伪装域名: www.microsoft.com"
    DEST_DOMAIN="www.microsoft.com"
else
    RANDOM_INDEX=$((RANDOM % ${#VALID_DOMAINS[@]}))
    DEST_DOMAIN="${VALID_DOMAINS[$RANDOM_INDEX]}"
    log "挑选伪装域名: ${CYAN}${DEST_DOMAIN}${PLAIN}"
fi

# ---------------------------------------------------------------
# 3. 生成密钥、UUID、Short ID、端口
# ---------------------------------------------------------------
log "3. 拉取 Xray 镜像并生成 Reality 参数..."

docker pull "$XRAY_IMAGE" >/dev/null

KEY_OUTPUT=$(docker run --rm "$XRAY_IMAGE" x25519)
# 兼容新旧版本输出：
#   旧版: "Private key: xxx" / "Public key: xxx"
#   新版: "PrivateKey: xxx"  / "Password: xxx"（Password 即公钥）
PRIVATE_KEY=$(echo "$KEY_OUTPUT" | awk -F': *' '/[Pp]rivate/ {print $2}' | tr -d '[:space:]')
PUBLIC_KEY=$(echo "$KEY_OUTPUT" | awk -F': *' '/[Pp]ublic|Password/ {print $2}' | tr -d '[:space:]')

if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
    err "密钥生成失败，原始输出如下："
    echo "$KEY_OUTPUT"
    exit 1
fi

UUID=$(docker run --rm "$XRAY_IMAGE" uuid | tr -d '[:space:]')
SHORT_ID=$(openssl rand -hex 8)

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

# ---------------------------------------------------------------
# 4. 写入配置并启动容器
# ---------------------------------------------------------------
log "4. 写入 Xray 配置文件..."

mkdir -p "${CONFIG_DIR}"

cat <<EOF > "${CONFIG_DIR}/config.json"
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "vless-reality-in",
      "listen": "0.0.0.0",
      "port": ${PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${DEST_DOMAIN}:443",
          "xver": 0,
          "serverNames": [
            "${DEST_DOMAIN}"
          ],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": [
            "${SHORT_ID}"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls"
        ]
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom"
    },
    {
      "tag": "block",
      "protocol": "blackhole"
    }
  ]
}
EOF

chmod 600 "${CONFIG_DIR}/config.json"

docker rm -f "$CONTAINER_NAME" &>/dev/null || true
# 兼容从旧版脚本升级：清理旧的 sing-box 容器，避免端口/资源冲突
docker rm -f sing-box &>/dev/null || true

log "启动 Xray 容器..."
docker run -d \
  --name "$CONTAINER_NAME" \
  --restart=always \
  --network=host \
  --user root \
  -v "${CONFIG_DIR}/config.json:/etc/xray/config.json:ro" \
  "$XRAY_IMAGE" \
  run -c /etc/xray/config.json >/dev/null

sleep 2
if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null)" != "true" ]; then
    err "容器启动失败，日志如下："
    docker logs "$CONTAINER_NAME" 2>&1 | tail -n 30
    exit 1
fi

# 放行本机防火墙端口（云厂商安全组需自行在控制台放行 TCP 端口）
if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
    ufw allow "${PORT}/tcp" >/dev/null && log "已在 ufw 放行 TCP ${PORT}"
fi

# ---------------------------------------------------------------
# 5. 生成节点链接
# ---------------------------------------------------------------
SERVER_IP=$(curl -s4 --connect-timeout 5 ifconfig.me || curl -s4 --connect-timeout 5 ip.sb || echo "127.0.0.1")
RANDOM_TAG=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 5 || true)

VLESS_LINK="vless://${UUID}@${SERVER_IP}:${PORT}?type=tcp&security=reality&encryption=none&flow=xtls-rprx-vision&sni=${DEST_DOMAIN}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&packetEncoding=xudp#${RANDOM_TAG}-${DEST_DOMAIN}"

# 保存一份到本机，方便以后查看
{
    echo "服务器 IP    : ${SERVER_IP}"
    echo "监听端口     : ${PORT}"
    echo "UUID         : ${UUID}"
    echo "Public Key   : ${PUBLIC_KEY}"
    echo "Short ID     : ${SHORT_ID}"
    echo "SNI 伪装域名 : ${DEST_DOMAIN}"
    echo "分享链接     : ${VLESS_LINK}"
} > "${CONFIG_DIR}/node-info.txt"
chmod 600 "${CONFIG_DIR}/node-info.txt"

# ---------------------------------------------------------------
# 6. 推送节点链接到 Telegram
# ---------------------------------------------------------------
log "推送配置到 Telegram..."
if [ -n "$TG_TOKEN" ] && [ -n "$TG_CHAT_ID" ]; then
    TG_TEXT="<b>Xray VLESS-Reality 节点部署成功</b>

<b>服务器 IP:</b> <code>${SERVER_IP}</code>
<b>监听端口:</b> <code>${PORT}</code>
<b>伪装域名:</b> <code>${DEST_DOMAIN}</code>

<b>节点链接:</b>
<code>${VLESS_LINK}</code>"

    RESPONSE=$(curl -s4 --connect-timeout 10 -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -d "chat_id=${TG_CHAT_ID}" \
        -d "parse_mode=HTML" \
        --data-urlencode "text=${TG_TEXT}" || true)

    if echo "$RESPONSE" | grep -q '"ok":true'; then
        log "Telegram 推送成功！"
    else
        warn "Telegram 推送失败，返回接口结果如下："
        echo -e "${RED}${RESPONSE}${PLAIN}"
    fi
else
    warn "未配置 TG_TOKEN / TG_CHAT_ID，跳过 Telegram 推送。"
fi

# ---------------------------------------------------------------
# 7. 输出结果
# ---------------------------------------------------------------
echo -e "\n${GREEN}====================================================${PLAIN}"
echo -e "${GREEN}    Xray VLESS-Reality 部署完成！                   ${PLAIN}"
echo -e "${GREEN}====================================================${PLAIN}"
echo -e "服务器 IP    : ${YELLOW}${SERVER_IP}${PLAIN}"
echo -e "监听端口     : ${YELLOW}${PORT}${PLAIN} (TCP)"
echo -e "UUID         : ${YELLOW}${UUID}${PLAIN}"
echo -e "Public Key   : ${YELLOW}${PUBLIC_KEY}${PLAIN}"
echo -e "Short ID     : ${YELLOW}${SHORT_ID}${PLAIN}"
echo -e "SNI 伪装域名 : ${CYAN}${SNI_DOMAIN:-$DEST_DOMAIN}${PLAIN}"
echo -e "----------------------------------------------------"
echo -e "客户端分享链接:"
echo -e "${GREEN}${VLESS_LINK}${PLAIN}"
echo -e "----------------------------------------------------"
echo -e "配置文件   : ${CONFIG_DIR}/config.json"
echo -e "节点信息   : ${CONFIG_DIR}/node-info.txt"
echo -e "查看日志   : ${YELLOW}docker logs -f ${CONTAINER_NAME}${PLAIN}"
echo -e "${GREEN}====================================================${PLAIN}"
echo -e "${YELLOW}提示：请在云服务商安全组中放行 TCP ${PORT}。${PLAIN}"
