#!/bin/sh
set -e

if [ -z "$HOST_IP" ]; then
  echo "Ошибка: переменная HOST_IP не задана!"
  exit 1
fi

apk add --no-cache openssl

mkdir -p /certs/ca
cd /certs/ca

# 1. Корневой CA
if [ ! -f "ca.crt" ] || [ ! -f "ca.key" ]; then
  echo "Генерация корневого CA..."
  openssl genrsa -out ca.key 4096
  openssl req -x509 -new -nodes -key ca.key -sha256 -days 3650 -out ca.crt \
    -subj "/C=RU/ST=Local/L=Lab/O=VaultCluster/CN=Vault Root CA"
fi

# 30 дней в секундах
RENEW_SECONDS=2592000

# 2. Генерация сертификатов и конфигов для каждой из 3 нод Vault
for i in 1 2 3; do
  NODE_DIR="/certs/vault${i}"
  NODE_CONTAINER="vault-node${i}"
  NODE_DOMAIN="vault${i}.${HOST_IP}.nip.io"
  CERT_FILE="${NODE_DIR}/vault.crt"
  KEY_FILE="${NODE_DIR}/vault.key"

  mkdir -p "/configs/node${i}/config"
  sed -e "s/__NODE_NUM__/${i}/g" -e "s/__HOST_IP__/${HOST_IP}/g" /vault.hcl.tpl > "/configs/node${i}/config/vault.hcl"
  chmod 644 "/configs/node${i}/config/vault.hcl"

  mkdir -p "$NODE_DIR"
  cp /certs/ca/ca.crt "${NODE_DIR}/ca.crt"

  if [ -f "$CERT_FILE" ] && openssl x509 -checkend "$RENEW_SECONDS" -noout -in "$CERT_FILE" >/dev/null 2>&1; then
    echo "Сертификат для ${NODE_DOMAIN} еще действителен. Пропускаем."
    continue
  fi

  echo "Выпуск сертификата для ${NODE_DOMAIN} на 365 дней..."
  openssl genrsa -out "$KEY_FILE" 2048

  cat << EOT > "${NODE_DIR}/vault.ext"
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${NODE_DOMAIN}
DNS.2 = ${NODE_CONTAINER}
DNS.3 = localhost
IP.1 = ${HOST_IP}
IP.2 = 127.0.0.1
EOT

  openssl req -new -key "$KEY_FILE" -out "${NODE_DIR}/vault.csr" \
    -subj "/C=RU/ST=Local/L=Lab/O=VaultCluster/CN=${NODE_DOMAIN}"

  openssl x509 -req -in "${NODE_DIR}/vault.csr" -CA /certs/ca/ca.crt -CAkey /certs/ca/ca.key -CAcreateserial \
    -out "$CERT_FILE" -days 365 -sha256 -extfile "${NODE_DIR}/vault.ext"

  rm -f "${NODE_DIR}/vault.csr" "${NODE_DIR}/vault.ext"
  chmod 644 "$CERT_FILE" "$KEY_FILE" "${NODE_DIR}/ca.crt"
done

# 3. Генерация конфига и единого сертификата для HAProxy
HAPROXY_DIR="/certs/haproxy"
HAPROXY_DOMAIN="vault.${HOST_IP}.nip.io"
HAPROXY_CERT="${HAPROXY_DIR}/vault.crt"
HAPROXY_KEY="${HAPROXY_DIR}/vault.key"
HAPROXY_PEM="${HAPROXY_DIR}/vault.pem"

mkdir -p "/configs/haproxy"
sed -e "s/__HOST_IP__/${HOST_IP}/g" /haproxy.cfg.tpl > "/configs/haproxy/haproxy.cfg"
chmod 644 "/configs/haproxy/haproxy.cfg"

mkdir -p "$HAPROXY_DIR"
cp /certs/ca/ca.crt "${HAPROXY_DIR}/ca.crt"

if [ -f "$HAPROXY_CERT" ] && openssl x509 -checkend "$RENEW_SECONDS" -noout -in "$HAPROXY_CERT" >/dev/null 2>&1; then
  echo "Сертификат для HAProxy (${HAPROXY_DOMAIN}) еще действителен. Пропускаем."
else
  echo "Выпуск сертификата для HAProxy (${HAPROXY_DOMAIN}) на 365 дней..."
  openssl genrsa -out "$HAPROXY_KEY" 2048

  cat << EOT > "${HAPROXY_DIR}/vault.ext"
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${HAPROXY_DOMAIN}
DNS.2 = vault-haproxy
DNS.3 = localhost
IP.1 = ${HOST_IP}
IP.2 = 127.0.0.1
EOT

  openssl req -new -key "$HAPROXY_KEY" -out "${HAPROXY_DIR}/vault.csr" \
    -subj "/C=RU/ST=Local/L=Lab/O=VaultCluster/CN=${HAPROXY_DOMAIN}"

  openssl x509 -req -in "${HAPROXY_DIR}/vault.csr" -CA /certs/ca/ca.crt -CAkey /certs/ca/ca.key -CAcreateserial \
    -out "$HAPROXY_CERT" -days 365 -sha256 -extfile "${HAPROXY_DIR}/vault.ext"

  # HAProxy требует объединенный файл (сертификат + приватный ключ)
  cat "$HAPROXY_CERT" "$HAPROXY_KEY" > "$HAPROXY_PEM"

  rm -f "${HAPROXY_DIR}/vault.csr" "${HAPROXY_DIR}/vault.ext"
  chmod 644 "$HAPROXY_CERT" "$HAPROXY_KEY" "$HAPROXY_PEM" "${HAPROXY_DIR}/ca.crt"
fi

echo "Все конфиги и сертификаты для IP ${HOST_IP} готовы!"
