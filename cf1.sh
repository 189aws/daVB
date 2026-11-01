#!/bin/sh
cd /home
sudo mkdir -p /etc/systemd/resolved.conf.d
echo -e "[Resolve]\nDNS=1.1.1.2 1.1.1.3\nLLMNR=no\nDNSOverTLS=yes" | sudo tee /etc/systemd/resolved.conf.d/doh.conf
sudo systemctl restart systemd-resolved
sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
sudo resolvectl dns ens5 1.1.1.2 1.1.1.3
sudo resolvectl dns enX0 1.1.1.2 1.1.1.3
sudo resolvectl dns eth0 1.1.1.2 1.1.1.3
sudo systemctl restart systemd-resolved
resolvectl status
