#!/bin/bash
set -euo pipefail

export VAULT_ADDR="${VAULT_ADDR:-https://vault.local.ildoc.it}"

APPROLE_ROLE_FILE=/app/role_id
APPROLE_SECRET_FILE=/app/secret_id
SSH_MOUNT=""
SSH_HOME=""

cleanup_approle_files() {
  rm -f "$APPROLE_ROLE_FILE" "$APPROLE_SECRET_FILE"
}

restore_known_hosts() {
  [ -n "$SSH_MOUNT" ] && [ -n "$SSH_HOME" ] || return 0
  local src="$SSH_MOUNT/known_hosts"
  local dst="$SSH_HOME/.ssh/known_hosts"
  if [ -f "$src" ] && [ -f "$dst" ] && [ -w "$src" ] && ! cmp -s "$src" "$dst"; then
    cat "$dst" > "$src" || true
  fi
}

on_exit() {
  cleanup_approle_files
  restore_known_hosts
}
trap on_exit EXIT

# OpenSSH accepts a user config owned by root or the current uid, and rejects
# group/world-writable files. A bind mount of the host ~/.ssh fails that check.
ssh_needs_private_copy() {
  local path=$1
  local uid=$2
  [ -e "$path" ] || return 1
  local owner mode
  owner=$(stat -c '%u' "$path")
  mode=$(stat -c '%a' "$path")
  if [ "$owner" != "0" ] && [ "$owner" != "$uid" ]; then
    return 0
  fi
  if [ $((8#$mode & 022)) -ne 0 ]; then
    return 0
  fi
  return 1
}

prepare_ssh() {
  local src="${HOME}/.ssh"
  [ -d "$src" ] || return 0

  local uid
  uid=$(id -u)

  local needs_copy=0 path
  if ssh_needs_private_copy "$src" "$uid"; then
    needs_copy=1
  else
    while IFS= read -r -d '' path; do
      if ssh_needs_private_copy "$path" "$uid"; then
        needs_copy=1
        break
      fi
    done < <(find "$src" -mindepth 1 -print0)
  fi
  [ "$needs_copy" -eq 1 ] || return 0

  local dest_home rel parent
  dest_home=$(mktemp -d /tmp/ansible-home.XXXXXX)
  mkdir -p "$dest_home/.ssh"

  while IFS= read -r -d '' path; do
    rel="${path#"$src"/}"
    if [ -d "$path" ] && [ ! -L "$path" ]; then
      mkdir -p "$dest_home/.ssh/$rel"
    elif [ -S "$path" ]; then
      continue
    elif [ -f "$path" ] || [ -L "$path" ]; then
      parent=$(dirname -- "$rel")
      mkdir -p "$dest_home/.ssh/$parent"
      if [ -L "$path" ]; then
        cp -L -- "$path" "$dest_home/.ssh/$rel" 2>/dev/null || cp -a -- "$path" "$dest_home/.ssh/$rel"
      else
        cp -a -- "$path" "$dest_home/.ssh/$rel"
      fi
    fi
  done < <(find "$src" -mindepth 1 -print0)

  chown -R "$uid:$(id -g)" "$dest_home"
  chmod 700 "$dest_home" "$dest_home/.ssh"
  find "$dest_home/.ssh" -type d -exec chmod 700 {} +
  find "$dest_home/.ssh" -type f -exec chmod 600 {} +

  # OpenSSH reads pw_dir from /etc/passwd, not $HOME.
  if ! set_login_home "$dest_home"; then
    echo "[!] Could not point the container user home at ${dest_home}" >&2
    exit 1
  fi

  if [ -z "${KUBECONFIG:-}" ] && [ -f /root/.kube/config ]; then
    export KUBECONFIG=/root/.kube/config
  fi

  SSH_MOUNT=$src
  SSH_HOME=$dest_home
  export HOME="$dest_home"
  echo "[+] Copied ${src} to ${dest_home}/.ssh so OpenSSH accepts the mounted keys"
}

set_login_home() {
  local dest=$1
  local user tmp name found=0 line
  local f1 f2 f3 f4 f5 f6 f7
  user=$(id -un)
  tmp=$(mktemp)
  found=0
  while IFS= read -r line || [ -n "$line" ]; do
    name=${line%%:*}
    if [ "$name" = "$user" ]; then
      IFS=: read -r f1 f2 f3 f4 f5 f6 f7 <<< "$line"
      printf '%s:%s:%s:%s:%s:%s:%s\n' "$f1" "$f2" "$f3" "$f4" "$f5" "$dest" "$f7"
      found=1
    else
      printf '%s\n' "$line"
    fi
  done < /etc/passwd > "$tmp"
  local old_lines new_lines
  old_lines=$(wc -l < /etc/passwd)
  new_lines=$(wc -l < "$tmp")
  if [ "$found" -ne 1 ] || [ "$old_lines" != "$new_lines" ]; then
    rm -f "$tmp"
    return 1
  fi
  cat "$tmp" > /etc/passwd
  rm -f "$tmp"
}

wait_for_vault_token() {
  local agent_pid=$1
  local _
  for _ in $(seq 1 60); do
    if [ -s /tmp/vault-token ]; then
      return 0
    fi
    if ! kill -0 "$agent_pid" 2>/dev/null; then
      if [ -s /tmp/vault-token ]; then
        return 0
      fi
      echo "[!] Vault Agent exited before writing a token" >&2
      wait "$agent_pid" || true
      exit 1
    fi
    sleep 0.5
  done

  echo "[!] Timed out waiting for a Vault token from AppRole" >&2
  kill "$agent_pid" 2>/dev/null || true
  wait "$agent_pid" 2>/dev/null || true
  exit 1
}

authenticate_vault() {
  if [ -n "${VAULT_TOKEN:-}" ]; then
    echo "[+] Using provided VAULT_TOKEN"
    return
  fi

  if [ -n "${VAULT_ROLE_ID:-}" ] && [ -n "${VAULT_SECRET_ID:-}" ]; then
    echo "[+] Authenticating via AppRole (Vault Agent)..."
    umask 077
    printf '%s\n' "$VAULT_ROLE_ID" > "$APPROLE_ROLE_FILE"
    printf '%s\n' "$VAULT_SECRET_ID" > "$APPROLE_SECRET_FILE"

    vault agent -config=/app/vault-agent.hcl -address="$VAULT_ADDR" &
    local agent_pid=$!
    wait_for_vault_token "$agent_pid"

    if kill -0 "$agent_pid" 2>/dev/null; then
      kill "$agent_pid" 2>/dev/null || true
    fi
    wait "$agent_pid" 2>/dev/null || true

    VAULT_TOKEN=$(tr -d '[:space:]' < /tmp/vault-token)
    if [ -z "$VAULT_TOKEN" ]; then
      echo "[!] Vault Agent wrote an empty token" >&2
      exit 1
    fi
    export VAULT_TOKEN
    rm -f /tmp/vault-token
    cleanup_approle_files
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
  VAULT_TOKEN=$(vault print token)
  export VAULT_TOKEN
  echo "[+] OIDC authentication succeeded"
}

authenticate_vault
prepare_ssh

echo "[+] Starting playbook..."

mkdir -p /app/playbooks

if [ "${DEBUG:-}" = "true" ]; then
  echo "[DEBUG] ls -la /app/playbooks:"
  ls -la /app/playbooks
  echo "[DEBUG] HOME=${HOME}"
  if [ -n "${KUBECONFIG:-}" ]; then
    echo "[DEBUG] KUBECONFIG=${KUBECONFIG}"
  fi
fi

cd /app/playbooks
ansible-playbook "$@"
