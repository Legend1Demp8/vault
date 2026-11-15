# ---------------------------------------------------------------------------
# ОБЩИЕ НАСТРОЙКИ УЗЛА HASHICORP VAULT
# ---------------------------------------------------------------------------
cluster_name = "vault-production"
ui = true
disable_mlock = true

# ---------------------------------------------------------------------------
# НАСТРОЙКИ ВСТРОЕННОГО ХРАНИЛИЩА (INTEGRATED STORAGE / RAFT)
# ---------------------------------------------------------------------------
storage "raft" {
  path    = "/vault/data"
  node_id = "node__NODE_NUM__"

  # Блоки автоматического поиска и присоединения к соседним нодам кластера
  # --- Сосед 1 ---
  retry_join {
    leader_api_addr         = "https://vault__PEER_1__.__HOST_IP__.nip.io:8200"
    leader_ca_cert_file     = "/vault/certs/ca.crt"
    leader_client_cert_file = "/vault/certs/vault.crt"
    leader_client_key_file  = "/vault/certs/vault.key"
  }

  # --- Сосед 2 ---
  retry_join {
    leader_api_addr         = "https://vault__PEER_2__.__HOST_IP__.nip.io:8200"
    leader_ca_cert_file     = "/vault/certs/ca.crt"
    leader_client_cert_file = "/vault/certs/vault.crt"
    leader_client_key_file  = "/vault/certs/vault.key"
  }
}

# ---------------------------------------------------------------------------
# СЕТЕВОЙ ИНТЕРФЕЙС (LISTENER): ПРИЕМ ВХОДЯЩИХ ЗАПРОСОВ API И UI
# ---------------------------------------------------------------------------
listener "tcp" {
  address            = "0.0.0.0:8200"
  tls_cert_file      = "/vault/certs/vault.crt"
  tls_key_file       = "/vault/certs/vault.key"
  tls_client_ca_file = "/vault/certs/ca.crt"
}

# ---------------------------------------------------------------------------
# СЕТЕВЫЕ АДРЕСА ДЛЯ КЛАСТЕРНОГО ВЗАИМОДЕЙСТВИЯ
# ---------------------------------------------------------------------------
api_addr     = "https://vault__NODE_NUM__.__HOST_IP__.nip.io:8200"
cluster_addr = "https://vault__NODE_NUM__.__HOST_IP__.nip.io:8201"
