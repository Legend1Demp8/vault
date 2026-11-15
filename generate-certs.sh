#!/bin/sh

# Прерывать выполнение скрипта при любой ошибке
set -e

# ==============================================================================
# ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ И КОНСТАНТЫ
# ==============================================================================
CA_DIR="/certs/ca"
CA_CERT="${CA_DIR}/ca.crt"
CA_KEY="${CA_DIR}/ca.key"

# Порог обновления сертификата: 30 дней в секундах (30 * 24 * 60 * 60)
RENEW_SECONDS=2592000

# Общие параметры субъекта (Subject) для всех сертификатов
CERT_SUBJ_PREFIX="/C=RU/ST=Local/L=Lab/O=VaultCluster"

# ==============================================================================
# ФУНКЦИИ
# ==============================================================================

# Шаг 1: Проверка обязательных переменных окружения и установка пакетов
check_prerequisites() {
    echo "---> [Шаг 1] Проверка окружения и зависимостей..."

    if [ -z "$HOST_IP" ]; then
        echo "Ошибка: переменная HOST_IP не задана!"
        exit 1
    fi

    # Устанавливаем openssl только если он еще не установлен (актуально для Alpine)
    if ! command -v openssl >/dev/null 2>&1; then
        echo "Утилита openssl не найдена. Выполняем установку..."
        apk add --no-cache openssl
    fi
}

# Шаг 2: Создание корневого центра сертификации (Root CA)
setup_root_ca() {
    echo "---> [Шаг 2] Проверка корневого центра сертификации (Root CA)..."
    mkdir -p "$CA_DIR"

    # Генерируем CA только если сертификат или ключ отсутствуют
    if [ ! -f "$CA_CERT" ] || [ ! -f "$CA_KEY" ]; then
        echo "Генерация нового корневого CA на базе ECDSA P-384 (срок действия 10 лет)..."
        openssl ecparam -name secp384r1 -genkey -noout -out "$CA_KEY"
        openssl req -x509 -new -nodes -key "$CA_KEY" -sha256 -days 3650 \
            -out "$CA_CERT" \
            -subj "${CERT_SUBJ_PREFIX}/CN=Vault Root CA"
    else
        echo "Корневой CA уже существует. Пропускаем."
    fi
}

# Вспомогательная функция: Выпуск сертификата, подписанного нашим Root CA
# Аргументы:
#   $1 - Директория для сохранения файлов
#   $2 - Основное доменное имя (Common Name и DNS.1)
#   $3 - Имя контейнера (DNS.2)
issue_certificate() {
    TARGET_DIR="$1"
    DOMAIN_NAME="$2"
    CONTAINER_NAME="$3"

    CERT_FILE="${TARGET_DIR}/vault.crt"
    KEY_FILE="${TARGET_DIR}/vault.key"
    CSR_FILE="${TARGET_DIR}/vault.csr"
    EXT_FILE="${TARGET_DIR}/vault.ext"

    mkdir -p "$TARGET_DIR"
    cp "$CA_CERT" "${TARGET_DIR}/ca.crt"

    # Проверяем, существует ли сертификат и не истекает ли он в ближайшие 30 дней
    if [ -f "$CERT_FILE" ] && openssl x509 -checkend "$RENEW_SECONDS" -noout -in "$CERT_FILE" >/dev/null 2>&1; then
        echo "Сертификат для ${DOMAIN_NAME} еще действителен. Пропускаем."
        return 0
    fi

    echo "Выпуск сертификата ECDSA P-256 для ${DOMAIN_NAME} на 365 дней..."

    # 1. Генерация приватного ключа на эллиптической кривой P-256
    openssl ecparam -name prime256v1 -genkey -noout -out "$KEY_FILE"

    # 2. Создание файла расширений (Subject Alternative Names - SAN)
    cat << EOT > "$EXT_FILE"
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${DOMAIN_NAME}
DNS.2 = ${CONTAINER_NAME}
DNS.3 = localhost
IP.1 = ${HOST_IP}
IP.2 = 127.0.0.1
EOT

    # 3. Создание запроса на подпись сертификата (CSR)
    openssl req -new -key "$KEY_FILE" -out "$CSR_FILE" \
        -subj "${CERT_SUBJ_PREFIX}/CN=${DOMAIN_NAME}"

    # 4. Подпись сертификата нашим корневым CA
    openssl x509 -req -in "$CSR_FILE" -CA "$CA_CERT" -CAkey "$CA_KEY" -CAcreateserial \
        -out "$CERT_FILE" -days 365 -sha256 -extfile "$EXT_FILE"

    # 5. Удаление временных файлов и настройка прав доступа
    rm -f "$CSR_FILE" "$EXT_FILE"
    chmod 644 "$CERT_FILE" "$KEY_FILE" "${TARGET_DIR}/ca.crt"
}

