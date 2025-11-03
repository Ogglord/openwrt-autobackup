#!/bin/sh
# OpenWrt DNS Domain Configuration Script
# Configures separate DNS domains for each VLAN
#
# VLAN 99 (LAN):      .lan suffix      (192.168.99.0/24)
# VLAN 100 (WiFi):    .wifi suffix     (192.168.100.0/24)
# VLAN 20 (Services): .services suffix (192.168.20.0/24)
#
# Usage: ./configure-dns-domains.sh

set -e

echo "==========================================="
echo "OpenWrt DNS Domain Configuration"
echo "==========================================="
echo ""

# Backup current DHCP configuration
echo "[1/3] Backing up current DHCP configuration..."
cp /etc/config/dhcp /etc/config/dhcp.backup.dns.$(date +%Y%m%d_%H%M%S)
echo "Backup created in /etc/config/"

# ==========================================
# DHCP/DNS DOMAIN CONFIGURATION
# ==========================================

echo ""
echo "[2/3] Configuring DNS domains for each VLAN..."

# Configure dnsmasq general settings
echo "Configuring dnsmasq general settings..."
uci set dhcp.@dnsmasq[0].domainneeded='1'
uci set dhcp.@dnsmasq[0].localise_queries='1'
uci set dhcp.@dnsmasq[0].rebind_protection='1'
uci set dhcp.@dnsmasq[0].rebind_localhost='1'
uci set dhcp.@dnsmasq[0].local='/lan/'
uci set dhcp.@dnsmasq[0].domain='lan'
uci set dhcp.@dnsmasq[0].expandhosts='1'
uci set dhcp.@dnsmasq[0].authoritative='1'
uci set dhcp.@dnsmasq[0].readethers='1'
uci set dhcp.@dnsmasq[0].leasefile='/tmp/dhcp.leases'
uci set dhcp.@dnsmasq[0].localservice='1'

# VLAN 99 - Management/LAN (.lan)
echo "Configuring VLAN 99 (LAN) - domain: .lan"
uci set dhcp.lan=dhcp
uci set dhcp.lan.interface='lan'
uci set dhcp.lan.start='100'
uci set dhcp.lan.limit='150'
uci set dhcp.lan.leasetime='30m'
uci set dhcp.lan.dhcpv4='server'
uci set dhcp.lan.dhcpv6='server'
uci set dhcp.lan.ra='server'
uci set dhcp.lan.domain='lan'
uci -q delete dhcp.lan.dhcp_option 2>/dev/null || true
uci add_list dhcp.lan.dhcp_option='6,192.168.99.1'
uci add_list dhcp.lan.dhcp_option='15,lan'

# VLAN 100 - WiFi (.wifi)
echo "Configuring VLAN 100 (WiFi) - domain: .wifi"
uci set dhcp.wifi=dhcp
uci set dhcp.wifi.interface='wifi'
uci set dhcp.wifi.start='100'
uci set dhcp.wifi.limit='150'
uci set dhcp.wifi.leasetime='30m'
uci set dhcp.wifi.dhcpv4='server'
uci set dhcp.wifi.domain='wifi'
uci -q delete dhcp.wifi.dhcp_option 2>/dev/null || true
uci add_list dhcp.wifi.dhcp_option='6,192.168.100.1'
uci add_list dhcp.wifi.dhcp_option='15,wifi'

# VLAN 20 - Services (.services)
echo "Configuring VLAN 20 (Services) - domain: .services"
uci set dhcp.services=dhcp
uci set dhcp.services.interface='services'
uci set dhcp.services.start='100'
uci set dhcp.services.limit='150'
uci set dhcp.services.leasetime='30m'
uci set dhcp.services.dhcpv4='server'
uci set dhcp.services.domain='services'
uci -q delete dhcp.services.dhcp_option 2>/dev/null || true
uci add_list dhcp.services.dhcp_option='6,192.168.20.1'
uci add_list dhcp.services.dhcp_option='15,services'

echo "DNS domains configured:"
echo "  - VLAN 99 (LAN):      .lan domain"
echo "  - VLAN 100 (WiFi):    .wifi domain"
echo "  - VLAN 20 (Services): .services domain"

# ==========================================
# COMMIT AND APPLY CHANGES
# ==========================================

echo ""
echo "[3/3] Committing and applying configuration..."

# Commit changes
uci commit dhcp

echo "Configuration committed successfully"
echo ""
echo "==========================================="
echo "Configuration Summary"
echo "==========================================="
echo ""
echo "DNS Domains configured:"
echo "  LAN (192.168.99.x)      -> hostname.lan"
echo "  WiFi (192.168.100.x)    -> hostname.wifi"
echo "  Services (192.168.20.x) -> hostname.services"
echo ""
echo "DNS servers (DHCP option 6):"
echo "  LAN:      192.168.99.1"
echo "  WiFi:     192.168.100.1"
echo "  Services: 192.168.20.1"
echo ""
echo "Domain search (DHCP option 15):"
echo "  LAN:      lan"
echo "  WiFi:     wifi"
echo "  Services: services"
echo ""
echo "==========================================="
echo ""
echo "IMPORTANT: dnsmasq will restart now."
echo "Clients will need to renew their DHCP leases to get new domain settings."
echo ""
read -p "Press ENTER to restart dnsmasq and apply changes (or Ctrl+C to cancel)..."

# Restart dnsmasq
echo ""
echo "Restarting dnsmasq..."
/etc/init.d/dnsmasq restart
sleep 2

echo ""
echo "Configuration complete!"
echo ""
echo "Verification steps:"
echo "  1. Check dnsmasq status: /etc/init.d/dnsmasq status"
echo "  2. View DHCP leases: cat /tmp/dhcp.leases"
echo "  3. Test DNS resolution: nslookup <hostname>.lan"
echo "  4. Force clients to renew DHCP leases"
echo ""
echo "Example usage:"
echo "  - From LAN: ping myserver.services"
echo "  - From WiFi: ping router.lan"
echo "  - From Services: ping laptop.wifi"
echo ""
echo "Note: Cross-VLAN DNS resolution works, but firewall rules"
echo "      still control actual connectivity between zones."
echo ""
