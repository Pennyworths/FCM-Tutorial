FROM amazonlinux:2

SHELL ["/bin/bash", "-eo", "pipefail", "-c"]

# System packages
RUN yum update -y && yum install -y \
    postgresql \
    jq \
    curl \
    unzip \
    tar \
    bash \
    python3 \
    python3-pip \
    git \
 && yum clean all

# Detect architecture once (x86_64 or aarch64)
ARG TARGETARCH
RUN case "${TARGETARCH:-$(uname -m)}" in \
      x86_64|amd64)  echo x86_64  > /arch ;; \
      aarch64|arm64) echo aarch64 > /arch ;; \
      *) echo "Unsupported arch: ${TARGETARCH:-$(uname -m)}" && exit 1 ;; \
    esac

# AWS CLI v2 (right arch)
RUN ARCH="$(cat /arch)" \
 && curl -L "https://awscli.amazonaws.com/awscli-exe-linux-${ARCH}.zip" -o awscliv2.zip \
 && unzip -q awscliv2.zip \
 && ./aws/install \
 && rm -rf aws awscliv2.zip

# Go migrate (right arch)
RUN ARCH="$(cat /arch)" \
 && if [ "$ARCH" = "x86_64" ]; then \
      URL="https://github.com/golang-migrate/migrate/releases/download/v4.16.2/migrate.linux-amd64.tar.gz"; \
    else \
      URL="https://github.com/golang-migrate/migrate/releases/download/v4.16.2/migrate.linux-arm64.tar.gz"; \
    fi \
 && curl -L "$URL" -o /tmp/migrate.tgz \
 && tar -xzf /tmp/migrate.tgz -C /usr/local/bin migrate \
 && chmod +x /usr/local/bin/migrate \
 && rm -f /tmp/migrate.tgz

# SSM plugin (right arch, rpm)
RUN ARCH="$(cat /arch)" \
 && if [ "$ARCH" = "x86_64" ]; then \
      URL="https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm"; \
    else \
      URL="https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_arm64/session-manager-plugin.rpm"; \
    fi \
 && curl -L "$URL" -o /tmp/session-manager-plugin.rpm \
 && yum install -y /tmp/session-manager-plugin.rpm \
 && rm -f /tmp/session-manager-plugin.rpm

# Python deps
RUN pip3 install --no-cache-dir boto3 psycopg2-binary click tabulate

WORKDIR /migrations
COPY scripts/ ./scripts/
COPY migrate/ ./migrate/

RUN chmod +x ./scripts/*.sh

# No ENTRYPOINT; allow `docker compose run svc <cmd>`
CMD ["/bin/bash"]

