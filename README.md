# Base nginx Docker image for Drake Apps

This is a base nginx docker image used for nearly all of my nginx deployments.

## Differences between this and base nginx:alpine

1. Redirects not found URLs back to the index
2. Increase cache lifetime of static assets
3. Blocks hidden / dot files

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
