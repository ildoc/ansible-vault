#!/bin/bash
set -euo pipefail

export VAULT_ADDR="${VAULT_ADDR:-https://vault.local.ildoc.it}"

cleanup_approle_files() {
  rm -f /app/role_id /app/secret_id
}

authenticate_vault() {
  if [ -n "${VAULT_TOKEN:-}" ]; then
    echo "[+] Using provided VAULT_TOKEN"
    return
  fi

  if [ -n "${VAULT_ROLE_ID:-}" ] && [ -n "${VAULT_SECRET_ID:-}" ]; then
    echo "[+] Authenticating via AppRole (Vault Agent)..."
    umask 077
    printf '%s\n' "$VAULT_ROLE_ID" > /app/role_id
    printf '%s\n' "$VAULT_SECRET_ID" > /app/secret_id
    trap cleanup_approle_files EXIT

    vault agent -config=/app/vault-agent.hcl &
    while [ ! -f /tmp/vault-token ]; do sleep 0.5; done
    export VAULT_TOKEN
    VAULT_TOKEN=$(cat /tmp/vault-token)
    cleanup_approle_files
    trap - EXIT
    echo "[+] Vault Agent authenticated"
    return
  fi

  echo "[+] Authenticating via OIDC..."
  echo "[+] The callback is http://localhost:8250/oidc/callback — that must be THIS machine"
  echo "[+]   (or an SSH tunnel from your laptop: ssh -L 8250:127.0.0.1:8250 user@server)."
  echo "[+] Publish the port with: -p 127.0.0.1:8250:8250"
  echo "[+] Prefer -e VAULT_TOKEN if the browser is on another host without a tunnel."
  local oidc_args=(-method=oidc skip_browser=true)
  if [ -n "${VAULT_OIDC_ROLE:-}" ]; then
    oidc_args+=("role=${VAULT_OIDC_ROLE}")
  fi
  vault login "${oidc_args[@]}"
  export VAULT_TOKEN
  VAULT_TOKEN=$(vault print token)
  echo "[+] OIDC authentication succeeded"
}

authenticate_vault

echo "[+] Starting playbook..."

mkdir -p /app/playbooks

if [ "${DEBUG:-}" = "true" ]; then
  echo "[DEBUG] ls -la /app/playbooks:"
  ls -la /app/playbooks
fi

cd /app/playbooks
ansible-playbook "$@"
