#!/bin/sh
# Log request timings (rt, urt, cs, st) when NGINX_LOG_TIMING is on.
#
# Swaps the http-level access log for the `cloudflare_timing` format defined
# in nginx.conf: the `cloudflare` format followed by
#
#   rt=$request_time urt="$upstream_response_time"
#   cs=$upstream_cache_status st="$upstream_http_server_timing"
#
# Sites that leave it unset log exactly what they did before. The file is
# rewritten rather than added to conf.d, because a second access_log at the
# http level would log every request twice.
#
#   NGINX_LOG_TIMING=1   enable
set -e

ME="$(basename "$0")"

case "$(printf '%s' "${NGINX_LOG_TIMING:-}" | tr '[:upper:]' '[:lower:]')" in
    1 | true | yes | on) ;;
    *) exit 0 ;;
esac

{
    echo "# Generated at startup by $ME — do not edit."
    echo "# NGINX_LOG_TIMING=$NGINX_LOG_TIMING"
    echo "access_log /var/log/nginx/access.log cloudflare_timing;"
} > /etc/nginx/access-log.conf

echo "$ME: access log format cloudflare_timing"
