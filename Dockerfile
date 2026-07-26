# Accept the version as a build argument (defaults to 'latest' if not provided)
ARG NGINX_VERSION=latest

# Build the Brotli dynamic modules against the exact nginx version used by the
# final image. The official nginx binaries are built with --with-compat, so
# modules compiled with --with-compat here load cleanly into them.
FROM nginx:${NGINX_VERSION}-alpine AS brotli-builder

# Pinned to the current head of google/ngx_brotli
ARG NGX_BROTLI_COMMIT=a71f9312c2deb28875acc7bacfdd5695a111aa53

RUN set -eux; \
    apk add --no-cache build-base cmake git linux-headers openssl-dev pcre-dev zlib-dev; \
    NGINX_SRC_VERSION="$(nginx -v 2>&1 | sed -n 's|^.*nginx/||p')"; \
    mkdir -p /usr/src; \
    wget -qO- "https://nginx.org/download/nginx-${NGINX_SRC_VERSION}.tar.gz" | tar -xz -C /usr/src; \
    git clone https://github.com/google/ngx_brotli.git /usr/src/ngx_brotli; \
    cd /usr/src/ngx_brotli; \
    git checkout "${NGX_BROTLI_COMMIT}"; \
    git submodule update --init --recursive; \
    # ngx_brotli links against the bundled libbrotli built into deps/brotli/out,
    # statically, so the runtime image needs no extra brotli package.
    cmake -S /usr/src/ngx_brotli/deps/brotli -B /usr/src/ngx_brotli/deps/brotli/out \
        -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF; \
    cmake --build /usr/src/ngx_brotli/deps/brotli/out --config Release --target brotlienc -j"$(nproc)"; \
    cd "/usr/src/nginx-${NGINX_SRC_VERSION}"; \
    ./configure --with-compat --add-dynamic-module=/usr/src/ngx_brotli; \
    make -j"$(nproc)" modules; \
    mkdir -p /modules; \
    cp objs/ngx_http_brotli_filter_module.so objs/ngx_http_brotli_static_module.so /modules/; \
    strip /modules/*.so

FROM nginx:${NGINX_VERSION}-alpine

COPY --from=brotli-builder /modules/*.so /usr/lib/nginx/modules/

RUN rm -rf /usr/share/nginx/html/*

COPY nginx.conf /etc/nginx/nginx.conf
COPY default.conf /etc/nginx/conf.d/default.conf
