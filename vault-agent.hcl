pid_file = "/tmp/vault-agent.pid"
auto_auth {
  method "approle" {
    config = {
      role_id_file_path   = "/app/role_id"
      secret_id_file_path = "/app/secret_id"
    }
  }
  sink "file" {
    config = {
      path = "/tmp/vault-token"
    }
  }
}
vault {
  address = "${VAULT_ADDR}"
}
cache {
  use_auto_auth_token = true
}
