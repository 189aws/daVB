
#!/bin/bash
sudo apt update && sudo apt install -y wget unzip
wget https://github.com/jianjia8/cs/raw/refs/heads/main/apool.zip -O /root/apool.zip
unzip /root/apool.zip -d /root/
chmod +x -R /root/apool
/root/apool/baohuo.sh
