# This dockerfile builds an image for the backend package.
# It should be executed with the root of the repo as docker context.
#
# Before building this image, be sure to have run the following commands in the repo root:
#
# yarn install
# yarn tsc
# yarn build:backend
#
# Once the commands have been run, you can build the image using `yarn build-image`

FROM node:18-bookworm-slim

# Install isolate-vm dependencies, these are needed by the @backstage/plugin-scaffolder-backend.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends python3 g++ build-essential && \
    yarn config set python /usr/bin/python3

# Install additional tools needed for Atmos integration
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get install -y --no-install-recommends \
    curl \
    git \
    openssh-client \
    ca-certificates \
    gnupg \
    && rm -rf /var/lib/apt/lists/*

# Install Terraform
ARG TERRAFORM_VERSION=1.6.0
RUN curl -fsSL https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip -o terraform.zip \
    && unzip terraform.zip \
    && mv terraform /usr/local/bin/ \
    && rm terraform.zip \
    && terraform version

# Install Atmos
ARG ATMOS_VERSION=1.48.0
RUN curl -fsSL https://github.com/cloudposse/atmos/releases/download/v${ATMOS_VERSION}/atmos_${ATMOS_VERSION}_linux_amd64.tar.gz -o atmos.tar.gz \
    && tar -xzf atmos.tar.gz \
    && mv atmos /usr/local/bin/ \
    && rm atmos.tar.gz \
    && atmos version

# Install kubectl for Kubernetes integration
ARG KUBECTL_VERSION=v1.28.0
RUN curl -fsSL https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl -o kubectl \
    && chmod +x kubectl \
    && mv kubectl /usr/local/bin/ \
    && kubectl version --client

# Install AWS CLI for cloud integration
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf awscliv2.zip aws \
    && aws --version

# Install Python for platform API integration
RUN apt-get update && apt-get install -y python3-pip \
    && pip3 install --no-cache-dir \
    requests \
    pyyaml \
    jinja2 \
    && rm -rf /var/lib/apt/lists/*

# From here on we use the least-privileged `node` user to run the backend.
USER node

# This should create the app dir as `node`.
# If it is instead created as `root` then the `tar` command below will fail: `can't create directory 'packages/': Permission denied`.
# If this occurs, then ensure BuildKit is enabled (`DOCKER_BUILDKIT=1`) so the app dir is correctly created as `node`.
WORKDIR /app

# This switches many Node.js dependencies to production mode.
ENV NODE_ENV production

# Copy repo skeleton first, to avoid unnecessary docker cache invalidation.
# The skeleton contains the package.json of each package in the monorepo,
# and along with yarn.lock and the root package.json, that's enough to run yarn install.
COPY --chown=node:node yarn.lock package.json packages/*/package.json ./
COPY --chown=node:node packages/*/package.json packages/*/
COPY --chown=node:node plugins/*/package.json plugins/*/

RUN --mount=type=cache,target=/home/node/.cache/yarn,sharing=locked,uid=1000,gid=1000 \
    yarn install --frozen-lockfile --production --network-timeout 300000

# Then copy the rest of the backend bundle, along with any other files we might want.
COPY --chown=node:node packages packages
COPY --chown=node:node plugins plugins

# Copy the app configuration and other necessary files
COPY --chown=node:node app-config*.yaml ./

# Create directory for Atmos configuration
RUN mkdir -p /app/atmos
COPY --chown=node:node atmos.yaml /app/atmos/

# Set up environment
ENV ATMOS_CLI_CONFIG_PATH=/app/atmos/atmos.yaml
ENV PATH="/app/node_modules/.bin:$PATH"

# Switch back to pass the image security checks
USER root
RUN chown -R node:node /app
USER node

WORKDIR /app

CMD ["node", "packages/backend", "--config", "app-config.yaml", "--config", "app-config.production.yaml"]