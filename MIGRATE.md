## Переезд Vault CE (2.2.2) в OpenBao (2.7.3)

### Необходимые изменения в проекте

#### 1. Остановить действующий кластер Vault
```bash
docker compose down
```

#### 2. Добавить переменную в файл `.env`
```diff
+   OPENBAO_VERSION=2.7.3
```

#### 3. Заменить образ в `docker-compose.yml`
Для сервисов `vault-node1`, `vault-node2` и `vault-node3` обновите параметр `image`:
```diff
-   image: haproxy:\${HAPROXY_VERSION}
+   image: openbao/openbao:\${OPENBAO_VERSION}
```

#### 4. Обновить команду запуска в `docker-compose.yml`
Для сервисов `vault-node1`, `vault-node2` и `vault-node3` обновите параметр `command`:
```diff
-   command: vault server -config=/vault/config/vault.hcl
+   command: bao server -config=/vault/config/vault.hcl
```


В OpenBao без проблем переезжают практически все стандартные ресурсы HashiCorp Vault CE: секреты, методы аутентификации, политики ACL, настройки PKI/Transit, токены и аудит-логи.
