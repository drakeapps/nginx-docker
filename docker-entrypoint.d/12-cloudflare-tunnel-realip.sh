#!/bin/sh
# Trust the local hop for CF-Connecting-IP when nginx sits behind a Cloudflare
# Tunnel.
#
# nginx.conf trusts Cloudflare's published edge ranges, which is correct when
# Cloudflare proxies straight to the origin. With a tunnel it is `cloudflared`
# that connects to nginx, so the peer address is the docker bridge gateway, a
# sibling container, or loopback — never a Cloudflare address. The realip
# module therefore never fires and every request is attributed to the tunnel:
# access logs show a single IP for the entire internet, and anything keyed on
# $remote_addr (rate limits, geo, allow/deny) collapses into one bucket.
#
# Opt-in, because trusting a private peer means anything able to reach nginx
# from one of these ranges can forge CF-Connecting-IP and claim to be any
# client it likes. That is fine when the tunnel is the only way in; it is not
# when the container is also reachable from a LAN or from another proxy.
#
#   CLOUDFLARE_TUNNEL=1                     enable
#   CLOUDFLARE_TUNNEL_TRUSTED="cidr cidr"   override the trusted ranges
#                                           (space- or comma-separated)
set -e

ME="$(basename "$0")"

case "$(printf '%s' "${CLOUDFLARE_TUNNEL:-}" | tr '[:upper:]' '[:lower:]')" in
    1 | true | yes | on) ;;
    *) exit 0 ;;
esac

# Loopback covers `network_mode: host`; the RFC1918 ranges and the IPv6 ULA
# range cover a bridge gateway or a cloudflared sibling container.
TRUSTED="${CLOUDFLARE_TUNNEL_TRUSTED:-127.0.0.1/32 ::1/128 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 fc00::/7}"
TARGET=/etc/nginx/conf.d/00-cloudflare-tunnel-realip.conf

# conf.d is included at the http level, so set_real_ip_from here joins the
# Cloudflare ranges already listed in nginx.conf rather than replacing them —
# an origin can be reachable both ways.
{
    echo "# Generated at startup by $ME — do not edit."
    echo "# CLOUDFLARE_TUNNEL=$CLOUDFLARE_TUNNEL"
    for cidr in $(printf '%s' "$TRUSTED" | tr ',' ' '); do
        echo "set_real_ip_from $cidr;"
    done
} > "$TARGET"

echo "$ME: CF-Connecting-IP trusted from $(printf '%s' "$TRUSTED" | tr ',' ' ')"
