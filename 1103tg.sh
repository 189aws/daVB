#!/usr/bin/env bash
# =============================================================================
#  tg-mail-install.sh  —  Debian 12 一键部署「收信 → Telegram 推送」系统
#  架构: Postfix(只收不发, catch-all) --pipe--> Python 处理程序 --> Telegram Bot
#
#  用法:
#    交互式安装:   sudo bash tg-mail-install.sh
#    非交互安装:   sudo TG_BOT_TOKEN="123:ABC" TG_CHAT_ID="123456789" \
#                       bash tg-mail-install.sh
#    发送自检邮件: sudo bash tg-mail-install.sh test
#
#  说明: 不限制域名。任意域名只要 A 记录(或 MX)指向本机公网 IPv4，
#        发往 任意名字@该域名 的邮件都会被接收并推送到 Telegram。
#    卸载:         sudo bash tg-mail-install.sh uninstall
# =============================================================================
set -Eeuo pipefail

INSTALL_DIR=/opt/tg-mail
CONF_DIR=/etc/tg-mail
CONF_FILE=$CONF_DIR/config.env
HANDLER=$INSTALL_DIR/tg_mail_handler.py
DOMAINS_FILE=/etc/postfix/tg_any_domain
RCPT_FILE=/etc/postfix/tg_recipients
SVC_USER=tgmail

# ---- 写死的 Telegram 配置 (如需临时覆盖，可用环境变量传入) ----
TG_BOT_TOKEN="${TG_BOT_TOKEN:-8847461870:AAE2_ZWvgkAltdHy8y4QxYhWVGDk85JVwZs}"
TG_CHAT_ID="${TG_CHAT_ID:-1417748881}"

