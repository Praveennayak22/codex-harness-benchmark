# Frozen Node image digest used in the original November 2026 experiments.
# If building for a different architecture, choose and document its digest.
FROM node:22-bookworm-slim@sha256:4b150b48b4116e2a22f2c39cc27025fbf4f153e2078fd3b14d159fdb5c7279da

RUN apt-get update && \
    apt-get install -y --no-install-recommends git ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Original experimental CLI version, rather than the moving npm 'latest'.
RUN npm install -g @openai/codex@0.166.0 && codex --version

RUN mkdir -p /workspace && chown node:node /workspace
USER node
WORKDIR /workspace
CMD ["codex", "--version"]
