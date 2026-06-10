# TODO

## AmneziaWG

- Генерация server.key/server.pub
- Генерация client keys
- Генерация:
  - openwrt.conf
  - pc.conf
  - mobile.conf
  - mb.conf
- Автоматический docker compose up -d
- Экспорт конфигов в /opt/docker/amneziawg/clients

## Backup

- Daily backup 03:00
- Retention 30 days
- Rotation weekly/monthly

## Validation

- ansible-playbook --syntax-check
- ansible-lint