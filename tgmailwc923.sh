#!/bin/bash
set -e

# ========== 配置区 ==========
TG_TOKEN="8896559295:AAHWVHQVJfoWG9v4McFg2qJgACw0nEpMxJo"
TG_CHAT_ID="1417748881"
LISTEN_PORT=25                            # SMTP 监听端口
SERVICE_DIR="/opt/tg_mail_forwarder"
# ============================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# ── 1. 环境准备与依赖安装 ─────────────────────────────────────────
log "检查并安装基础组件..."
apt-get update -qq && apt-get install -y -qq python3 python3-pip psmisc curl >/dev/null 2>&1

# ── 2. 清理占用端口 25 的服务 ──────────────────────────────────────
log "清理 25 端口占用服务..."
systemctl stop postfix exim4 sendmail 2>/dev/null || true
systemctl disable postfix exim4 sendmail 2>/dev/null || true
fuser -k ${LISTEN_PORT}/tcp 2>/dev/null || true
sleep 1

# ── 3. 创建部署目录并写入修复后的 Python 代码 ───────────────────────
log "更新 Python 邮件接收与 Telegram 转发服务代码..."
mkdir -p ${SERVICE_DIR}

cat <<'EOF' > ${SERVICE_DIR}/mail_server.py
import asyncio
import email
from email.header import decode_header
import re
import urllib.parse
import urllib.request
import sys
import html

TG_TOKEN = "TG_TOKEN_PLACEHOLDER"
TG_CHAT_ID = "TG_CHAT_ID_PLACEHOLDER"

def decode_str(s):
    """解码邮件头中的编码文本 (如 Subject, From)"""
    if not s:
        return ""
    decoded_list = decode_header(s)
    result = []
    for content, charset in decoded_list:
        if isinstance(content, bytes):
            charset = charset or 'utf-8'
            try:
                result.append(content.decode(charset, errors='replace'))
            except Exception:
                result.append(content.decode('utf-8', errors='replace'))
        else:
            result.append(str(content))
    return "".join(result)

def extract_body(msg):
    """全兼容提取邮件正文"""
    plain_text = ""
    html_text = ""

    if msg.is_multipart():
        for part in msg.walk():
            content_type = part.get_content_type()
            content_disposition = str(part.get("Content-Disposition"))

            if "attachment" in content_disposition:
                continue

            charset = part.get_content_charset() or 'utf-8'

            if content_type == "text/plain" and not plain_text:
                try:
                    payload = part.get_payload(decode=True)
                    if payload:
                        plain_text = payload.decode(charset, errors='replace')
                except Exception:
                    pass

            elif content_type == "text/html" and not html_text:
                try:
                    payload = part.get_payload(decode=True)
                    if payload:
                        html_text = payload.decode(charset, errors='replace')
                except Exception:
                    pass
    else:
        content_type = msg.get_content_type()
        charset = msg.get_content_charset() or 'utf-8'
        try:
            payload = msg.get_payload(decode=True)
            if payload:
                text = payload.decode(charset, errors='replace')
                if content_type == "text/html":
                    html_text = text
                else:
                    plain_text = text
        except Exception:
            plain_text = str(msg.get_payload())

    if plain_text.strip():
        final_body = plain_text.strip()
    elif html_text.strip():
        cleaned = re.sub(r'<(script|style)[^>]*>.*?</\1>', '', html_text, flags=re.DOTALL | re.IGNORECASE)
        cleaned = re.sub(r'<[^>]+>', ' ', cleaned)
        cleaned = re.sub(r'\s+', ' ', cleaned)
        final_body = cleaned.strip()
    else:
        final_body = "[该邮件无文本内容或仅包含图像/附件]"

    return final_body

def send_tg_message(sender, recipient, subject, body):
    """格式化并推送给 Telegram Bot (修复 400 Bad Request)"""
    # 先在纯文本下匹配验证码 (4-8 位纯数字或字母混合)
    code_match = re.search(r'\b([A-Z0-9]{4,8})\b', body)
    code_str = f"\n🔑 <b>提取验证码：</b> <code>{code_match.group(1)}</code>\n" if code_match else ""

    # 截取前 1500 个字符
    if len(body) > 1500:
        body = body[:1500] + "... (后略)"

    # 【关键修复】使用 html.escape 防止文本里的 < > & 破坏 TG HTML 格式
    safe_sender = html.escape(sender)
    safe_recipient = html.escape(recipient)
    safe_subject = html.escape(subject)
    safe_body = html.escape(body)

    msg_text = (
        f"📧 <b>收到新邮件！</b>\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"👤 <b>发件人：</b> <code>{safe_sender}</code>\n"
        f"📥 <b>收件人：</b> <code>{safe_recipient}</code>\n"
        f"📌 <b>主 题：</b> <b>{safe_subject}</b>\n"
        f"{code_str}"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"📝 <b>正文内容：</b>\n"
        f"<pre>{safe_body}</pre>"
    )

    url = f"https://api.telegram.org/bot{TG_TOKEN}/sendMessage"
    payload = {
        "chat_id": TG_CHAT_ID,
        "text": msg_text,
        "parse_mode": "HTML"
    }

    try:
        data = urllib.parse.urlencode(payload).encode('utf-8')
        req = urllib.request.Request(url, data=data)
        urllib.request.urlopen(req, timeout=10)
    except Exception as e:
        print(f"[错误] 推送 Telegram 失败: {e}", file=sys.stderr)

class SMTPHandler:
    async def handle_DATA(self, server, session, envelope):
        mail_from = envelope.mail_from
        rcpt_tos = ", ".join(envelope.rcpt_tos)
        data = envelope.content

        msg = email.message_from_bytes(data)

        sender = decode_str(msg.get("From", mail_from))
        recipient = decode_str(msg.get("To", rcpt_tos))
        subject = decode_str(msg.get("Subject", "(无主题)"))
        body = extract_body(msg)

        print(f"[+] 收到邮件: 来自 {sender} -> 给 {recipient} | 主题: {subject}")
        send_tg_message(sender, recipient, subject, body)

        return '250 Message accepted for delivery'

async def main():
    from aiosmtpd.controller import Controller
    handler = SMTPHandler()
    controller = Controller(handler, hostname='0.0.0.0', port=25)
    controller.start()
    print("[✓] SMTP 邮件转发服务已在 0.0.0.0:25 启动成功...")
    while True:
        await asyncio.sleep(3600)

if __name__ == '__main__':
    try:
        import aiosmtpd
    except ImportError:
        import subprocess
        subprocess.check_call([sys.executable, "-m", "pip", "install", "aiosmtpd"])
        
    asyncio.run(main())
EOF

# 替换配置参数
sed -i "s/TG_TOKEN_PLACEHOLDER/${TG_TOKEN}/g" ${SERVICE_DIR}/mail_server.py
sed -i "s/TG_CHAT_ID_PLACEHOLDER/${TG_CHAT_ID}/g" ${SERVICE_DIR}/mail_server.py

# ── 4. 安装依赖并重启服务 ──────────────────────────────────────────
log "安装 Python aiosmtpd 依赖..."
pip3 install aiosmtpd >/dev/null 2>&1 || python3 -m pip install aiosmtpd --break-system-packages >/dev/null 2>&1

log "重启 Systemd 服务..."
systemctl daemon-reload
systemctl restart tg-mail

sleep 2

if systemctl is-active --quiet tg-mail; then
    log "服务修复并重启完成！"
else
    err "服务启动失败，请检查日志。"
fi
