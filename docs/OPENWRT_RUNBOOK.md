# OpenWrt 25.12.4: восстановление AWG + Pi-hole DNS + PBR + MTProxy

Актуально для:

- Router: Xiaomi Mi Router AX3000T
- OpenWrt: 25.12.4
- Package manager: `apk`
- WAN gateway: `192.168.0.1`
- LAN: `192.168.1.0/24`
- VPS: `31.77.131.246`
- AWG server: `31.77.131.246:51820`
- AWG client interface on OpenWrt: `awg1`
- AWG client IP: `10.8.0.2/24`
- Pi-hole DNS on VPS: `10.8.0.1`
- MTProxy: `31.77.131.246:8888`
- Mode: split tunneling
  - ChatGPT/OpenAI -> AWG
  - YouTube -> AWG
  - DNS -> Pi-hole through AWG
  - Telegram -> MTProxy
  - Everything else -> WAN

> Важно: приватные ключи AWG и secret MTProxy в этот файл не включены. Их нужно брать из актуальных конфигов:
>
> - `/opt/docker/amneziawg/config/openwrt.conf` на VPS
> - `/opt/docker/mtproxy/docker-compose.yml` на VPS

---

## 0. Перед началом

Подключиться к роутеру:

```sh
ssh root@192.168.1.1
```

Сделать бэкап текущей конфигурации:

```sh
sysupgrade -b /tmp/openwrt-before-awg-pbr.tar.gz
ls -lh /tmp/openwrt-before-awg-pbr.tar.gz
```

---

## 1. Проверка версии OpenWrt

```sh
ubus call system board
```

Ожидаемо:

```text
OpenWrt 25.12.4
kernel 6.12.x
model Xiaomi Mi Router AX3000T
```

---

## 2. Установка AmneziaWG-клиента

Проверить, есть ли пакеты:

```sh
apk update
apk info | grep -Ei "amnezia|wireguard|pbr"
```

Официальных `amnezia` пакетов может не быть. Тогда использовать установочный скрипт AWG для OpenWrt:

```sh
ping -c 3 github.com

sh <(wget -4 -O - https://raw.githubusercontent.com/Slava-Shchipunov/awg-openwrt/refs/heads/master/amneziawg-install.sh)
```

Проверка:

```sh
which awg
ls /lib/netifd/proto | grep amnezia
```

Ожидаемо:

```text
/usr/bin/awg
amneziawg.sh
```

---

## 3. Настройка AWG-интерфейса `awg1`

Вставить значения из актуального `openwrt.conf`:

- `<OPENWRT_PRIVATE_KEY>`
- `<SERVER_PUBLIC_KEY>`
- endpoint `31.77.131.246`
- port `51820`

Текущие параметры обфускации:

```text
Jc    = 91
Jmin  = 181
Jmax  = 415
H1    = 448149634
H2    = 700583532
H3    = 1733601552
H4    = 1358820585
S1    = 9
S2    = 26
```

Команды:

```sh
uci set network.awg1='interface'
uci set network.awg1.proto='amneziawg'
uci set network.awg1.private_key='<OPENWRT_PRIVATE_KEY>'
uci set network.awg1.listen_port='51821'
uci set network.awg1.addresses='10.8.0.2/24'

uci set network.awg1.awg_jc='91'
uci set network.awg1.awg_jmin='181'
uci set network.awg1.awg_jmax='415'
uci set network.awg1.awg_s1='9'
uci set network.awg1.awg_s2='26'
uci set network.awg1.awg_h1='448149634'
uci set network.awg1.awg_h2='700583532'
uci set network.awg1.awg_h3='1733601552'
uci set network.awg1.awg_h4='1358820585'

uci add network amneziawg_awg1
uci set network.@amneziawg_awg1[-1].name='awg1_client'
uci set network.@amneziawg_awg1[-1].interface='awg1'
uci set network.@amneziawg_awg1[-1].public_key='<SERVER_PUBLIC_KEY>'
uci set network.@amneziawg_awg1[-1].endpoint_host='31.77.131.246'
uci set network.@amneziawg_awg1[-1].endpoint_port='51820'
uci set network.@amneziawg_awg1[-1].allowed_ips='0.0.0.0/0'
uci add_list network.@amneziawg_awg1[-1].allowed_ips='::/0'
uci set network.@amneziawg_awg1[-1].persistent_keepalive='25'

# Важно для split tunneling:
# не добавлять default route через AWG в main table.
uci set network.@amneziawg_awg1[-1].route_allowed_ips='0'

# DNS Pi-hole через AWG
uci set network.awg1.peerdns='0'
uci add_list network.awg1.dns='10.8.0.1'

uci commit network
```

