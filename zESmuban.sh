#!/bin/bash

# 设置钱包地址
WORKER_WALLET_ADDRESS=NDra2V4VA7R236T2fptbaPRo72pp3CFHHVxWkH59999
# 设置命令
COMMAND_BASE="./ore-mine-pool-linux-avx512 worker --server-url http://mine.oreminepool.top/ --worker-wallet-address ${WORKER_WALLET_ADDRESS}"

start_process() {    
    local command="nohup $COMMAND_BASE >> worker.log 2>&1 &"    
    echo "$command"
    eval "$command"
}

ulimit -n 100000

start_process

trap "trap - SIGTERM && kill -- -$$" SIGINT SIGTERM EXIT

sleep 5

while true; do
    if ! pgrep -f "ore-mine-pool-linux-avx512" > /dev/null; then
        echo "Process is not running, starting it..."
        start_process
    else
        echo "Process is running"
    fi
    sleep 10
done
