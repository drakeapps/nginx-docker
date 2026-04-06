# Accept the version as a build argument (defaults to 'latest' if not provided)
ARG NGINX_VERSION=latest

FROM nginx:${NGINX_VERSION}-alpine

RUN rm -rf /usr/share/nginx/html/*

COPY cloudflare.conf /etc/nginx/conf.d/00-cloudflare.conf
COPY nginx.conf /etc/nginx/conf.d/default.conf
