FROM ghcr.io/runatlantis/atlantis:latest

# Install essential tools
RUN apk add --no-cache curl jq yq bash aws-cli python3 py3-pip findutils grep

# Install Atmos with specific version for consistency
ARG ATMOS_VERSION=1.44.0
RUN curl -L -o /tmp/atmos.tar.gz https://github.com/cloudposse/atmos/releases/download/v${ATMOS_VERSION}/atmos_linux_amd64.tar.gz && \
    tar -xf /tmp/atmos.tar.gz -C /tmp && \
    mv /tmp/atmos /usr/local/bin/atmos && \
    chmod +x /usr/local/bin/atmos && \
    rm -f /tmp/atmos.tar.gz

# Verify installation and show version
RUN atmos --version

# Install additional tools for YAML parsing and JSON handling
RUN pip3 install --no-cache-dir yamllint cfn-lint

# Create directories for plan caching and logs
RUN mkdir -p /atlantis/plans /atlantis/logs && \
    chmod -R 777 /atlantis/plans /atlantis/logs

# Set up AWS credentials directory
RUN mkdir -p /root/.aws

# Install helper scripts for AWS cross-account access
COPY scripts/assume-role.sh /usr/local/bin/assume-role
RUN chmod +x /usr/local/bin/assume-role

# Add custom server-side repo config
COPY atlantis.yaml /atlantis-repo-config.yaml

# Add custom error handling and logging wrapper
COPY scripts/atmos-wrapper.sh /usr/local/bin/atmos-wrapper
RUN chmod +x /usr/local/bin/atmos-wrapper

# Create health check endpoint
RUN echo '#!/bin/sh\necho "Atlantis Atmos Server: OK"' > /usr/local/bin/healthcheck && \
    chmod +x /usr/local/bin/healthcheck

# Set working directory
WORKDIR /atlantis

# Set up environment variables
ENV PATH="/usr/local/bin:${PATH}" \
    ATLANTIS_LOG_LEVEL=debug \
    ATMOS_DEBUG=true

# Expose ports for Atlantis server and metrics
EXPOSE 4141 4142

# Set up Docker health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 CMD [ "healthcheck" ]

# Set up entrypoint with more verbose logging
ENTRYPOINT ["atlantis", "server", "--repo-config=/atlantis-repo-config.yaml", "--log-level=debug"]

# Default command arguments with better security practices
CMD ["--gh-user=atlantis", \
     "--gh-token=${GITHUB_TOKEN}", \
     "--gh-webhook-secret=${GITHUB_WEBHOOK_SECRET}", \
     "--repo-allowlist=${REPO_ALLOWLIST}", \
     "--write-git-creds=true", \
     "--port=4141", \
     "--disable-apply-all=true", \
     "--silence-whitelist-errors=true", \
     "--enable-diff-markdown-format=true"]