# Переезд Vault CE (2.2.2) в OpenBao (2.7.3)

## Нюансы переноса
### Что переедет без проблем (об этом не нужно думать)
Если хранилище успешно смонтировалось и распечаталось (или вы переносите состояние через API), следующие сущности работают идентично на уровне протокола и структуры данных:
• Хранилище секретов KV (v1 и v2): все секреты, история версий, кастомные метаданные и настройки TTL.
• Криптография Transit: ключи шифрования (AES-GCM, RSA, Ed25519), ротированные версии ключей. Строки вида vault:v1:..., зашифрованные в Vault, без проблем расшифровываются в OpenBao.
• PKI (Центр сертификации): корневые и промежуточные CA, приватные ключи CA, роли выпуска, шаблоны, выпущенные сертификаты и списки отзыва (CRL).
• Базовые методы аутентификации:
	• AppRole (существующие role_id и secret_id остаются валидными).
	• Userpass, LDAP, JWT / OIDC, Kubernetes, TLS Cert.
• Система доступа и аудита:
	• Политики ACL (весь синтаксис HCL).
	• Сущности Identity (Entities, Groups, Aliases).
	• Активные сервисные токены и root-токен (продолжают работать со старым сроком жизни).
	• Аудит-устройства (file, syslog, socket).

### Что не переедет и вызовет падение OpenBao
- Auto-Unseal через облачные KMS или PKCS#11 без плагинов: в OpenBao 2.7 все встроенные механизмы распечатывания (awskms, gcpckms, azurekeyvault, alicloudkms, ocikms, pkcs11) удалены из основного бинарника и вынесены во внешние плагины. Если у вас обычный Shamir Unseal (ручной ввод ключей), всё запустится штатно.
- FQDN с точкой на конце в PKI: из-за перехода на Go 1.27 OpenBao 2.7 больше не принимает домены вида example.com. в настройках PKI.



## Процесс переезда
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
-   image: hashicorp/vault:${VAULT_VERSION}
+   image: openbao/openbao:${OPENBAO_VERSION}
```

#### 4. Обновить команду запуска в `docker-compose.yml`
Для сервисов `vault-node1`, `vault-node2` и `vault-node3` обновите параметр `command`:
```diff
-   command: vault server -config=/vault/config/vault.hcl
+   command: bao server -config=/vault/config/vault.hcl
```
