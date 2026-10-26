# ansible-vault

Container image to run Ansible playbooks with HashiCorp Vault authentication
(OIDC via Authentik, temporary token, or AppRole) and kubectl available.

Default Vault address: `https://vault.local.ildoc.it` (override with `VAULT_ADDR`).

No secrets are baked into the image. Auth happens at runtime only.

## Auth priority

1. `VAULT_TOKEN` — use a short-lived token (e.g. after host-side OIDC login)
2. AppRole — if both `VAULT_ROLE_ID` and `VAULT_SECRET_ID` are set
3. OIDC — interactive browser login (callback on `localhost:8250`)

## OIDC on a remote server (browser on another PC)

Vault CLI listens for the OIDC callback on `http://localhost:8250`. If Docker
runs on a server and the browser is on your laptop, `localhost` is the laptop —
the callback never reaches the container unless you tunnel the port.

On the laptop:

```bash
ssh -L 8250:127.0.0.1:8250 user@ubuntu-server
```

On the server (keep the tunnel open):

```bash
docker run --rm -it \
  -p 127.0.0.1:8250:8250 \
  -v "$(pwd)":/app/playbooks \
  -v ~/.kube:/root/.kube \
  registry.gitlab.local.ildoc.it/devops/ansible-vault:latest \
  mioplaybook.yml --ask-pass --ask-become-pass
```

Open the printed Authentik URL in the laptop browser. After login, the redirect
to `localhost:8250` goes through the SSH tunnel into the container.

Optional role (Vault default is `dynamic`):

```bash
-e VAULT_OIDC_ROLE=admin
```

## Temporary token (no port 8250)

Best when you already have Vault CLI on a machine with a browser (or after a
one-shot OIDC login elsewhere):

```bash
export VAULT_ADDR=https://vault.local.ildoc.it
vault login -method=oidc
# copy the token, then on the server:
docker run --rm -it \
  -e VAULT_TOKEN \
  -v "$(pwd)":/app/playbooks \
  -v ~/.kube:/root/.kube \
  registry.gitlab.local.ildoc.it/devops/ansible-vault:latest \
  mioplaybook.yml --ask-pass --ask-become-pass
```

## AppRole (automation / CI)

`VAULT_ADDR` is optional; the default is `https://vault.local.ildoc.it`.
Omitting the image tag selects `:latest`.

```bash
docker run --rm -it \
  -e VAULT_ROLE_ID=<role_id> \
  -e VAULT_SECRET_ID=<secret_id> \
  -e VAULT_ADDR=https://vault.local.ildoc.it \
  -v "$(pwd)":/app/playbooks \
  -v ~/.kube:/root/.kube \
  registry.gitlab.local.ildoc.it/devops/ansible-vault \
  mioplaybook.yml --ask-pass --ask-become-pass
```

## SSH keys

The image includes `openssh-client` and `sshpass` and runs as root, so
`--ask-pass` / `--ask-become-pass` need `-it`.

To use your keys instead of `--ask-pass`, mount `~/.ssh` on `/root/.ssh`.
OpenSSH rejects a config owned by the host user, so the entrypoint copies
that directory into a private home (mode `0700`/`0600`) and uses it for SSH.
`kubectl` keeps using `/root/.kube/config`.

```bash
docker run --rm -it \
  -e VAULT_ROLE_ID=<role_id> \
  -e VAULT_SECRET_ID=<secret_id> \
  -e VAULT_ADDR=https://vault.local.ildoc.it \
  -v "$(pwd)":/app/playbooks \
  -v ~/.kube:/root/.kube \
  -v ~/.ssh:/root/.ssh:ro \
  registry.gitlab.local.ildoc.it/devops/ansible-vault \
  mioplaybook.yml --ask-become-pass
```

`:ro` is enough. If the mount is read-write and `known_hosts` already exists,
newly learned host keys are written back without changing the file owner.

`IdentityFile` and `Include` paths must live under `~/.ssh`. An absolute host
path such as `/home/you/.ssh/id_ed25519` is not inside the container.

A key with a passphrase is not prompted by Ansible. Forward the agent socket
instead:

```bash
  -v "$SSH_AUTH_SOCK:$SSH_AUTH_SOCK" \
  -e SSH_AUTH_SOCK \
```

## Debug

```bash
-e DEBUG=true
```
