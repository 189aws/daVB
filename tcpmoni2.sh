#!/bin/bash

# ============================================
# AWS EC2 超温和版 - 专为 c5.large 优化
# 2 vCPUs, 4GB RAM
# 策略：极慢建立，绝不卡死SSH
# ============================================

set -e

echo "========================================"
echo "  🐌 超温和模式 (c5.large 专用)"
echo "========================================"

# 1. 检查依赖
if ! command -v python3 &> /dev/null; then
    apt-get update -qq 2>/dev/null
    apt-get install -y python3 screen 2>/dev/null
fi

# 2. 极度温和的系统优化
echo "[1/3] 温和优化系统..."
sysctl -w net.ipv4.ip_local_port_range="10000 65535" >/dev/null 2>&1
sysctl -w net.ipv4.tcp_tw_reuse=1 >/dev/null 2>&1
sysctl -w net.ipv4.tcp_fin_timeout=60 >/dev/null 2>&1
sysctl -w net.ipv4.tcp_keepalive_time=1200 >/dev/null 2>&1
ulimit -n 65535 2>/dev/null || ulimit -n 32768

# 3. 创建超轻量Python引擎
echo "[2/3] 生成轻量引擎..."
cat << 'PYTHON_EOF' > /tmp/ultra_gentle.py
#!/usr/bin/env python3
import asyncio
import random
import ssl
import sys
import time
from datetime import datetime

# 200个精选目标（减少选择开销）
TARGETS = [
    "google.com", "youtube.com", "facebook.com", "amazon.com", "wikipedia.org",
    "twitter.com", "instagram.com", "linkedin.com", "reddit.com", "netflix.com",
    "yahoo.com", "bing.com", "twitch.tv", "ebay.com", "apple.com",
    "microsoft.com", "github.com", "stackoverflow.com", "pinterest.com", "tumblr.com",
    "booking.com", "aliexpress.com", "walmart.com", "imdb.com", "bbc.com",
    "cnn.com", "nytimes.com", "dropbox.com", "spotify.com", "soundcloud.com",
    "vimeo.com", "dailymotion.com", "etsy.com", "zillow.com", "indeed.com",
    "tripadvisor.com", "expedia.com", "airbnb.com", "quora.com", "medium.com",
    "wordpress.com", "blogger.com", "wix.com", "squarespace.com", "shopify.com",
    "paypal.com", "stripe.com", "adobe.com", "canva.com", "figma.com",
    "slack.com", "zoom.us", "trello.com", "asana.com", "notion.so",
    "salesforce.com", "oracle.com", "ibm.com", "intel.com", "nvidia.com",
    "amd.com", "dell.com", "hp.com", "lenovo.com", "samsung.com",
    "sony.com", "lg.com", "panasonic.com", "toshiba.com", "philips.com",
    "nike.com", "adidas.com", "puma.com", "underarmour.com", "reebok.com",
    "zara.com", "hm.com", "uniqlo.com", "gap.com", "oldnavy.com",
    "ikea.com", "homedepot.com", "lowes.com", "target.com", "bestbuy.com",
    "costco.com", "samsclub.com", "kroger.com", "safeway.com", "wholefoods.com",
    "tesla.com", "ford.com", "gm.com", "toyota.com", "honda.com",
    "bmw.com", "mercedes-benz.com", "audi.com", "volkswagen.com", "nissan.com",
    "espn.com", "nba.com", "nfl.com", "mlb.com", "nhl.com",
    "fifa.com", "uefa.com", "olympics.com", "skysports.com", "bleacherreport.com",
    "coursera.org", "edx.org", "udemy.com", "khanacademy.org", "duolingo.com",
    "codecademy.com", "skillshare.com", "masterclass.com", "lynda.com", "pluralsight.com",
    "webmd.com", "healthline.com", "mayoclinic.org", "cdc.gov", "nih.gov",
    "who.int", "nature.com", "science.org", "sciencedirect.com", "arxiv.org",
    "jstor.org", "researchgate.net", "academia.edu", "pubmed.gov", "springer.com",
    "forbes.com", "bloomberg.com", "reuters.com", "wsj.com", "economist.com",
    "cnbc.com", "marketwatch.com", "investing.com", "seekingalpha.com", "morningstar.com",
    "chase.com", "bankofamerica.com", "wellsfargo.com", "citibank.com", "usbank.com",
    "capitalone.com", "americanexpress.com", "discover.com", "ally.com", "schwab.com",
    "fidelity.com", "vanguard.com", "etrade.com", "tdameritrade.com", "robinhood.com",
    "coinbase.com", "binance.com", "kraken.com", "gemini.com", "blockchain.com",
    "steam.com", "epicgames.com", "origin.com", "ubisoft.com", "ea.com",
    "blizzard.com", "riotgames.com", "minecraft.net", "roblox.com", "fortnite.com",
    "discord.com", "telegram.org", "whatsapp.com", "signal.org", "viber.com",
    "skype.com", "messenger.com", "wechat.com", "line.me", "snapchat.com",
    "tiktok.com", "douyin.com", "kuaishou.com", "bilibili.com", "youku.com",
    "iqiyi.com", "tencent.com", "baidu.com", "qq.com", "weibo.com",
    "taobao.com", "tmall.com", "jd.com", "pinduoduo.com", "meituan.com",
]

