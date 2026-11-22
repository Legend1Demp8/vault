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
| Хранилище секретов KV V2 | OpenBao запустился, секреты доступны | Есть | Vault не видит данные |

### Тест 1: Хранилище секретов KV V1
<details>
<summary>Нажмите, чтобы развернуть список</summary>
	
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
</details>

### Тест 2: Хранилище секретов KV V2
<details>
<summary>Нажмите, чтобы развернуть список</summary>

#### 1. Инициализируем хранилище KV V2
```
docker exec -it vault-node1 vault secrets enable -path=secret-v2 kv-v2
```
#### 2. Заполняем данными хранилище KV V2
```
docker exec -it vault-node1 vault kv put secret-v2/app/db user="admin" pass="v1_password_2026"
docker exec -it vault-node1 vault kv patch secret-v2/app/db pass="v2_super_secret"

docker exec -it vault-node1 vault kv put secret-v2/app/tokens stripe="sk_live_998877" telegram="bot_112233"
docker exec -it vault-node1 vault kv metadata put -max-versions=3 -custom-metadata=owner="backend-team" -custom-metadata=env="prod" secret-v2/app/tokens

docker exec -i vault-node1 vault kv put secret-v2/app/service - <<EOF
{
  "api_url": "https://internal.local",
  "retries": 5,
  "debug_mode": false,
  "allowed_ips": ["10.10.10.1", "10.10.10.2"]
}
EOF
```
#### 3. Проверяем как сохранилось
```
for k in db service tokens; do echo "=== $k ==="; docker exec vault-node1 vault kv get -format=json secret-v2/app/$k | jq '.data.data'; done
=== db ===
{
  "pass": "v2_super_secret",
  "user": "admin"
}
=== service ===
{
  "allowed_ips": [
    "10.10.10.1",
    "10.10.10.2"
  ],
  "api_url": "https://internal.local",
  "debug_mode": false,
  "retries": 5
}
=== tokens ===
{
  "stripe": "sk_live_998877",
  "telegram": "bot_112233"
}

docker exec -it vault-node1 vault kv metadata get -format=json secret-v2/app/db
{
  "request_id": "8e18ffef-f844-e2be-5d72-ec4f911755ca",
  "lease_id": "",
  "lease_duration": 0,
  "renewable": false,
  "data": {
    "cas_required": false,
    "created_time": "2026-11-22T12:26:43.382922517Z",
    "current_version": 2,
    "custom_metadata": null,
    "delete_version_after": "0s",
    "last_updated_by": {
      "actor": "root",
      "client_id": "0DHqvq2D77kL2/JTPSZkTMJbkFVmUu0TzMi0jiXcFy8=",
      "operation": "patch"
    },
    "max_versions": 0,
    "oldest_version": 0,
    "updated_time": "2026-11-22T12:30:16.156196898Z",
    "versions": {
      "1": {
        "created_by": {
          "actor": "root",
          "client_id": "0DHqvq2D77kL2/JTPSZkTMJbkFVmUu0TzMi0jiXcFy8=",
          "operation": "create"
        },
        "created_time": "2026-11-22T12:26:43.382922517Z",
        "deleted_by": null,
        "deletion_time": "",
        "destroyed": false
      },
      "2": {
        "created_by": {
          "actor": "root",
          "client_id": "0DHqvq2D77kL2/JTPSZkTMJbkFVmUu0TzMi0jiXcFy8=",
          "operation": "patch"
        },
        "created_time": "2026-11-22T12:30:16.156196898Z",
        "deleted_by": null,
        "deletion_time": "",
        "destroyed": false
      }
    }
  },
  "warnings": null,
  "mount_type": "kv"
}

docker exec -it vault-node1 vault kv metadata get -format=json secret-v2/app/tokens
{
  "request_id": "0eb21a00-00db-9747-838f-4956322b6b48",
  "lease_id": "",
  "lease_duration": 0,
  "renewable": false,
  "data": {
    "cas_required": false,
    "created_time": "2026-11-22T12:28:40.084624758Z",
    "current_version": 1,
    "custom_metadata": {
      "env": "prod",
      "owner": "backend-team"
    },
    "delete_version_after": "0s",
    "last_updated_by": {
      "actor": "root",
      "client_id": "0DHqvq2D77kL2/JTPSZkTMJbkFVmUu0TzMi0jiXcFy8=",
      "operation": "create"
    },
    "max_versions": 3,
    "oldest_version": 0,
    "updated_time": "2026-11-22T12:28:40.084624758Z",
    "versions": {
      "1": {
        "created_by": {
          "actor": "root",
          "client_id": "0DHqvq2D77kL2/JTPSZkTMJbkFVmUu0TzMi0jiXcFy8=",
          "operation": "create"
        },
        "created_time": "2026-11-22T12:28:40.084624758Z",
        "deleted_by": null,
        "deletion_time": "",
        "destroyed": false
      }
    }
  },
  "warnings": null,
  "mount_type": "kv"
}

```
#### 4. Переезд на OpenBao и проверка
```

```

</details>

### Тест N: Хранилище секретов KV V1
<details>
<summary>Нажмите, чтобы развернуть список</summary>

</details>



















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