# Шаг 3: Генерация конфигурационных файлов для 3 нод Vault
generate_vault_configs() {
    echo "---> [Шаг 3] Генерация конфигураций для нод Vault..."

    for i in 1 2 3; do
        NODE_CONFIG_DIR="/configs/node${i}/config"
        echo "Создание конфига для ноды ${i}..."

        # Определяем номера двух соседних нод для текущей ноды i
        case "$i" in
            1) PEER1=2; PEER2=3 ;;
            2) PEER1=1; PEER2=3 ;;
            3) PEER1=1; PEER2=2 ;;
        esac

        mkdir -p "$NODE_CONFIG_DIR"
        sed -e "s/__NODE_NUM__/${i}/g" \
            -e "s/__PEER_1__/${PEER1}/g" \
            -e "s/__PEER_2__/${PEER2}/g" \
            -e "s/__HOST_IP__/${HOST_IP}/g" \
            /vault.hcl.tpl > "${NODE_CONFIG_DIR}/vault.hcl"

        chmod 644 "${NODE_CONFIG_DIR}/vault.hcl"
    done
}

# Шаг 4: Выпуск сертификатов для 3 нод Vault
issue_vault_certs() {
    echo "---> [Шаг 4] Выпуск сертификатов для нод Vault..."

    for i in 1 2 3; do
        NODE_CERT_DIR="/certs/vault${i}"
        NODE_CONTAINER="vault-node${i}"
        NODE_DOMAIN="vault${i}.${HOST_IP}.nip.io"

        echo "Проверка сертификата для ноды ${i} (${NODE_DOMAIN})..."
        issue_certificate "$NODE_CERT_DIR" "$NODE_DOMAIN" "$NODE_CONTAINER"
    done
}

# Шаг 5: Генерация конфигурационного файла для балансировщика HAProxy
generate_haproxy_config() {
    echo "---> [Шаг 5] Генерация конфигурации для HAProxy..."

    HAPROXY_CONFIG_DIR="/configs/haproxy"
    echo "Создание конфига для HAProxy..."

    mkdir -p "$HAPROXY_CONFIG_DIR"
    sed -e "s/__HOST_IP__/${HOST_IP}/g" \
        /haproxy.cfg.tpl > "${HAPROXY_CONFIG_DIR}/haproxy.cfg"
    chmod 644 "${HAPROXY_CONFIG_DIR}/haproxy.cfg"
}

# Шаг 6: Выпуск сертификата и сборка PEM-файла для балансировщика HAProxy
issue_haproxy_cert() {
    echo "---> [Шаг 6] Выпуск сертификата для HAProxy..."

    HAPROXY_CERT_DIR="/certs/haproxy"
    HAPROXY_DOMAIN="vault.${HOST_IP}.nip.io"

    CERT_FILE="${HAPROXY_CERT_DIR}/vault.crt"
    KEY_FILE="${HAPROXY_CERT_DIR}/vault.key"
    PEM_FILE="${HAPROXY_CERT_DIR}/vault.pem"

    # Выпуск сертификата для HAProxy
    issue_certificate "$HAPROXY_CERT_DIR" "$HAPROXY_DOMAIN" "vault-haproxy"

    # Собираем единый PEM-файл только если его нет или сертификат был только что обновлен
    if [ ! -f "$PEM_FILE" ] || [ "$CERT_FILE" -nt "$PEM_FILE" ]; then
        echo "Сборка единого файла ${PEM_FILE} для HAProxy..."
        cat "$CERT_FILE" "$KEY_FILE" > "$PEM_FILE"
        chmod 644 "$PEM_FILE"
    else
        echo "Файл ${PEM_FILE} для HAProxy актуален. Пропускаем."
    fi
}

# ==============================================================================
# ТОЧКА ВХОДА (ПОСЛЕДОВАТЕЛЬНЫЙ ЗАПУСК ШАГОВ)
# ==============================================================================
main() {
    check_prerequisites
    setup_root_ca
    generate_vault_configs
    issue_vault_certs
    generate_haproxy_config
    issue_haproxy_cert

    echo "=================================================================="
    echo "Готово! Все конфиги и сертификаты для IP ${HOST_IP} успешно созданы."
    echo "=================================================================="
}

# Запуск главной функции
main