print(f"已加载 {len(TARGETS)} 个目标")

class Stats:
    def __init__(self):
        self.active = 0
        self.total = 0
        self.failed = 0
        self.start = time.time()

stats = Stats()
running = True

async def gentle_connect(worker_id, conn_id, start_delay):
    """超温和连接"""
    global running
    
    # 延迟启动
    await asyncio.sleep(start_delay)
    
    while running:
        reader, writer = None, None
        try:
            target = random.choice(TARGETS)
            
            ctx = ssl.create_default_context()
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE
            
            # 超长超时
            reader, writer = await asyncio.wait_for(
                asyncio.open_connection(target, 443, ssl=ctx),
                timeout=30
            )
            
            stats.active += 1
            stats.total += 1
            
            req = f"GET / HTTP/1.1\r\nHost: {target}\r\nConnection: keep-alive\r\n\r\n"
            writer.write(req.encode())
            await writer.drain()
            
            # 读取少量数据
            try:
                await asyncio.wait_for(reader.read(1024), timeout=8)
            except:
                pass
            
            # 超长心跳 - 5分钟一次
            while running:
                await asyncio.sleep(300)
                try:
                    writer.write(f"GET / HTTP/1.1\r\nHost: {target}\r\n\r\n".encode())
                    await writer.drain()
                    await asyncio.wait_for(reader.read(512), timeout=8)
                except:
                    break
                    
        except Exception:
            stats.failed += 1
            # 超长重连延迟
            await asyncio.sleep(random.uniform(15, 30))
        finally:
            if writer:
                stats.active -= 1
                try:
                    writer.close()
                    await writer.wait_closed()
                except:
                    pass

async def gentle_report():
    """每2分钟报告一次"""
    while running:
        await asyncio.sleep(120)
        mins = int((time.time() - stats.start) / 60)
        print(f"[{datetime.now().strftime('%H:%M:%S')}] "
              f"连接:{stats.active:4d} | 总:{stats.total:5d} | "
              f"失败:{stats.failed:4d} | {mins}分钟")

async def main():
    worker_id = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    phase = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    
    # 根据阶段配置
    if phase == 0:
        # 阶段1: 立即开始
        conns = 150
        base_delay = 0
        interval = 3.0
        print(f"Worker {worker_id} [阶段1] 150连接, 立即开始")
    elif phase == 1:
        # 阶段2: 12分钟后
        conns = 100
        base_delay = 720
        interval = 4.0
        print(f"Worker {worker_id} [阶段2] 100连接, 12分钟后启动")
    else:
        # 阶段3: 25分钟后
        conns = 100
        base_delay = 1500
        interval = 5.0
        print(f"Worker {worker_id} [阶段3] 100连接, 25分钟后启动")
    
    reporter = asyncio.create_task(gentle_report())
    
    # 创建任务
    tasks = []
    for i in range(conns):
        delay = base_delay + interval * i
        task = asyncio.create_task(gentle_connect(worker_id, i, delay))
        tasks.append(task)
        await asyncio.sleep(0.01)
    
    print(f"Worker {worker_id}: {conns}个任务已创建\n")
    
    try:
        await asyncio.gather(*tasks, reporter)
    except KeyboardInterrupt:
        global running
        running = False

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
PYTHON_EOF

