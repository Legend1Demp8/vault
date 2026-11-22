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

## Проверка переезда конкретных функций
### Таблица тестирования
| Функция | Результат переноса | Изменения в структуре данных | Повторный перенос в Vault |
| --- | --- | --- | --- |
| Хранилище секретов KV V1 | OpenBao запустился, секреты доступны | Есть | Vault не видит данные |
| Ячейка 4 | Ячейка 5 | Ячейка 6 |

### Хранилище секретов KV V1
#### 1. Инициализируем хранилище KV V1
```
docker exec -it vault-node1 vault secrets enable -path=secret-v1 kv-v1
```

#### 2. Заполняем данными хранилище KV V1
```
docker exec -it vault-node1 vault kv put secret-v1/legacy/db host="10.10.10.10" port="1010" password="old_password_1010"
docker exec -it vault-node1 vault kv put secret-v1/legacy/config mode="old_string_1010"
docker exec -i vault-node1 vault kv put secret-v1/legacy/cert crt=- <<EOF
-----BEGIN CERTIFICATE-----
old_cert_1010
-----END CERTIFICATE-----
EOF
```

#### 3. Проверяем как сохранилось
```
docker exec -it vault-node1 vault kv list secret-v1/legacy
Keys
----
cert
config
db
```
```
for k in db config cert; do echo "=== $k ==="; docker exec vault-node1 vault kv get -format=json secret-v1/legacy/$k; done
=== db ===
{
  "request_id": "bd260f8b-ce18-4703-b9af-ad7479d6633b",
  "lease_id": "",
  "lease_duration": 2764800,
  "renewable": false,
  "data": {
    "host": "10.10.10.10",
    "password": "old_password_1010",
    "port": "1010"
  },
  "warnings": null,
  "mount_type": "kv"
}
=== config ===
{
  "request_id": "58d698b3-1ad9-42f2-e448-26282d6bf810",
  "lease_id": "",
  "lease_duration": 2764800,
  "renewable": false,
  "data": {
    "mode": "old_string_1010"
  },
  "warnings": null,
  "mount_type": "kv"
}
=== cert ===
{
  "request_id": "53a4ac32-0d3a-70f6-eee5-18904003dc3a",
  "lease_id": "",
  "lease_duration": 2764800,
  "renewable": false,
  "data": {
    "crt": "-----BEGIN CERTIFICATE-----\nold_cert_1010\n-----END CERTIFICATE-----\n"
  },
  "warnings": null,
  "mount_type": "kv"
}
```
#### 4. Переезд на OpenBao и проверка
```
=== db ===
{
  "request_id": "5a76e0ee-ca54-d0fb-2c8a-61f14d317007",
  "lease_id": "",
  "lease_duration": 2764800,
  "renewable": false,
  "data": {
    "host": "10.10.10.10",
    "password": "old_password_1010",
    "port": "1010"
  },
  "warnings": null
}
=== config ===
{
  "request_id": "91ac8e5d-3687-dbbb-ab2b-5f2169a3b07e",
  "lease_id": "",
  "lease_duration": 2764800,
  "renewable": false,
  "data": {
    "mode": "old_string_1010"
  },
  "warnings": null
}
=== cert ===
{
  "request_id": "b7cdee4e-262b-3a20-3a2d-cf3386424266",
  "lease_id": "",
  "lease_duration": 2764800,
  "renewable": false,
  "data": {
    "crt": "-----BEGIN CERTIFICATE-----\nold_cert_1010\n-----END CERTIFICATE-----\n"
  },
  "warnings": null
}
```


#### Хранилище секретов KV V2

# Инициализируем хранилище KV V2
docker exec -it vault-node1 vault secrets enable -path=secret-v2 kv-v2

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
