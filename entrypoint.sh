#!/bin/bash
set -e

# Scrive i valori delle variabili passate via ENV in file
echo "$VAULT_ROLE_ID" > /app/role_id
echo "$VAULT_SECRET_ID" > /app/secret_id

# Avvia Vault Agent in background
vault agent -config=/app/vault-agent.hcl &
echo "⏳ Avvio Vault Agent..."
while [ ! -f /tmp/vault-token ]; do sleep 0.5; done
export VAULT_TOKEN=$(cat /tmp/vault-token)

echo "✅ Vault Agent autenticato. Avvio playbook..."
ansible-playbook "$@"
