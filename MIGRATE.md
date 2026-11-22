## Переезд Vault CE (2.2.2) в OpenBao (2.7.3)
### Основные изменения
#### 1. Добавить переменную в файл .env
```.env
...
OPENBAO_VERSION=2.7.3
```
#### 2. Заменить образ в `docker-compose.yml`
Для сервисов `vault-node1`, `vault-node2` и `vault-node3` обновите параметр `image`:
```diff
-   image: haproxy:${HAPROXY_VERSION}
+   image: openbao/openbao:${OPENBAO_VERSION}
```

#### 3. Обновить команду запуска в `docker-compose.yml`
Для сервисов `vault-node1`, `vault-node2` и `vault-node3` обновите параметр `commandcat`:
```diff
- command: vault server -config=/vault/config/vault.hcl
+ command: bao server -config=/vault/config/vault.hcl
```

В OpenBao без проблем переезжают практически все стандартные ресурсы HashiCorp Vault CE: секреты, методы аутентификации, политики ACL, настройки PKI/Transit, токены и аудит-логи.
