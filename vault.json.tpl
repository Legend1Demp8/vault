{
  "cluster_name": "vault-production",
  "ui": true,
  "disable_mlock": true,
  "plugin_directory": "/vault/plugins",
  "plugin_tmpdir": "/vault/plugins/tmp",
  "storage": {
    "raft": {
      "path": "/vault/data",
      "node_id": "node__NODE_NUM__",
      "retry_join": [
        {
          "leader_api_addr": "https://vault__PEER_1__.__HOST_IP__.nip.io:8200",
          "leader_ca_cert_file": "/vault/certs/ca.crt",
          "leader_client_cert_file": "/vault/certs/vault.crt",
          "leader_client_key_file": "/vault/certs/vault.key"
        },
        {
          "leader_api_addr": "https://vault__PEER_2__.__HOST_IP__.nip.io:8200",
          "leader_ca_cert_file": "/vault/certs/ca.crt",
          "leader_client_cert_file": "/vault/certs/vault.crt",
          "leader_client_key_file": "/vault/certs/vault.key"
        }
      ]
    }
  },
  "listener": [
    {
      "tcp": {
        "address": "0.0.0.0:8200",
        "tls_cert_file": "/vault/certs/vault.crt",
        "tls_key_file": "/vault/certs/vault.key",
        "tls_client_ca_file": "/vault/certs/ca.crt"
      }
    }
  ],
  "api_addr": "https://vault__NODE_NUM__.__HOST_IP__.nip.io:8200",
  "cluster_addr": "https://vault__NODE_NUM__.__HOST_IP__.nip.io:8201"
}
