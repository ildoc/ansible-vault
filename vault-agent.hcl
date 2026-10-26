exit_after_auth = true
pid_file = "/tmp/vault-agent.pid"

auto_auth {
  method "approle" {
    config = {
      role_id_file_path                   = "/app/role_id"
      secret_id_file_path                 = "/app/secret_id"
      remove_secret_id_file_after_reading = false
    }
  }

  sink "file" {
    config = {
      path = "/tmp/vault-token"
    }
  }
}

# Address comes from VAULT_ADDR or `vault agent -address`.
# A ${VAULT_ADDR} string in this file is not expanded.

template {
  destination = "/tmp/vault-agent-dummy.txt"
  contents    = "noop"
}
