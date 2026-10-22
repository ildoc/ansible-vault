FROM python:3.15.1-slim

# Stable OS packages — invalidate rarely
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl \
        unzip \
        gnupg \
        openssh-client \
        sshpass \
        apt-transport-https \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Third-party apt repos + vault/kubectl — invalidate on repo/version bumps
RUN curl -fsSL https://apt.releases.hashicorp.com/gpg \
        | gpg --dearmor -o /usr/share/keyrings/hashicorp.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(. /etc/os-release && echo "$VERSION_CODENAME") main" \
        > /etc/apt/sources.list.d/hashicorp.list \
    && curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.35/deb/Release.key \
        | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg \
    && echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.35/deb/ /' \
        > /etc/apt/sources.list.d/kubernetes.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        vault \
        kubectl \
    && rm -rf /var/lib/apt/lists/*

# Python deps — invalidate when package list / renovate bumps change
RUN pip install --no-cache-dir \
        ansible \
        hvac \
        netaddr \
        kubernetes \
        openshift

# Ansible collections — separate so pip layer stays cached when only collections change
RUN ansible-galaxy collection install \
        kubernetes.core \
        community.hashi_vault

WORKDIR /app

# App files last — most frequent changes must not bust apt/pip layers
COPY entrypoint.sh vault-agent.hcl ./

ENTRYPOINT ["bash", "entrypoint.sh"]