R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[34m'; N=$'\e[0m'
info() { echo "${B}[INFO]${N} $*"; }
ok()   { echo "${G}[ OK ]${N} $*"; }
warn() { echo "${Y}[WARN]${N} $*"; }
die()  { echo "${R}[FAIL]${N} $*" >&2; exit 1; }

trap 'die "脚本在第 $LINENO 行出错退出"' ERR

need_root() { [[ $EUID -eq 0 ]] || die "请使用 root 运行 (sudo bash $0)"; }

check_os() {
  . /etc/os-release 2>/dev/null || true
  if [[ "${ID:-}" != "debian" ]]; then
    warn "当前系统不是 Debian (${PRETTY_NAME:-unknown})，脚本按 Debian 12 编写，继续可能有问题"
  elif [[ "${VERSION_ID:-}" != "12" ]]; then
    warn "当前为 Debian ${VERSION_ID:-?}，脚本按 Debian 12 测试"
  fi
}

ask() { # ask VAR "提示"
  local var=$1 prompt=$2 val=""
  [[ -n "${!var:-}" ]] && return 0
  read -r -p "$prompt" val </dev/tty || true
  printf -v "$var" '%s' "$val"
}

valid_domain() {
  [[ "$1" =~ ^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$ ]]
}

# ----------------------------------------------------------------------------
prep_packages() {
  info "更新软件源并安装基础依赖..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y >/dev/null
  apt-get install -y curl ca-certificates python3 ssl-cert >/dev/null
  ok "基础依赖就绪"
}

load_old_conf() {
  if [[ -f $CONF_FILE ]]; then
    [[ -z "${TG_BOT_TOKEN:-}" ]] && TG_BOT_TOKEN=$(grep -E '^TG_BOT_TOKEN=' "$CONF_FILE" | cut -d= -f2- || true)
    [[ -z "${TG_CHAT_ID:-}"   ]] && TG_CHAT_ID=$(grep -E '^TG_CHAT_ID=' "$CONF_FILE" | cut -d= -f2- || true)
  fi
  return 0
}

detect_chat_id() {
  local resp
  resp=$(curl -fsS --max-time 15 "https://api.telegram.org/bot${TG_BOT_TOKEN}/getUpdates") || return 1
  python3 - "$resp" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
ids = []
for u in d.get("result", []):
    m = u.get("message") or u.get("channel_post") or u.get("my_chat_member") or {}
    c = m.get("chat")
    if c:
        ids.append(c["id"])
print(ids[-1] if ids else "")
PY
}

collect_input() {
  echo
  echo "================ 配置信息 ================"
  load_old_conf
  ask TG_BOT_TOKEN "Telegram Bot Token (从 @BotFather 获取): "
  [[ -n "$TG_BOT_TOKEN" ]] || die "未填写 Bot Token"

  local resp uname
  resp=$(curl -fsS --max-time 15 "https://api.telegram.org/bot${TG_BOT_TOKEN}/getMe") \
    || die "Bot Token 无效，或本机无法访问 api.telegram.org"
  uname=$(python3 -c 'import json,sys;print(json.load(sys.stdin)["result"]["username"])' <<<"$resp")
  ok "Bot 验证通过: @${uname}"

  ask TG_CHAT_ID "接收通知的 Chat ID (多个用逗号分隔；不知道直接回车自动获取): "
  if [[ -z "$TG_CHAT_ID" ]]; then
    echo "请现在打开 Telegram，给 @${uname} 发送任意一条消息（如 /start），然后回到这里按回车..."
    read -r </dev/tty || true
    TG_CHAT_ID=$(detect_chat_id || true)
    [[ -n "$TG_CHAT_ID" ]] || die "没能自动获取 Chat ID，请确认已给 Bot 发过消息，或手动指定 TG_CHAT_ID"
    ok "自动获取 Chat ID: $TG_CHAT_ID"
  fi
  TG_CHAT_ID=$(echo "$TG_CHAT_ID" | tr -d ' ')
}

# ----------------------------------------------------------------------------
get_fqdn() {
  local h
  h=$(hostname -f 2>/dev/null || hostname)
  [[ "$h" == *.* ]] || h="${h}.localdomain"
  echo "$h"
}

install_postfix() {
  info "安装 Postfix (会自动替换 Debian 默认的 exim4)..."
  export DEBIAN_FRONTEND=noninteractive
  local first; first=$(get_fqdn)
  echo "postfix postfix/mailname string $first"            | debconf-set-selections
  echo "postfix postfix/main_mailer_type select Internet Site" | debconf-set-selections
  apt-get install -y postfix >/dev/null
  ok "Postfix 已安装"
}

install_handler() {
  info "部署 Telegram 转发程序..."
  id "$SVC_USER" &>/dev/null || useradd --system --no-create-home --shell /usr/sbin/nologin "$SVC_USER"
  mkdir -p "$INSTALL_DIR" "$CONF_DIR"

  cat > "$HANDLER" <<'PYEOF'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Postfix pipe handler: 把收到的邮件推送到 Telegram。
argv: <sender> <recipient>;  stdin: 完整原始邮件
退出码: 0 成功; 75 临时失败(Postfix 会稍后重试)
"""
import sys, re, json, html, uuid, time, syslog
import urllib.request, urllib.error
from email import message_from_bytes, policy

CONF = "/etc/tg-mail/config.env"
EX_TEMPFAIL = 75
MAX_EML = 45 * 1024 * 1024

syslog.openlog("tg-mail", 0, syslog.LOG_MAIL)


def log(msg):
    syslog.syslog(syslog.LOG_INFO, msg)


def load_conf():
    conf = {}
    with open(CONF, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            conf[k.strip()] = v.strip().strip('"').strip("'")
    return conf


def tg_call(token, method, payload=None, files=None):
    url = "https://api.telegram.org/bot%s/%s" % (token, method)
    if files:
        boundary = uuid.uuid4().hex
        body = b""
        for k, v in (payload or {}).items():
            body += ('--%s\r\nContent-Disposition: form-data; name="%s"\r\n\r\n%s\r\n'
                     % (boundary, k, v)).encode("utf-8")
        for k, (fname, content, ctype) in files.items():
            body += ('--%s\r\nContent-Disposition: form-data; name="%s"; filename="%s"\r\n'
                     'Content-Type: %s\r\n\r\n' % (boundary, k, fname, ctype)).encode("utf-8")
            body += content + b"\r\n"
        body += ("--%s--\r\n" % boundary).encode()
        req = urllib.request.Request(
            url, data=body,
            headers={"Content-Type": "multipart/form-data; boundary=" + boundary})
    else:
        req = urllib.request.Request(
            url, data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


INVISIBLE = re.compile("[\u200b\u200c\u200d\u2060\ufeff\u034f\u00ad]")


def html_to_text(s):
    s = re.sub(r"(?s)<!--.*?-->", "", s)
    s = re.sub(r"(?is)<(script|style|title)\b[^>]*>.*?</\1\s*>", "", s)
    s = re.sub(r"(?is)<head\b[^>]*>.*?</head\s*>", "", s)

    def _link(m):  # 保留链接：「文字 (URL)」，重置密码/验证邮件的关键内容
        href = html.unescape(m.group(1)).strip()
        label = html.unescape(re.sub(r"(?s)<[^>]+>", "", m.group(2))).strip()
        if href.lower().startswith(("http://", "https://")):
            return "%s (%s)" % (label, href) if label and label != href else href
        return label

    s = re.sub(r"(?is)<a\b[^>]*?href\s*=\s*[\"']([^\"']*)[\"'][^>]*>(.*?)</a\s*>", _link, s)
    s = re.sub(r"(?i)<br\s*/?>|</(p|div|tr|li|h[1-6]|table)\s*>", "\n", s)
    s = re.sub(r"(?i)</t[dh]\s*>", " ", s)
    s = re.sub(r"(?s)<[^>]+>", "", s)
    s = html.unescape(s).replace("\xa0", " ")
    s = INVISIBLE.sub("", s)
    s = re.sub(r"[ \t\r\f\v]+", " ", s)
    s = re.sub(r"\n +", "\n", s)
    s = re.sub(r"\n{3,}", "\n\n", s)
    return s.strip()


def part_text(part):
    try:
        return part.get_content()
    except Exception:
        pass
    try:
        payload = part.get_payload(decode=True) or b""
        cs = part.get_content_charset() or "utf-8"
        try:
            return payload.decode(cs, "replace")
        except LookupError:
            return payload.decode("utf-8", "replace")
    except Exception:
        return ""


def extract_body(msg):
    """遍历所有 MIME 部分，收集 text/plain 与 text/html，优先用有内容的纯文本，否则用 HTML 转文字。"""
    plains, htmls = [], []
    for part in msg.walk():
        if part.is_multipart():
            continue
        if part.get_content_disposition() == "attachment" and part.get_filename():
            continue  # 真正的附件，不当正文
        ctype = part.get_content_type()
        if ctype == "text/plain":
            t = part_text(part).strip()
            if t:
                plains.append(t)
        elif ctype == "text/html":
            t = html_to_text(part_text(part))
            if t:
                htmls.append(t)
    plain = "\n\n".join(plains)
    htm = "\n\n".join(htmls)
    if plain and (len(plain) >= 30 or not htm):
        return plain
    if htm:
        return htm
    if plain:
        return plain
    if not msg.is_multipart():  # 单部分且非 text/* 的情况，尽力解码
        try:
            payload = msg.get_payload(decode=True) or b""
            return payload.decode(msg.get_content_charset() or "utf-8", "replace").strip()
        except Exception:
            pass
    return ""


def structure(msg):
    try:
        return ", ".join(p.get_content_type() for p in msg.walk())
    except Exception:
        return "unknown"


def hdr(msg, name):
    try:
        v = msg[name]
        return str(v) if v is not None else ""
    except Exception:
        return ""


def build(rcpt, sender, subject, date, atts, body, as_html):
    esc = html.escape if as_html else (lambda x: x)
    b_o, b_c = ("<b>", "</b>") if as_html else ("", "")
    c_o, c_c = ("<code>", "</code>") if as_html else ("", "")
    lines = [
        "📧 %s新邮件%s" % (b_o, b_c),
        "%s收件人：%s%s%s%s" % (b_o, b_c, c_o, esc(rcpt), c_c),
        "%s发件人：%s%s" % (b_o, b_c, esc(sender)),
        "%s主题：%s%s" % (b_o, b_c, esc(subject)),
    ]
    if date:
        lines.append("%s时间：%s%s" % (b_o, b_c, esc(date)))
    if atts:
        shown = ", ".join(atts[:10]) + (" 等%d个" % len(atts) if len(atts) > 10 else "")
        lines.append("📎 附件：%s" % esc(shown))
    lines.append("──────────")
    lines.append(esc(body) if body else "(无正文)")
    return "\n".join(lines)


def fit(rcpt, sender, subject, date, atts, body, as_html, limit=4000):
    body = body[:3000]
    while True:
        text = build(rcpt, sender, subject, date, atts, body, as_html)
        if len(text) <= limit or len(body) < 50:
            return text[:4096]
        body = body[: int(len(body) * 0.8)] + "…"


def send_message(token, chat_id, args):
    try:
        tg_call(token, "sendMessage", {
            "chat_id": chat_id,
            "text": fit(*args, as_html=True),
            "parse_mode": "HTML",
            "disable_web_page_preview": True,
        })
    except urllib.error.HTTPError as e:
        if e.code == 400:  # HTML 解析失败 → 退回纯文本
            tg_call(token, "sendMessage", {
                "chat_id": chat_id,
                "text": fit(*args, as_html=False),
                "disable_web_page_preview": True,
            })
        else:
            raise


def main():
    env_sender = sys.argv[1] if len(sys.argv) > 1 else ""
    env_rcpt = sys.argv[2] if len(sys.argv) > 2 else ""
    raw = sys.stdin.buffer.read()

    try:
        conf = load_conf()
        token = conf["TG_BOT_TOKEN"]
        chats = [c for c in re.split(r"[,;]", conf["TG_CHAT_ID"]) if c.strip()]
    except Exception as e:
        log("读取配置失败: %s" % e)
        return EX_TEMPFAIL

    send_eml = conf.get("SEND_EML", "0") == "1"

    msg = message_from_bytes(raw, policy=policy.default)
    subject = hdr(msg, "subject") or "(无主题)"
    sender = hdr(msg, "from") or env_sender or "(未知)"
    date = hdr(msg, "date")

    try:
        text = extract_body(msg)
    except Exception as e:
        log("正文解析异常: %s" % e)
        text = ""
    text = re.sub(r"\n{3,}", "\n\n", text.strip())

    force_eml = False
    if not text:  # 实在解析不出正文：提示结构，并强制附上原始 .eml 供排查
        force_eml = True
        text = "(未能解析出正文，已附上原始邮件 .eml)\n邮件结构: " + structure(msg)
        log("正文为空 rcpt=%s structure=%s" % (env_rcpt, structure(msg)))

    atts = []
    try:
        for p in msg.iter_attachments():
            atts.append(str(p.get_filename() or p.get_content_type()))
    except Exception:
        pass

    args = (env_rcpt, sender, subject, date, atts, text)
    ok_cnt = 0
    for cid in chats:
        cid = cid.strip()
        try:
            send_message(token, cid, args)
            ok_cnt += 1
            if (send_eml or force_eml) and len(raw) <= MAX_EML:
                try:
                    fname = "mail-%s.eml" % time.strftime("%Y%m%d-%H%M%S")
                    tg_call(token, "sendDocument",
                            {"chat_id": cid, "caption": subject[:200]},
                            files={"document": (fname, raw, "message/rfc822")})
                except Exception as e:
                    log("发送 eml 失败 chat=%s: %s" % (cid, e))
        except Exception as e:
            log("推送失败 chat=%s rcpt=%s: %s" % (cid, env_rcpt, e))

    if ok_cnt:
        log("已推送 rcpt=%s from=%s subject=%s" % (env_rcpt, env_sender, subject[:60]))
        return 0
    return EX_TEMPFAIL


if __name__ == "__main__":
    sys.exit(main())
PYEOF

  chown root:root "$INSTALL_DIR" "$HANDLER"
  chmod 755 "$INSTALL_DIR" "$HANDLER"
  ok "转发程序已部署: $HANDLER"
}

write_config() {
  cat > "$CONF_FILE" <<EOF
# tg-mail 配置 (修改后无需重启，下一封邮件即生效)
TG_BOT_TOKEN=$TG_BOT_TOKEN
# 多个 Chat ID 用英文逗号分隔
TG_CHAT_ID=$TG_CHAT_ID
# 设为 1 则同时把原始 .eml 文件(含附件)发到 Telegram
SEND_EML=0
EOF
  chown root:"$SVC_USER" "$CONF_FILE"
  chmod 640 "$CONF_FILE"
  ok "配置已写入 $CONF_FILE"
}

configure_postfix() {
  info "配置 Postfix..."
  local first; first=$(get_fqdn)
  [[ -f /etc/postfix/main.cf.orig-tgmail ]] || cp /etc/postfix/main.cf /etc/postfix/main.cf.orig-tgmail
  [[ -f /etc/postfix/master.cf.orig-tgmail ]] || cp /etc/postfix/master.cf /etc/postfix/master.cf.orig-tgmail

  # 接受「任意域名」+「任意收件人」(catch-all)，不做域名校验
  echo '/.*/ OK' > "$DOMAINS_FILE"
  echo '/^[^@]+@[^@]+$/ OK' > "$RCPT_FILE"

  postconf -e \
    "myhostname = $first" \
    "mydestination = localhost" \
    "mynetworks = 127.0.0.0/8" \
    "inet_interfaces = all" \
    "inet_protocols = ipv4" \
    "virtual_mailbox_domains = regexp:$DOMAINS_FILE" \
    "virtual_mailbox_maps = regexp:$RCPT_FILE" \
    "virtual_transport = tgpipe" \
    "tgpipe_destination_recipient_limit = 1" \
    "message_size_limit = 26214400" \
    "smtpd_banner = \$myhostname ESMTP" \
    "smtpd_helo_required = yes" \
    "smtpd_relay_restrictions = permit_mynetworks, reject_unauth_destination" \
    "smtpd_recipient_restrictions = reject_non_fqdn_recipient, reject_non_fqdn_sender, reject_unknown_sender_domain, permit_mynetworks, reject_unauth_destination" \
    "smtpd_tls_security_level = may" \
    "smtpd_tls_cert_file = /etc/ssl/certs/ssl-cert-snakeoil.pem" \
    "smtpd_tls_key_file = /etc/ssl/private/ssl-cert-snakeoil.key" \
    "smtp_tls_security_level = may" \
    "disable_vrfy_command = yes" \
    "maximal_queue_lifetime = 3d" \
    "bounce_queue_lifetime = 1d" \
    "biff = no" \
    "append_dot_mydomain = no"

  echo "$first" > /etc/mailname

  if ! grep -q '^tgpipe[[:space:]]' /etc/postfix/master.cf; then
    cat >> /etc/postfix/master.cf <<'EOF'

# tg-mail: 把收到的邮件通过管道交给 Telegram 转发程序
tgpipe    unix  -       n       n       -       10      pipe
  flags=DRq user=tgmail:tgmail argv=/opt/tg-mail/tg_mail_handler.py ${sender} ${recipient}
EOF
  fi

  postfix check
  systemctl enable postfix >/dev/null 2>&1 || true
  systemctl restart postfix
  ok "Postfix 配置完成并已重启"
}

open_firewall() {
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    ufw allow 25/tcp >/dev/null && ok "ufw 已放行 25/tcp"
  fi
}

verify_listen() {
  sleep 1
  if ss -ltn | awk '$4 ~ /:25$/ {f=1} END{exit !f}'; then
    if ss -ltnp | awk '$4 ~ /:25$/' | grep -q master; then
      ok "Postfix 正在监听 25 端口"
    else
      warn "25 端口被其他程序占用:"; ss -ltnp | awk '$4 ~ /:25$/'
    fi
  else
    warn "没有检测到 25 端口监听，请执行: systemctl status postfix"
  fi
}

send_selftest() {
  local d=selftest.tg-mail.invalid   # 任意域名都会被接收，无需真实存在
  python3 - "$d" <<'PY'
import smtplib, sys
from email.message import EmailMessage
d = sys.argv[1]
m = EmailMessage()
m["From"] = "selftest@localhost"
m["To"] = "selftest@" + d
m["Subject"] = "收信系统安装自检 / Self-test"
m.set_content("如果你在 Telegram 收到这条消息，说明「收信 → Telegram 推送」链路已打通 ✅")
with smtplib.SMTP("127.0.0.1", 25, timeout=20) as s:
    s.sendmail("", ["selftest@" + d], m.as_bytes())
print("自检邮件已投递给本机 Postfix")
PY
}

summary() {
  local ip
  ip=$(curl -4fsS --max-time 5 https://checkip.amazonaws.com 2>/dev/null | tr -d '[:space:]' || true)
  [[ -n "$ip" ]] || ip="<你的服务器公网IPv4>"
  echo
  echo "${G}==================== 安装完成 ====================${N}"
  echo "收信范围: 任意域名 (不做域名校验)"
  echo
  echo "${Y}【1】任意域名只要把 A 记录指向本机即可收信 (bind9 改完记得加 serial 并 rndc reload):${N}"
  echo "    mail.ccc.com.   IN  A   ${ip}      # 收 xxx@mail.ccc.com"
  echo "    (若想收 xxx@ccc.com 这种根域名邮件，再加: ccc.com.  IN MX 10 mail.ccc.com.)"
  echo
  echo "${Y}【2】AWS 安全组 (Security Group) 必须放行入站 TCP 25${N}  (来源 0.0.0.0/0)"
  echo
  echo "${Y}【3】Telegram 应该已收到一条自检消息${N}，若没有，查看日志:"
  echo "    journalctl -t tg-mail -n 30 --no-pager      # 转发程序日志"
  echo "    journalctl -u postfix@- -n 50 --no-pager     # Postfix 日志"
  echo "    postqueue -p                                 # 查看待重试队列"
  echo
  echo "常用命令:"
  echo "    bash $0 test                      # 再发一封自检邮件"
  echo "    nano $CONF_FILE      # 改 Token / Chat ID / SEND_EML=1(附带原始eml)"
  echo "    bash $0 uninstall                 # 卸载"
  echo "${G}===================================================${N}"
}

# ----------------------------------------------------------------------------
do_install() {
  need_root
  check_os
  prep_packages
  collect_input
  install_postfix
  install_handler
  write_config
  configure_postfix
  open_firewall
  verify_listen
  info "发送自检邮件..."
  send_selftest || warn "自检投递失败，请查看 postfix 日志"
  summary
}

do_test() {
  need_root
  [[ -f $DOMAINS_FILE ]] || die "尚未安装"
  send_selftest
  ok "已发送，请查看 Telegram"
}

do_uninstall() {
  need_root
  local ans=""
  read -r -p "将卸载 Postfix 与转发程序并删除配置，确认请输入 yes: " ans </dev/tty || true
  [[ "$ans" == "yes" ]] || die "已取消"
  systemctl stop postfix 2>/dev/null || true
  DEBIAN_FRONTEND=noninteractive apt-get purge -y postfix >/dev/null || true
  apt-get autoremove -y >/dev/null || true
  rm -rf "$INSTALL_DIR" "$CONF_DIR" /etc/postfix
  id "$SVC_USER" &>/dev/null && userdel "$SVC_USER" || true
  ok "已卸载"
}

case "${1:-install}" in
  install)    do_install ;;
  update-handler) need_root; install_handler; ok "转发程序已更新，下一封邮件即生效" ;;
  test)       do_test ;;
  uninstall)  do_uninstall ;;
  *) echo "用法: $0 [install|update-handler|test|uninstall]"; exit 1 ;;
esac
