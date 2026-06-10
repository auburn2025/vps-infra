# VPS Infrastructure

Ansible-проект для быстрого восстановления VPS с сервисами:

- SSH hardening
- unattended security updates
- nftables
- Fail2ban
- Docker Engine + Compose plugin
- AmneziaWG server в Docker
- Pi-hole в Docker
- MTProxy FakeTLS в Docker
- backup-архив конфигурации

Целевая ОС: Ubuntu 26.04 LTS / Ubuntu 24.04 LTS.

> Важно: приватные ключи, пароли, MTProxy secret, реальные клиентские `.conf` и inventory не должны храниться в публичном репозитории.

---

## 1. Подготовка локальной машины

Ubuntu / Debian / WSL:

```bash
sudo apt update
sudo apt install -y ansible openssh-client git
```

Fedora:

```bash
sudo dnf install -y ansible openssh-clients git
```

Проверка:

```bash
ansible --version
ssh -V
```

---

## 2. Клонирование репозитория

```bash
git clone https://github.com/auburn2025/vps-infra.git
cd vps-infra/ansible
```

---

## 3. Подготовка inventory

```bash
cp inventory.ini.example inventory.ini
nano inventory.ini
```

Пример:

```ini
[vps]
31.77.131.246 ansible_user=play2ai ansible_ssh_private_key_file=/home/asemenov/temp/vpsplay
```

Проверить SSH:

```bash
ssh -i /home/asemenov/temp/vpsplay play2ai@31.77.131.246
```

---

## 4. Подготовка переменных

```bash
cp group_vars/all.yml.example group_vars/all.yml
nano group_vars/all.yml
```

Минимально проверить/заполнить:

```yaml
vps_public_ip: "31.77.131.246"
admin_user: "play2ai"
external_iface: "ens3"
awg_port: 51820
awg_subnet: "10.8.0.0/24"
awg_server_ip: "10.8.0.1"
pihole_web_port: 8080
mtproxy_port: 8888
mtproxy_fake_tls_domain: "vk.com"
```

---

## 5. Ansible Vault для секретов

Создать файл секретов:

```bash
cp group_vars/vault.yml.example group_vars/vault.yml
ansible-vault encrypt group_vars/vault.yml
```

Редактировать:

```bash
ansible-vault edit group_vars/vault.yml
```

Запуск с vault:

```bash
ansible-playbook -i inventory.ini site.yml --ask-vault-pass
```

---

## 6. Проверка подключения Ansible

```bash
ansible -i inventory.ini vps -m ping
```

Ожидаемо:

```text
SUCCESS => {"ping": "pong"}
```

Если sudo требует пароль:

```bash
ansible -i inventory.ini vps -m ping --ask-become-pass
```

---

## 7. Установка всего на новый сервер

Полный запуск:

```bash
ansible-playbook -i inventory.ini site.yml --ask-vault-pass
```

Если sudo требует пароль:

```bash
ansible-playbook -i inventory.ini site.yml --ask-vault-pass --ask-become-pass
```

---

## 8. Запуск отдельных ролей

```bash
ansible-playbook -i inventory.ini site.yml --tags base --ask-vault-pass
ansible-playbook -i inventory.ini site.yml --tags docker --ask-vault-pass
ansible-playbook -i inventory.ini site.yml --tags nftables --ask-vault-pass
ansible-playbook -i inventory.ini site.yml --tags fail2ban --ask-vault-pass
ansible-playbook -i inventory.ini site.yml --tags amneziawg --ask-vault-pass
ansible-playbook -i inventory.ini site.yml --tags pihole --ask-vault-pass
ansible-playbook -i inventory.ini site.yml --tags mtproxy --ask-vault-pass
ansible-playbook -i inventory.ini site.yml --tags backup --ask-vault-pass
```

---

## 9. Проверка после установки на VPS

```bash
ssh play2ai@31.77.131.246
```

Проверить сервисы:

```bash
docker ps
ss -tulpn
sudo nft list ruleset
sudo fail2ban-client status sshd
```

Ожидаемые открытые внешние порты:

```text
22/tcp       SSH
51820/udp    AmneziaWG
8888/tcp     MTProxy
```

Pi-hole:

```text
DNS: 10.8.0.1:53 через AWG
Web: http://10.8.0.1:8080/admin через AWG
```

Проверка DNS через VPN:

```bash
nslookup google.com 10.8.0.1
nslookup doubleclick.net 10.8.0.1
```

Ожидаемо для заблокированного домена:

```text
0.0.0.0
```

---

## 10. Проверка MTProxy

На VPS:

```bash
cd /opt/docker/mtproxy
docker logs mtproxy --tail=50
ss -tulpn | grep 8888
nc -vz 127.0.0.1 8888
```

В логах будет ссылка вида:

```text
https://t.me/proxy?server=<IP>&port=8888&secret=<SECRET>
```

Открыть ссылку в Telegram и нажать `Enable Proxy`.

---

## 11. Клиентские AWG-конфиги

После генерации/восстановления конфиги должны лежать на VPS:

```text
/opt/docker/amneziawg/config/openwrt.conf
/opt/docker/amneziawg/config/pc.conf
/opt/docker/amneziawg/config/mobile.conf
/opt/docker/amneziawg/config/mb.conf
```

Скачать:

```bash
scp -i /home/asemenov/temp/vpsplay play2ai@31.77.131.246:/opt/docker/amneziawg/config/openwrt.conf .
scp -i /home/asemenov/temp/vpsplay play2ai@31.77.131.246:/opt/docker/amneziawg/config/pc.conf .
scp -i /home/asemenov/temp/vpsplay play2ai@31.77.131.246:/opt/docker/amneziawg/config/mobile.conf .
scp -i /home/asemenov/temp/vpsplay play2ai@31.77.131.246:/opt/docker/amneziawg/config/mb.conf .
```

---

## 12. Backup

Создать backup вручную:

```bash
sudo tar czf /root/vps-backup-$(date +%F).tar.gz \
  /etc/nftables.conf \
  /etc/fail2ban \
  /etc/docker \
  /opt/docker
```

Скачать:

```bash
scp -i /home/asemenov/temp/vpsplay play2ai@31.77.131.246:/root/vps-backup-YYYY-MM-DD.tar.gz .
```

---

## 13. Безопасность

Не коммитить в Git:

- `inventory.ini`
- `group_vars/all.yml`
- `group_vars/vault.yml`
- `*.key`
- `*.conf` с приватными ключами
- `.env`
- backup-архивы
- Pi-hole пароль
- MTProxy secret

Публичный репозиторий должен содержать только шаблоны и роли.

---

## 14. Быстрая диагностика

```bash
systemctl status ssh --no-pager
systemctl status docker --no-pager
systemctl status nftables --no-pager
systemctl status fail2ban --no-pager

docker ps
ss -tulpn
sudo nft list ruleset
sudo fail2ban-client status sshd
```

AWG:

```bash
docker exec -it amneziawg awg show
ip a | grep awg -A5
```

Pi-hole:

```bash
docker logs pihole --tail=50
```

MTProxy:

```bash
docker logs mtproxy --tail=50
```
