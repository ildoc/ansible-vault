#!/bin/bash
set -e

if [ -z "$VAULT_ADDR" ]; then
  export VAULT_ADDR="http://vault:8200"
fi

echo "$VAULT_ROLE_ID" > /app/role_id
echo "$VAULT_SECRET_ID" > /app/secret_id

vault agent -config=/app/vault-agent.hcl &
echo "[+] Starting Vault Agent..."
while [ ! -f /tmp/vault-token ]; do sleep 0.5; done
export VAULT_TOKEN=$(cat /tmp/vault-token)

echo "[+] Vault Agent authenticated. Starting playbook..."

mkdir -p /app/playbooks

if [ "${DEBUG}" = "true" ]; then
    echo "[DEBUG] ls -la /app/playbooks:"
    ls -la /app/playbooks
fi

cd /app/playbooks
ansible-playbook "$@"
