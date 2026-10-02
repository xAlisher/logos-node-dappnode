# Web UI service for the Logos node package — a faithful web replica of the
# official node app (xAlisher/logos-node-webui). Pinned to a commit so the
# package build is reproducible; bump WEBUI_REF when shipping a new UI.
#
# Builds the Vite/React bundle, then serves it with nginx and reverse-proxies
# /api to the node service on the package's internal docker network (node:8080).

FROM node:22-alpine AS build
ARG WEBUI_REF=88e316f34f3e03080326f8e9ad293d47604c6d7d
RUN apk add --no-cache git
WORKDIR /app
RUN git clone https://github.com/xAlisher/logos-node-webui.git . \
    && git checkout "$WEBUI_REF" \
    && npm ci \
    && npm run build

FROM nginx:1.27-alpine
# Node HTTP API reachable by service name on the package network.
ENV NODE_UPSTREAM=node:8080
COPY --from=build /app/dist /usr/share/nginx/html
COPY --from=build /app/nginx.conf.template /etc/nginx/templates/default.conf.template
EXPOSE 80
