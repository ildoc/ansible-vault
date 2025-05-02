#!/bin/bash
set -e

# Imposta valore di default per VAULT_ADDR se non definito
if [ -z "$VAULT_ADDR" ]; then
  export VAULT_ADDR="http://vault:8200"
fi

# Scrive i valori delle variabili passate via ENV in file
echo "$VAULT_ROLE_ID" > /app/role_id
echo "$VAULT_SECRET_ID" > /app/secret_id

# Avvia Vault Agent in background
vault agent -config=/app/vault-agent.hcl &
echo "⏳ Avvio Vault Agent..."
while [ ! -f /tmp/vault-token ]; do sleep 0.5; done
export VAULT_TOKEN=$(cat /tmp/vault-token)

echo "✅ Vault Agent autenticato. Avvio playbook..."

if [ "${DEBUG}" = "true" ]; then
    echo "DEBUG è attivo. Eseguendo ls -la su /app/playbooks..."
    ls -la /app/playbooks
fi

cd /app/playbooks
ansible-playbook "$@"
