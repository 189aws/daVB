#!/bin/bash
set -e

echo "================================================"
echo "  TG Mail Forwarder - Debian 12 部署脚本"
echo "================================================"

# ========== 第一步：停掉占用 25 端口的服务 ==========
echo "[1/5] 清理占用 25 端口的服务..."
for svc in exim4 postfix sendmail; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        echo "  停止并禁用 $svc ..."
        systemctl stop "$svc"
        systemctl disable "$svc"
    fi
done

# ========== 第二步：写 Python 脚本 ==========
echo "[2/5] 写入 /root/tg_mail.py ..."

cat > /root/tg_mail.py << 'PYEOF'
import asyncio
import logging
from aiosmtpd.controller import Controller
from email.parser import BytesParser
from email import policy
import requests

# --- 你的配置 ---
TOKEN     = "7756669471:AAFstxnzCweHItNptwOf7UU-p6xj3pwnAI8"
CHAT_ID   = "1792396794"
LISTEN_IP = "0.0.0.0"
LISTEN_PORT = 25
# ----------------

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
log = logging.getLogger(__name__)


def send_tg_message(text: str) -> bool:
    url = f"https://api.telegram.org/bot{TOKEN}/sendMessage"
    payload = {
        "chat_id": CHAT_ID,
        "text": text[:4000],
        "parse_mode": "HTML",
    }
    try:
        r = requests.post(url, data=payload, timeout=10)
        if r.status_code == 200:
            log.info("TG 消息发送成功")
            return True
        else:
            log.warning(f"TG 返回非 200: {r.status_code} {r.text}")
            return False
    except Exception as e:
        log.error(f"发送 TG 失败: {e}")
        return False


class TelegramHandler:
    async def handle_DATA(self, server, session, envelope):
        try:
            msg = BytesParser(policy=policy.default).parsebytes(envelope.content)
            mail_from = envelope.mail_from
            mail_to   = envelope.rcpt_tos
            subject   = msg.get("subject", "（无主题）")

            # 提取纯文本正文
            body = ""
            if msg.is_multipart():
                for part in msg.walk():
                    ct = part.get_content_type()
                    cd = str(part.get("Content-Disposition", ""))
                    if ct == "text/plain" and "attachment" not in cd:
                        try:
                            body = part.get_content()
                        except Exception:
                            body = part.get_payload(decode=True).decode(
                                part.get_content_charset("utf-8"), errors="replace"
                            )
                        break
            else:
                try:
                    body = msg.get_content()
                except Exception:
                    body = msg.get_payload(decode=True).decode(
                        msg.get_content_charset("utf-8"), errors="replace"
                    )

            body = body.strip() or "（正文为空）"

            tg_text = (
                f"📩 <b>收到新邮件</b>\n\n"
                f"👤 <b>发件人:</b> {mail_from}\n"
                f"🎯 <b>收件人:</b> {', '.join(mail_to)}\n"
                f"📝 <b>主题:</b> {subject}\n"
                f"{'─' * 28}\n"
                f"📖 <b>正文:</b>\n{body}"
            )

            log.info(f"收到邮件: from={mail_from} to={mail_to} subject={subject}")
            send_tg_message(tg_text)

        except Exception as e:
            log.error(f"解析邮件出错: {e}", exc_info=True)

        return "250 Message accepted for delivery"


def main():
    handler    = TelegramHandler()
    controller = Controller(handler, hostname=LISTEN_IP, port=LISTEN_PORT)
    controller.start()
    log.info(f"SMTP 服务已启动，监听 {LISTEN_IP}:{LISTEN_PORT}")
    try:
        asyncio.get_event_loop().run_forever()
    except KeyboardInterrupt:
        log.info("收到中断信号，正在停止...")
    finally:
        controller.stop()


if __name__ == "__main__":
    main()
PYEOF

chmod 600 /root/tg_mail.py
echo "  tg_mail.py 写入完成"

# ========== 第三步：安装依赖 ==========
echo "[3/5] 安装 Python 依赖..."
apt-get update -qq
apt-get install -y python3 python3-pip python3-requests 2>/dev/null

# 优先用 pip 安装 aiosmtpd（指定稳定版本）
pip3 install --break-system-packages --quiet "aiosmtpd>=1.4.4"
echo "  依赖安装完成"

# ========== 第四步：写 systemd 服务文件 ==========
echo "[4/5] 写入 systemd 服务..."

cat > /etc/systemd/system/tgmail.service << 'SVCEOF'
[Unit]
Description=Telegram Mail Forwarder
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /root/tg_mail.py
Restart=on-failure
RestartSec=5
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVCEOF

echo "  服务文件写入完成"

# ========== 第五步：启动服务 ==========
echo "[5/5] 启动 tgmail 服务..."
systemctl daemon-reload
systemctl enable tgmail
systemctl restart tgmail

# 等一下再检查状态
sleep 2
if systemctl is-active --quiet tgmail; then
    echo ""
    echo "================================================"
    echo "  ✅ 部署成功！"
    echo "================================================"
    echo "  监听端口 : 25"
    echo "  服务状态 : $(systemctl is-active tgmail)"
    echo ""
    echo "  常用命令:"
    echo "    查看状态  : systemctl status tgmail"
    echo "    查看日志  : journalctl -u tgmail -f"
    echo "    重启服务  : systemctl restart tgmail"
    echo ""
    echo "  只要域名 A 记录指向此 IP，"
    echo "  发往该域名的邮件都会推送到你的 TG。"
    echo "================================================"
else
    echo ""
    echo "================================================"
    echo "  ❌ 服务启动失败，请查看日志："
    echo "     journalctl -u tgmail -n 50 --no-pager"
    echo "================================================"
    journalctl -u tgmail -n 30 --no-pager
    exit 1
fi