Поднять интерфейс:

```sh
ifup awg1
sleep 10
```

Проверка:

```sh
ifstatus awg1
awg show
ping -c 3 10.8.0.1
```

Ожидаемо:

```text
latest handshake: есть
ping 10.8.0.1: 0% packet loss
```

---

## 4. Firewall-зона для AWG

Создать зону `awg1` и forwarding `lan -> awg1`.

```sh
uci add firewall zone
uci set firewall.@zone[-1].name='awg1'
uci set firewall.@zone[-1].network='awg1'
uci set firewall.@zone[-1].input='REJECT'
uci set firewall.@zone[-1].output='ACCEPT'
uci set firewall.@zone[-1].forward='REJECT'
uci set firewall.@zone[-1].masq='1'
uci set firewall.@zone[-1].mtu_fix='1'
uci set firewall.@zone[-1].family='ipv4'

uci add firewall forwarding
uci set firewall.@forwarding[-1].name='awg1-lan'
uci set firewall.@forwarding[-1].src='lan'
uci set firewall.@forwarding[-1].dest='awg1'
uci set firewall.@forwarding[-1].family='ipv4'

uci commit firewall
service firewall restart
```

Проверка:

```sh
uci show firewall | grep awg1
```

---

## 5. Настройка DNS через Pi-hole

Pi-hole находится на VPS:

```text
10.8.0.1:53
```

Проверка с роутера:

```sh
nslookup google.com 10.8.0.1
```

Настроить dnsmasq так, чтобы он использовал resolv.conf.auto:

```sh
cp /etc/config/dhcp /root/dhcp.backup

uci delete dhcp.@dnsmasq[0].doh_server 2>/dev/null
uci delete dhcp.@dnsmasq[0].doh_backup_server 2>/dev/null
uci delete dhcp.@dnsmasq[0].doh_backup_noresolv 2>/dev/null

uci del_list dhcp.@dnsmasq[0].server='127.0.0.1#5053' 2>/dev/null
uci del_list dhcp.@dnsmasq[0].server='127.0.0.1#5054' 2>/dev/null

uci set dhcp.@dnsmasq[0].noresolv='0'
uci set dhcp.@dnsmasq[0].resolvfile='/tmp/resolv.conf.d/resolv.conf.auto'

uci commit dhcp
service dnsmasq restart
```

Проверка:

```sh
cat /tmp/resolv.conf.d/resolv.conf.auto
nslookup doubleclick.net 10.8.0.1
```

Ожидаемо для заблокированного домена:

```text
0.0.0.0
```

---

## 6. Установка PBR

```sh
apk update
apk add pbr luci-app-pbr luci-i18n-pbr-ru
```

Включить службу:

```sh
/etc/init.d/pbr enable
/etc/init.d/pbr start
```

Проверка:

```sh
/etc/init.d/pbr status
```

---

## 7. Настройка split tunneling через PBR

Цель:

```text
ChatGPT/OpenAI -> awg1
YouTube        -> awg1
Остальное      -> wan
```

Базовая конфигурация PBR:

```sh
uci set pbr.config.enabled='1'
uci set pbr.config.verbosity='2'
uci set pbr.config.strict_enforcement='1'
uci set pbr.config.resolver_set='dnsmasq.nftset'
uci set pbr.config.resolver_instance='*'
uci set pbr.config.ipv6_enabled='0'
uci set pbr.config.rule_create_option='add'
uci set pbr.config.supported_interface='awg1'
uci commit pbr
```

Добавить/обновить политику ChatGPT/OpenAI:

```sh
# Если политики уже есть, лучше проверить индексы:
uci show pbr | grep ChatGPT

# Вариант через новую policy:
uci add pbr policy
uci set pbr.@policy[-1].name='ChatGPT_via_AWG'
uci set pbr.@policy[-1].interface='awg1'
uci set pbr.@policy[-1].dest_addr='chatgpt.com openai.com auth.openai.com cdn.oaistatic.com'
uci set pbr.@policy[-1].strategy='strict'
uci set pbr.@policy[-1].enabled='1'
```

Добавить/обновить политику YouTube:

