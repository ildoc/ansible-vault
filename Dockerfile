FROM python:3.13.3-slim

RUN curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(. /etc/os-release && echo "$VERSION_CODENAME") main" > /etc/apt/sources.list.d/hashicorp.list \
    && curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg \
    && echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list \
    && apt-get update \
    && apt-get install -y \
    curl \
    unzip \
    gnupg \
    openssh-client \
    sshpass \
    apt-transport-https \
    ca-certificates \
    vault \
    kubectl \
    && apt-get clean

# Installa Ansible
RUN pip install --no-cache-dir \
    ansible \
    hvac \
    netaddr \
    kubernetes \
    openshift \
    && ansible-galaxy collection install \
    kubernetes.core \
    community.hashi_vault

# Crea directory e copia entrypoint
WORKDIR /app
COPY entrypoint.sh vault-agent.hcl ./

ENTRYPOINT ["bash", "entrypoint.sh"]
