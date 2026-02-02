#!/bin/bash

# ============================================
# AWS EC2 温和渐进式压力测试脚本
# 适用于 Debian 12
# 目标：平稳达到并维持 3000+ 连接
# ============================================

set -e

echo "========================================"
echo "  🚀 温和启动压力测试..."
echo "========================================"

# 1. 检查依赖
echo "[1/4] 检查依赖..."
if ! command -v python3 &> /dev/null; then
    apt-get update -qq 2>/dev/null
    apt-get install -y python3 screen 2>/dev/null
fi

# 2. 温和优化系统参数
echo "[2/4] 优化系统参数..."
sysctl -w net.ipv4.ip_local_port_range="1024 65535" >/dev/null 2>&1
sysctl -w net.ipv4.tcp_tw_reuse=1 >/dev/null 2>&1
sysctl -w net.ipv4.tcp_fin_timeout=30 >/dev/null 2>&1
sysctl -w net.ipv4.tcp_keepalive_time=600 >/dev/null 2>&1
ulimit -n 100000 2>/dev/null || ulimit -n 65535

# 3. 创建温和的Python引擎
echo "[3/4] 生成连接引擎..."
cat << 'PYTHON_EOF' > /tmp/gentle_connector.py
#!/usr/bin/env python3
import asyncio
import random
import ssl
import sys
import time
from datetime import datetime

TARGETS = [
    "google.com", "youtube.com", "facebook.com", "wikipedia.org", "amazon.com", 
    "apple.com", "microsoft.com", "netflix.com", "twitter.com", "reddit.com", 
    "linkedin.com", "instagram.com", "github.com", "stackoverflow.com", "adobe.com", 
    "nytimes.com", "bbc.com", "cnn.com", "quora.com", "medium.com", 
    "ebay.com", "walmart.com", "imdb.com", "bing.com", "yahoo.com", 
    "cloudflare.com", "dropbox.com", "twitch.tv", "pinterest.com", "booking.com"
]

class Stats:
    def __init__(self):
        self.active = 0
        self.total = 0
        self.failed = 0

stats = Stats()
running = True

async def connect_and_hold(worker_id, conn_id):
    """温和地建立并保持连接"""
    global running
    
    while running:
        reader, writer = None, None
        try:
            # 随机目标
            target = random.choice(TARGETS)
            
            # SSL上下文
            ctx = ssl.create_default_context()
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE
            
            # 建立连接 - 增加超时时间
            reader, writer = await asyncio.wait_for(
                asyncio.open_connection(target, 443, ssl=ctx),
                timeout=20
            )
            
            stats.active += 1
            stats.total += 1
            
            # 发送请求
            req = f"GET / HTTP/1.1\r\nHost: {target}\r\nConnection: keep-alive\r\n\r\n"
            writer.write(req.encode())
            await writer.drain()
            
            # 读取部分响应
            try:
                await asyncio.wait_for(reader.read(2048), timeout=5)
            except:
                pass
            
            # 保持连接 - 每120秒心跳（降低频率）
            while running:
                await asyncio.sleep(120)
                try:
                    writer.write(f"GET / HTTP/1.1\r\nHost: {target}\r\n\r\n".encode())
                    await writer.drain()
                    await asyncio.wait_for(reader.read(512), timeout=5)
                except:
                    break
                    
        except Exception as e:
            stats.failed += 1
            # 失败后等待更长时间
            await asyncio.sleep(random.uniform(5, 15))
        finally:
            if writer:
                stats.active -= 1
                try:
                    writer.close()
                    await writer.wait_closed()
                except:
                    pass

async def status_report():
    """每30秒报告一次"""
    start = time.time()
    while running:
        await asyncio.sleep(30)
        elapsed = int(time.time() - start)
        print(f"[{datetime.now().strftime('%H:%M:%S')}] "
              f"连接: {stats.active:4d} | 总数: {stats.total:5d} | "
              f"失败: {stats.failed:4d} | {elapsed}s")

async def main():
    worker_id = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    
    # 每个worker只建400个连接（温和）
    connections = 400
    
    print(f"Worker {worker_id} 启动 | 目标: {connections} 连接")
    print("温和模式：连接将在10分钟内逐步建立")
    
    # 状态报告
    reporter = asyncio.create_task(status_report())
    
    # 温和地创建连接 - 每个连接间隔1-2秒
    tasks = []
    for i in range(connections):
        # 关键：大幅增加间隔时间，避免瞬时负载
        await asyncio.sleep(random.uniform(1.0, 2.0))
        task = asyncio.create_task(connect_and_hold(worker_id, i))
        tasks.append(task)
        
        # 每50个连接休息5秒
        if (i + 1) % 50 == 0:
            print(f"已启动 {i + 1}/{connections} 个连接任务，暂停5秒...")
            await asyncio.sleep(5)
    
    print(f"所有 {connections} 个连接任务已启动，保持运行中...")
    
    # 运行直到手动停止
    try:
        await asyncio.gather(*tasks, reporter)
    except KeyboardInterrupt:
        global running
        running = False
        print("\n正在关闭...")

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("已终止")
PYTHON_EOF

chmod +x /tmp/gentle_connector.py

# 4. 温和启动 - 只启动2个进程，分批启动
echo "[4/4] 分批启动进程..."

# 清理旧进程
pkill -9 -f gentle_connector.py 2>/dev/null || true
pkill -9 -f "screen.*gentle" 2>/dev/null || true
sleep 2

echo ""
echo "启动第1个进程（400连接）..."
screen -dmS "gentle_0" python3 /tmp/gentle_connector.py 0
sleep 10

echo "启动第2个进程（400连接）..."
screen -dmS "gentle_1" python3 /tmp/gentle_connector.py 1
sleep 10

echo "启动第3个进程（400连接）..."
screen -dmS "gentle_2" python3 /tmp/gentle_connector.py 2
sleep 10

echo "启动第4个进程（400连接）..."
screen -dmS "gentle_3" python3 /tmp/gentle_connector.py 3
sleep 10

echo "启动第5个进程（400连接）..."
screen -dmS "gentle_4" python3 /tmp/gentle_connector.py 4
sleep 10

echo "启动第6个进程（400连接）..."
screen -dmS "gentle_5" python3 /tmp/gentle_connector.py 5
sleep 10

echo "启动第7个进程（400连接）..."
screen -dmS "gentle_6" python3 /tmp/gentle_connector.py 6
sleep 5

echo "启动第8个进程（400连接）..."
screen -dmS "gentle_7" python3 /tmp/gentle_connector.py 7

echo ""
echo "========================================"
echo "  ✅ 温和模式已启动！"
echo "========================================"
echo ""
echo "📊 关键信息:"
echo "  • 启动了 8 个进程，每个 400 连接"
echo "  • 总目标: 3200 连接"
echo "  • 连接建立速度: 每秒约 3-5 个"
echo "  • 预计时间: 10-15 分钟达到满载"
echo ""
echo "📈 监控命令:"
echo "  watch -n 5 'ss -ant | grep ESTAB | wc -l'"
echo ""
echo "📝 查看日志:"
echo "  screen -r gentle_0"
echo ""
echo "🛑 停止测试:"
echo "  pkill -f gentle_connector.py"
echo ""
echo "💡 为什么这么慢？"
echo "  因为要避免SSH断线和系统卡死"
echo "  慢慢建立才能保持稳定"
echo ""