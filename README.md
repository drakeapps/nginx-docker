# Base nginx Docker image for Drake Apps

This is a base nginx docker image used for nearly all of my nginx deployments.

## Differences between this and base nginx:alpine

1. Redirects not found URLs back to the index
2. Increase cache lifetime of static assets
3. Blocks hidden / dot files
4. Resolves real client IP from Cloudflare's `CF-Connecting-IP` header
5. Logs the requested hostname (`$host`) in the access log for multi-site visibility

## Cloudflare logging

The main `nginx.conf` is configured at the `http` level with:

- All current Cloudflare IP ranges as trusted proxies via `set_real_ip_from`
- `real_ip_header CF-Connecting-IP` so `$remote_addr` reflects the actual client IP
- A `cloudflare` log format that appends the requested `$host` to each log line

Since these are set at the `http` level, all server blocks in `/etc/nginx/conf.d/` inherit them automatically — including any custom configs you bring in.

## Custom server config

If you need a different server configuration for a specific service (e.g. reverse proxy, custom routing), you can replace the default server block by copying your own config into the image:

```Dockerfile
FROM ghcr.io/drakeapps/nginx:latest

COPY my-custom-site.conf /etc/nginx/conf.d/default.conf
COPY --from=build /build/dist /usr/share/nginx/html/
```

The Cloudflare real IP resolution and hostname logging will still apply since they are defined in the main `nginx.conf` at the `http` level. Your custom config only needs to define the `server` block.

Example `my-custom-site.conf` for a reverse proxy:

```nginx
server {
    listen 80;
    server_name api.example.com;

    location / {
        proxy_pass http://backend:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

> **Note:** If your custom server block sets its own `access_log` directive, it will override the inherited `cloudflare` format for that block.

## Example usage

### Simple copy all and `npm build`

```Dockerfile
FROM node:24-slim AS build

WORKDIR /build

COPY . .

RUN npm run build

FROM ghcr.io/drakeapps/nginx:latest

COPY --from=build /build/dist /usr/share/nginx/html/
```

### A more extended `pnpm` version that is used in production

```Dockerfile
FROM --platform=$BUILDPLATFORM node:24-slim AS base
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable
WORKDIR /build

FROM base AS deps
COPY package.json pnpm-lock.yaml tsconfig.json tsconfig.node.json ./
COPY font-awesome/ ./font-awesome/ 
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install --frozen-lockfile

FROM base AS build

COPY --from=deps /build/node_modules ./node_modules

COPY package.json pnpm-lock.yaml tsconfig.json tsconfig.node.json ./

COPY index.html index.tsx index.scss ./
COPY shared/ shared/
COPY static/ static/
COPY components/ components/
COPY src/ src/
COPY types/ types/

RUN pnpm run build

FROM ghcr.io/drakeapps/nginx:latest
COPY --from=build /build/dist /usr/share/nginx/html/
```
