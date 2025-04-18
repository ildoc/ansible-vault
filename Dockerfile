FROM python:3.13.3-slim

# Aggiungi vault CLI
RUN apt-get update && apt-get install -y curl unzip gnupg && \
    curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(. /etc/os-release && echo "$VERSION_CODENAME") main" > /etc/apt/sources.list.d/hashicorp.list && \
    apt-get update && apt-get install -y vault && \
    apt-get clean

# Installa Ansible
RUN pip install --no-cache-dir ansible

# Installa Ansible Collection per Vault
RUN ansible-galaxy collection install community.hashi_vault

# Crea directory e copia entrypoint
WORKDIR /app
COPY entrypoint.sh .
COPY vault-agent.hcl .

ENTRYPOINT ["bash", "entrypoint.sh"]
