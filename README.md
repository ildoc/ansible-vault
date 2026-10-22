# ansible-vault

Container image to run Ansible playbooks with HashiCorp Vault authentication
(OIDC via Authentik, temporary token, or AppRole) and kubectl available.

Default Vault address: `https://vault.local.ildoc.it` (override with `VAULT_ADDR`).

No secrets are baked into the image. Auth happens at runtime only.

## Auth priority

1. `VAULT_TOKEN` — use a short-lived token (e.g. after host-side OIDC login)
2. AppRole — if both `VAULT_ROLE_ID` and `VAULT_SECRET_ID` are set
3. OIDC — interactive browser login (default for local use)

## OIDC (interactive)

Requires `-it` and publishing the Vault CLI callback port (`8250`), already
allowed on the Vault OIDC role (`http://localhost:8250/oidc/callback`).

```bash
docker run --rm -it \
  -p 8250:8250 \
  -v "$(pwd)":/app/playbooks \
  -v ~/.kube:/root/.kube \
  registry.gitlab.local.ildoc.it/devops/ansible-vault:latest \
  mioplaybook.yml --ask-pass --ask-become-pass
```

Optional role (Vault default is `dynamic`):

```bash
-e VAULT_OIDC_ROLE=admin
```

## Temporary token

Log in on the host first, then pass the token into the container (no port 8250):

```bash
export VAULT_ADDR=https://vault.local.ildoc.it
vault login -method=oidc

docker run --rm -it \
  -e VAULT_TOKEN \
  -v "$(pwd)":/app/playbooks \
  -v ~/.kube:/root/.kube \
  registry.gitlab.local.ildoc.it/devops/ansible-vault:latest \
  mioplaybook.yml --ask-pass --ask-become-pass
```

## AppRole (automation / CI)

```bash
docker run --rm -it \
  -e VAULT_ROLE_ID=<role_id> \
  -e VAULT_SECRET_ID=<secret_id> \
  -v "$(pwd)":/app/playbooks \
  -v ~/.kube:/root/.kube \
  registry.gitlab.local.ildoc.it/devops/ansible-vault:latest \
  mioplaybook.yml --ask-pass --ask-become-pass
```

## Debug

```bash
-e DEBUG=true
```
