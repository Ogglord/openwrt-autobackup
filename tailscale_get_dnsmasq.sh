#!/bin/sh
# Update dnsmasq with Tailscale hostnames on OpenWrt
# dnsmasq needs to be configured with 
# config dnsmasq
#    option confdir '/etc/dnsmasq.d'

CONF_DIR="/etc/dnsmasq.d"
CONF_FILE="${CONF_DIR}/tailscale.conf"

mkdir -p "$CONF_DIR"
> "$CONF_FILE"

tailscale status --json | jq -c '.Peer[] | select(.TailscaleIPs != null)' | while read -r peer; do
    ip=$(echo "$peer" | jq -r '.TailscaleIPs[0]')
    short=$(echo "$peer" | jq -r '.HostName // empty')
    full=$(echo "$peer" | jq -r '.DNSName // empty')

    # Remove trailing dot from FQDN
    full="${full%%.}"

    echo "address=/${full}/${ip}" >> "$CONF_FILE"

    # Skip empty, localhost, or any name with space or apostrophe
    [ -z "$short" ] && continue
    [ "$short" = "localhost" ] && continue
    echo "$short" | grep -q "[ '’]" && continue
    echo "address=/${short}.lan/${ip}" >> "$CONF_FILE"
done

/etc/init.d/dnsmasq reload