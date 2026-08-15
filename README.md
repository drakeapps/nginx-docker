# Base nginx Docker image for Drake Apps

This is a base nginx docker image used for nearly all of my nginx deployments.

## Differences between this and base nginx:alpine

1. Redirects not found URLs back to the index
2. Increase cache lifetime of static assets
3. Blocks hidden / dot files
4. Resolves real client IP from Cloudflare's `CF-Connecting-IP` header
5. Logs the requested hostname (`$host`) in the access log for multi-site visibility
6. Brotli and gzip compression enabled by default, including precompressed assets
7. Optional `CLOUDFLARE_TUNNEL` mode for origins reached through a Cloudflare Tunnel

## Compression

Brotli and gzip are both on by default, configured at the `http` level in `nginx.conf`, so every server block inherits them:

- `brotli on` / `gzip on` at compression level 5, for responses of at least 256 bytes
- Matching type lists covering HTML, CSS, JS, JSON, XML, SVG, WASM, plain text and font files. Already-compressed formats (jpg, png, webp, woff2, ...) are excluded — recompressing them costs CPU and saves nothing
- `Vary: Accept-Encoding` on compressed responses
- `brotli_static on` / `gzip_static on`, so a prebuilt `app.js.br` or `app.js.gz` sitting next to `app.js` is served as-is instead of being compressed on every request. Clients that accept both get the Brotli file

Brotli is not part of the official nginx image, so the `Dockerfile` builds [`google/ngx_brotli`](https://github.com/google/ngx_brotli) as dynamic modules in a builder stage against the same nginx version, then copies the two `.so` files into the final image. libbrotli is linked statically, so nothing extra is installed at runtime. The modules are loaded at the top of `nginx.conf`:

```nginx
load_module modules/ngx_http_brotli_filter_module.so;
load_module modules/ngx_http_brotli_static_module.so;
```

To turn compression off (or tune it) for a specific service, override it in your own server or location block, e.g. `brotli off; gzip off;`.

## Cloudflare logging

The main `nginx.conf` is configured at the `http` level with:

- All current Cloudflare IP ranges as trusted proxies via `set_real_ip_from`
- `real_ip_header CF-Connecting-IP` so `$remote_addr` reflects the actual client IP
- A `cloudflare` log format that appends the requested `$host` to each log line

Since these are set at the `http` level, all server blocks in `/etc/nginx/conf.d/` inherit them automatically — including any custom configs you bring in. The same applies to the compression settings above.

## Behind a Cloudflare Tunnel

The ranges above are Cloudflare's *edge*, which is what connects to the origin when the DNS record is proxied straight through. **Behind a Cloudflare Tunnel it is `cloudflared` that connects to nginx**, from the docker bridge gateway, a sibling container, or loopback — never a Cloudflare address. So `set_real_ip_from` never matches, the realip module never fires, and `$remote_addr` is the tunnel for every single request.

The symptoms are easy to miss until they matter: the access log shows one address (`172.17.0.1`, `192.168.x.1`) for the whole internet, and anything keyed on `$remote_addr` — `limit_req`, `limit_conn`, `geo`, `allow`/`deny` — collapses the entire internet into one bucket. A per-IP rate limit configured that way throttles all of your users together the moment any traffic spike arrives.

Set `CLOUDFLARE_TUNNEL=1` on the container to also trust the local hop:

```yaml
services:
  web:
    image: ghcr.io/drakeapps/nginx:latest
    environment:
      - CLOUDFLARE_TUNNEL=1
```

A startup hook then writes `/etc/nginx/conf.d/00-cloudflare-tunnel-realip.conf` trusting loopback, the RFC1918 ranges and the IPv6 ULA range:

```
127.0.0.1/32  ::1/128  10.0.0.0/8  172.16.0.0/12  192.168.0.0/16  fc00::/7
```

Override the list with `CLOUDFLARE_TUNNEL_TRUSTED` (space- or comma-separated CIDRs) to trust only the network you actually use, e.g. `CLOUDFLARE_TUNNEL_TRUSTED=172.18.0.0/16`. These are *added* to the Cloudflare edge ranges rather than replacing them, so an origin that is reachable both ways keeps working.

> **This is opt-in on purpose.** Trusting a private peer means anything that can reach nginx from one of those ranges can forge `CF-Connecting-IP` and claim to be any client it likes. That is fine when the tunnel is the only route in. It is **not** fine when the container's port is also published to a LAN, or when another reverse proxy on the same host can reach it — there, narrow `CLOUDFLARE_TUNNEL_TRUSTED` to the tunnel's own address, or leave the mode off.

Verify it took effect by checking a log line's first field after a request through the tunnel: it should be the browser's public IP, not a `172.x`/`192.168.x` address.

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