```sh
uci add pbr policy
uci set pbr.@policy[-1].name='YouTube_via_AWG'
uci set pbr.@policy[-1].interface='awg1'
uci set pbr.@policy[-1].dest_addr='youtube.com youtu.be youtube-nocookie.com youtube-ui.l.google.com youtubei.googleapis.com youtubeembeddedplayer.googleapis.com youtubekids.com googlevideo.com ytimg.com ytimg.l.google.com yt3.ggpht.com yt4.ggpht.com yt3.googleusercontent.com jnn-pa.googleapis.com wide-youtube.l.google.com yt-video-upload.l.google.com stable.dl2.discordapp.net'
uci set pbr.@policy[-1].strategy='strict'
uci set pbr.@policy[-1].enabled='1'
```

Сохранить и перезапустить:

```sh
uci commit pbr
/etc/init.d/pbr restart
```

Проверка логов:

```sh
logread | grep pbr
```

Ожидаемые строки:

```text
Routing 'ChatGPT_via_AWG' via awg1 [✓]
Routing 'YouTube_via_AWG' via awg1 [✓]
pbr started with gateways: wan/192.168.0.1 awg1/10.8.0.2
```

---

## 8. Проверка маршрутов

Проверить main table:

```sh
ip route
```

Важно: не должно быть

```text
default dev awg1
```

Должно быть:

```text
default via 192.168.0.1 dev wan
10.8.0.0/24 dev awg1
31.77.131.246 via 192.168.0.1 dev wan
```

Если default route отсутствует, временно вернуть:

```sh
ip route add default via 192.168.0.1 dev wan
```

Если проблема повторяется после reboot, явно задать gateway:

```sh
uci set network.wan.gateway='192.168.0.1'
uci commit network
service network restart
```

Проверить PBR-таблицы:

```sh
ip route show table pbr_wan
ip route show table pbr_awg1
```

Ожидаемо:

```text
table pbr_wan:
default via 192.168.0.1 dev wan

table pbr_awg1:
default via 10.8.0.2 dev awg1
```

---

## 9. Проверка фактической работы

Обычный интернет:

```sh
curl -4 ifconfig.me
```

На роутере при split tunneling это может зависеть от PBR и local traffic. На ПК в LAN открыть:

```text
https://ifconfig.me
```

Ожидаемо: IP провайдера, не `31.77.131.246`.

Проверить AWG-счетчики:

```sh
awg show
```

Дальше:

1. Закрыть ChatGPT и YouTube.
2. Открыть Яндекс/Яндекс Музыку.
3. Проверить `awg show` — счетчики не должны быстро расти.
4. Открыть YouTube или ChatGPT.
5. Проверить `awg show` — счетчики должны расти.

---

## 10. Отключение/включение AWG вручную

Отключить:

```sh
ifdown awg1
```

Включить:

```sh
ifup awg1
```

Проверить:

```sh
awg show
ping -c 3 10.8.0.1
```

---

## 11. MTProxy

MTProxy работает на VPS отдельно.

Текущая схема:

```text
31.77.131.246:8888
FakeTLS domain: vk.com
```

Ссылка берется из логов контейнера на VPS:

```sh
cd /opt/docker/mtproxy
docker logs mtproxy --tail=30
```

Telegram не нужно отправлять через AWG/PBR, если он использует MTProxy.

---

## 12. Финальный бэкап OpenWrt

После успешной проверки:

```sh
sysupgrade -b /tmp/openwrt-after-awg-pbr-working.tar.gz
ls -lh /tmp/openwrt-after-awg-pbr-working.tar.gz
```

Скачать архив с роутера:

```sh
scp root@192.168.1.1:/tmp/openwrt-after-awg-pbr-working.tar.gz .
```

---

## 13. Команды диагностики

AWG:

```sh
awg show
ifstatus awg1
logread | grep -i awg
```

DNS:

```sh
cat /tmp/resolv.conf.d/resolv.conf.auto
nslookup google.com 10.8.0.1
nslookup doubleclick.net 10.8.0.1
```

PBR:

```sh
/etc/init.d/pbr status
logread | grep pbr
uci show pbr
ip rule
ip route
ip route show table pbr_wan
ip route show table pbr_awg1
nft list ruleset | grep pbr -A30
```

WAN:

```sh
ifstatus wan
ip route
ping -c 3 8.8.8.8
```

---

## 14. Важные замечания

1. Не включать `route_allowed_ips='1'` для `awg1`, если нужен split tunneling.
2. Если `route_allowed_ips='1'`, весь трафик пойдет через VPS.
3. Для split tunneling:
   - `route_allowed_ips='0'`
   - PBR включен
   - политики ChatGPT/YouTube enabled
   - default route должен быть через WAN
4. Pi-hole можно использовать через AWG даже при split tunneling.
5. Telegram лучше вести через MTProxy, а не через AWG.