chmod +x /tmp/ultra_gentle.py

# 4. 超缓慢分阶段启动
echo "[3/3] 分阶段启动（超慢）..."

pkill -9 -f ultra_gentle.py 2>/dev/null || true
pkill -9 -f "screen.*ultra" 2>/dev/null || true
sleep 3

echo ""
echo "========== 阶段1: 立即启动 (目标2000) =========="
# 只启动4个worker，每个150连接 = 600连接
for i in {0..3}; do
    echo "  启动 Worker $i..."
    screen -dmS "ultra_0_$i" python3 /tmp/ultra_gentle.py $i 0
    sleep 5  # 每个进程间隔5秒
done
echo "✅ 阶段1: 4进程×150连接 = 600连接（将在7.5分钟内建立）"
sleep 10

echo ""
echo "========== 阶段2: 12分钟后自动启动 (+800) =========="
# 4个worker，每个100连接 = 400连接
for i in {0..3}; do
    echo "  准备 Worker $i..."
    screen -dmS "ultra_1_$i" python3 /tmp/ultra_gentle.py $i 1
    sleep 5
done
echo "✅ 阶段2: 4进程×100连接 = 400连接（12分钟后自动开始）"
sleep 10

echo ""
echo "========== 阶段3: 25分钟后自动启动 (+800) =========="
# 4个worker，每个100连接 = 400连接
for i in {0..3}; do
    echo "  准备 Worker $i..."
    screen -dmS "ultra_2_$i" python3 /tmp/ultra_gentle.py $i 2
    sleep 5
done
echo "✅ 阶段3: 4进程×100连接 = 400连接（25分钟后自动开始）"

echo ""
echo "========================================"
echo "  ✅ 超温和模式已启动！"
echo "========================================"
echo ""
echo "📊 c5.large 专用配置:"
echo "  • CPU: 2 vCPUs (轻负载)"
echo "  • 内存: ~800MB 使用"
echo "  • 总进程: 12个（分3批）"
echo "  • 目标网站: 200个"
echo ""
echo "⏱️  增长时间表:"
echo "  ┌──────────────────────────────┐"
echo "  │  时间     │  连接数         │"
echo "  ├──────────────────────────────┤"
echo "  │  5分钟    │   ~300          │"
echo "  │  10分钟   │   ~600 (阶段1✓) │"
echo "  │  15分钟   │   ~800          │"
echo "  │  20分钟   │  ~1000 (阶段2✓) │"
echo "  │  30分钟   │  ~1200          │"
echo "  │  40分钟   │  ~1400 (阶段3✓) │"
echo "  │  50分钟   │  ~1600          │"
echo "  └──────────────────────────────┘"
echo ""
echo "🔑 为什么这么保守？"
echo "  • c5.large 只有2个CPU"
echo "  • 避免CPU 100%导致SSH断线"
echo "  • 每个连接间隔3-5秒建立"
echo "  • 心跳间隔5分钟（极低开销）"
echo "  • 失败重连等15-30秒"
echo ""
echo "💡 如果还是断线："
echo "  1. 再减少进程数（改为每批2个）"
echo "  2. 增加建立间隔（改为5-8秒）"
echo "  3. 升级到 c5.xlarge"
echo ""
echo "📈 监控（不要太频繁查看）:"
echo "  watch -n 30 'ss -ant | grep ESTAB | wc -l'"
echo ""
echo "📝 查看日志:"
echo "  screen -r ultra_0_0"
echo ""
echo "🛑 停止:"
echo "  pkill -f ultra_gentle.py"
echo ""
echo "⚠️  SSH保护提示:"
echo "  • 建议使用 tmux 或 screen 运行监控"
echo "  • 不要频繁执行命令"
echo "  • 等待至少5分钟再查看第一次结果"
echo ""