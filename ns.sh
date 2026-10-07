#!/bin/bash
set -e

SRC_DOMAIN="$1"
DST_DOMAIN="$2"

[ -z "$SRC_DOMAIN" ] && echo "Usage: $0 source.com target.com" && exit 1
[ -z "$DST_DOMAIN" ] && echo "Usage: $0 source.com target.com" && exit 1

ZONE="/etc/bind/zones/${DST_DOMAIN}.zone"
CONF="/etc/bind/named.conf.local"

# 安装必要软件
apt update
DEBIAN_FRONTEND=noninteractive apt install -y bind9 bind9utils dnsutils curl

mkdir -p /etc/bind/zones

########################################
# 获取本机IP和随机IP
########################################
IPAddrRRR1=$(curl -s checkip.amazonaws.com)

# 从源域名随机取一个A记录，生成随机后两段
ip=$(dig +short A ${SRC_DOMAIN} | shuf -n 1)
o1=$(echo $ip | cut -d. -f1)
o2=$(echo $ip | cut -d. -f2)
o3=$((RANDOM % 254 + 1))
o4=$((RANDOM % 254 + 1))
IPAddrRRR2="${o1}.${o2}.${o3}.${o4}"

# Wildcard IP
WildRecord=${IPAddrRRR1}

########################################
# SERIAL
########################################
SERIAL=$(date +%Y%m%d00)

########################################
# 写SOA和NS头
########################################
cat <<EOF > "$ZONE"
\$TTL 60
@ IN SOA RRR1.${DST_DOMAIN}. admin.${DST_DOMAIN}. (
    ${SERIAL}
    3600
    1800
    604800
    86400
)

@ IN NS RRR1.${DST_DOMAIN}.
@ IN NS RRR2.${DST_DOMAIN}.
@       IN      MX  10  mail.${DST_DOMAIN}.
*       IN      MX  10  mail.${DST_DOMAIN}.
RRR1 IN A ${IPAddrRRR1}
RRR2 IN A ${IPAddrRRR2}


EOF

########################################
# 抓取源域名记录
########################################
echo "===> Fetching records from ${SRC_DOMAIN}"

# A记录
dig +short A ${SRC_DOMAIN} | while read ip; do
    echo "@ IN A ${ip}" >> "$ZONE"
done

# CNAME
dig +short CNAME ${SRC_DOMAIN} | while read cname; do
    echo "@ IN CNAME ${cname}" >> "$ZONE"
done

# MX
dig +short MX ${SRC_DOMAIN} | while read line; do
    prio=$(echo $line | awk '{print $1}')
    host=$(echo $line | awk '{print $2}')
    echo "@ IN MX ${prio} ${host}" >> "$ZONE"

    # MX 对应 A记录
    dig +short A ${host} | while read ip; do
        echo "${host%.} IN A ${ip}" >> "$ZONE"
    done
done

# TXT
dig +short TXT ${SRC_DOMAIN} | while read txt; do
    # 去掉首尾引号
    txt_clean=$(echo "$txt" | sed 's/^"//;s/"$//')
    echo "@ IN TXT \"${txt_clean}\"" >> "$ZONE"
done

########################################
# 强制覆盖规则
########################################
echo "" >> "$ZONE"
echo "; ===== FORCE OVERRIDE =====" >> "$ZONE"

# 泛解析
echo "* IN A ${WildRecord}" >> "$ZONE"

########################################
# 权限
########################################
chown -R bind:bind /etc/bind/zones
chmod -R 755 /etc/bind/zones

########################################
# 写配置文件
########################################
grep -q "zone \"${DST_DOMAIN}\"" $CONF || cat >> $CONF <<EOF

zone "${DST_DOMAIN}" {
    type master;
    file "${ZONE}";
};
EOF

########################################
# 检查并重启
########################################
named-checkconf
named-checkzone "${DST_DOMAIN}" "${ZONE}"

systemctl restart bind9

########################################
# 输出信息
########################################
echo "=================================="
echo "源域名: ${SRC_DOMAIN}"
echo "目标域名: ${DST_DOMAIN}"
echo "RRR1: ${IPAddrRRR1}"
echo "RRR2: ${IPAddrRRR2}"
echo "WildRecord: ${WildRecord}"
echo "=================================="