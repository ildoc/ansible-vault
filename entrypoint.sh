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

  echo "[+] Authenticating via OIDC (open the URL in your browser)..."
  echo "[+] Ensure port 8250 is published: -p 8250:8250"
  local oidc_args=(-method=oidc)
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
