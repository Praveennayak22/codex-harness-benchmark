FROM node:22-bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends git ca-certificates && \
    rm -rf /var/lib/apt/lists/*

RUN npm install -g @openai/codex

RUN mkdir -p /workspace && chown node:node /workspace

USER node

WORKDIR /workspace

CMD ["codex", "--version"]
