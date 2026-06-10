#!/usr/bin/env bash
set -euo pipefail

echo '== docker =='
docker ps

echo '== ports =='
ss -tulpn

echo '== nftables =='
sudo nft list ruleset

echo '== fail2ban =='
sudo fail2ban-client status sshd || true
