# VPS Runbook

## Цель

Восстановить VPS с сервисами:

- SSH key-only
- nftables
- Fail2ban
- Docker
- AmneziaWG
- Pi-hole
- MTProxy FakeTLS

## Порты

Снаружи открыты только:

```text
22/tcp    SSH
51820/udp AWG
8888/tcp  MTProxy
```

Pi-hole доступен только через AWG:

```text
DNS: 10.8.0.1:53
WEB: http://10.8.0.1:8080/admin
```

## Установка

```bash
cd ansible
cp inventory.ini.example inventory.ini
cp group_vars/all.yml.example group_vars/all.yml
nano inventory.ini
nano group_vars/all.yml
ansible -i inventory.ini vps -m ping
ansible-playbook -i inventory.ini site.yml
```

## Проверка

```bash
docker ps
ss -tulpn
sudo nft list ruleset
sudo fail2ban-client status sshd
```

## AWG

Серверный конфиг должен находиться здесь:

```text
/opt/docker/amneziawg/config/awg0.conf
```

Запуск:

```bash
cd /opt/docker/amneziawg
docker compose up -d
docker exec -it amneziawg awg show
```

## Pi-hole

```bash
cd /opt/docker/pihole
docker compose up -d
docker logs pihole --tail=50
```

## MTProxy

```bash
cd /opt/docker/mtproxy
docker compose up -d
docker logs mtproxy --tail=50
```

Ссылка для Telegram будет в логах контейнера.

## Backup

```bash
sudo tar czf /root/vps-backup-$(date +%F).tar.gz /etc/nftables.conf /etc/fail2ban /etc/docker /opt/docker
```
