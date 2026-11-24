# Small todo list (Express + React, SQLite) used by the Argo CD labs.
# Build:  docker build -t xeusnguyen/kubewekend-todo:v1.0.0 --build-arg APP_VERSION=v1.0.0 .
# Change the visible content for a new release with --build-arg APP_MESSAGE="..."

# --- Build stage: production dependencies only (sqlite3 is a native module) ---
FROM node:24-alpine AS deps
WORKDIR /app
COPY package.json yarn.lock ./
RUN yarn install --production --frozen-lockfile --network-timeout 100000 \
    && yarn cache clean

# --- Runtime stage: static code, no nodemon, no dev mode ---
FROM node:24-alpine
ARG APP_VERSION=dev
ARG APP_MESSAGE="Hello from Kubewekend"
ENV NODE_ENV=production \
    APP_VERSION=${APP_VERSION} \
    APP_MESSAGE=${APP_MESSAGE} \
    SQLITE_DB_LOCATION=/data/todo.db
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY package.json ./
COPY src ./src
# The node user owns the data directory; Kubernetes mounts an emptyDir here
RUN mkdir -p /data && chown node:node /data
USER node
EXPOSE 3000
CMD ["node", "src/index.js"]
