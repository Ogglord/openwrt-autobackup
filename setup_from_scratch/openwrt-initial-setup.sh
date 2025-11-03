#!/bin/sh
# OpenWrt VLAN Configuration Script for GL.iNet Flint 2
# Configures VLANs 99 (Mgmt/LAN), 100 (WiFi), and 20 (Services)
#
# Prerequisites:
# - Router IP already set to 192.168.99.1
# - WiFi SSIDs already configured
# - Stock OpenWrt configuration otherwise
#
# Usage: ./openwrt-initial-setup.sh

set -e

echo "=========================================="
echo "OpenWrt VLAN Configuration Script"
echo "=========================================="
echo ""

# Backup current configuration
echo "[1/6] Backing up current configuration..."
cp /etc/config/network /etc/config/network.backup.$(date +%Y%m%d_%H%M%S)
cp /etc/config/dhcp /etc/config/dhcp.backup.$(date +%Y%m%d_%H%M%S)
cp /etc/config/firewall /etc/config/firewall.backup.$(date +%Y%m%d_%H%M%S)
echo "Backups created in /etc/config/"

# ==========================================
# NETWORK CONFIGURATION
# ==========================================

echo ""
echo "[2/6] Configuring bridge VLANs and interfaces..."

# Remove default LAN bridge VLAN if it exists
uci -q delete network.@bridge-vlan[0] 2>/dev/null || true

# Configure br-lan as the main bridge device
uci set network.@device[0].name='br-lan'
uci set network.@device[0].type='bridge'
uci -q delete network.@device[0].ports 2>/dev/null || true
uci add_list network.@device[0].ports='lan1'
uci add_list network.@device[0].ports='lan2'
uci add_list network.@device[0].ports='lan3'
uci add_list network.@device[0].ports='lan4'
uci add_list network.@device[0].ports='lan5'
uci set network.@device[0].bridge_empty='1'

# VLAN 99 - Management/LAN (192.168.99.0/24)
# Tagged on trunk port (lan1), untagged on other ports
uci add network bridge-vlan
uci set network.@bridge-vlan[-1].device='br-lan'
uci set network.@bridge-vlan[-1].vlan='99'
uci add_list network.@bridge-vlan[-1].ports='lan1:t'  # Tagged for trunk to switch
uci add_list network.@bridge-vlan[-1].ports='lan2'
uci add_list network.@bridge-vlan[-1].ports='lan3'
uci add_list network.@bridge-vlan[-1].ports='lan4'
uci add_list network.@bridge-vlan[-1].ports='lan5'

# VLAN 20 - Services (192.168.20.0/24)
# Tagged on trunk port only
uci add network bridge-vlan
uci set network.@bridge-vlan[-1].device='br-lan'
uci set network.@bridge-vlan[-1].vlan='20'
uci add_list network.@bridge-vlan[-1].ports='lan1:t'  # Tagged for trunk to switch

# Configure LAN interface (VLAN 99)
uci set network.lan=interface
uci set network.lan.device='br-lan.99'
uci set network.lan.proto='static'
uci set network.lan.ipaddr='192.168.99.1'
uci set network.lan.netmask='255.255.255.0'
uci set network.lan.ip6assign='60'

# Configure WiFi interface (VLAN 100) - WiFi only, no switch tagging
uci set network.wifi=interface
uci set network.wifi.proto='static'
uci set network.wifi.ipaddr='192.168.100.1'
uci set network.wifi.netmask='255.255.255.0'
uci set network.wifi.device='br-wifi'

# Create separate bridge for WiFi (VLAN 100)
uci set network.br_wifi=device
uci set network.br_wifi.name='br-wifi'
uci set network.br_wifi.type='bridge'
uci set network.br_wifi.bridge_empty='1'

# Configure Services interface (VLAN 20)
uci set network.services=interface
uci set network.services.device='br-lan.20'
uci set network.services.proto='static'
uci set network.services.ipaddr='192.168.20.1'
uci set network.services.netmask='255.255.255.0'

echo "Network interfaces configured:"
echo "  - VLAN 99 (LAN/Mgmt): 192.168.99.1/24"
echo "  - VLAN 100 (WiFi): 192.168.100.1/24"
echo "  - VLAN 20 (Services): 192.168.20.1/24"

# ==========================================
# DHCP CONFIGURATION
# ==========================================

echo ""
echo "[3/6] Configuring DHCP servers..."
# DHCP for VLAN 99 (LAN/Mgmt)
uci set dhcp.lan=dhcp
uci set dhcp.lan.interface='lan'
uci set dhcp.lan.start='100'
uci set dhcp.lan.limit='150'
uci set dhcp.lan.leasetime='12h'
uci set dhcp.lan.dhcpv4='server'
uci set dhcp.lan.dhcpv6='server'
uci set dhcp.lan.ra='server'

# DHCP for VLAN 100 (WiFi)
uci set dhcp.wifi=dhcp
uci set dhcp.wifi.interface='wifi'
uci set dhcp.wifi.start='100'
uci set dhcp.wifi.limit='150'
uci set dhcp.wifi.leasetime='12h'
uci set dhcp.wifi.dhcpv4='server'

# DHCP for VLAN 20 (Services)
uci set dhcp.services=dhcp
uci set dhcp.services.interface='services'
uci set dhcp.services.start='100'
uci set dhcp.services.limit='150'
uci set dhcp.services.leasetime='12h'
uci set dhcp.services.dhcpv4='server'

echo "DHCP servers configured for all VLANs"

# ==========================================
# FIREWALL CONFIGURATION
# ==========================================

echo ""
echo "[4/6] Configuring firewall zones and rules..."

# Stop firewall service completely
echo "Stopping firewall service..."
/etc/init.d/firewall stop >/dev/null 2>&1 || true
nft flush ruleset 2>/dev/null || true
sleep 2

# Clear generated firewall state files
echo "Clearing firewall state..."
rm -f /var/run/fw4.state 2>/dev/null || true
rm -f /tmp/fw4.* 2>/dev/null || true

# COMPLETELY clear ALL firewall UCI configuration
echo "Clearing firewall UCI configuration..."
uci -q delete firewall.@defaults[0] 2>/dev/null || true
while uci -q delete firewall.@zone[-1] 2>/dev/null; do :; done
while uci -q delete firewall.@forwarding[-1] 2>/dev/null; do :; done
while uci -q delete firewall.@rule[-1] 2>/dev/null; do :; done
while uci -q delete firewall.@redirect[-1] 2>/dev/null; do :; done
while uci -q delete firewall.@ipset[-1] 2>/dev/null; do :; done
while uci -q delete firewall.@include[-1] 2>/dev/null; do :; done

# Rebuild firewall from scratch
echo "Building new firewall configuration..."

# Firewall defaults (MUST be first)
uci add firewall defaults
uci set firewall.@defaults[-1].input='REJECT'
uci set firewall.@defaults[-1].output='ACCEPT'
uci set firewall.@defaults[-1].forward='REJECT'
uci set firewall.@defaults[-1].synflood_protect='1'
uci set firewall.@defaults[-1].drop_invalid='1'

# Zone: WAN
uci add firewall zone
uci set firewall.@zone[-1].name='wan'
uci set firewall.@zone[-1].input='REJECT'
uci set firewall.@zone[-1].output='ACCEPT'
uci set firewall.@zone[-1].forward='REJECT'
uci set firewall.@zone[-1].masq='1'
uci set firewall.@zone[-1].mtu_fix='1'
uci add_list firewall.@zone[-1].network='wan'
uci add_list firewall.@zone[-1].network='wan6'

# Zone: LAN (VLAN 99)
uci add firewall zone
uci set firewall.@zone[-1].name='lan'
uci set firewall.@zone[-1].input='ACCEPT'
uci set firewall.@zone[-1].output='ACCEPT'
uci set firewall.@zone[-1].forward='ACCEPT'
uci add_list firewall.@zone[-1].network='lan'

# Zone: WiFi (VLAN 100)
uci add firewall zone
uci set firewall.@zone[-1].name='wifi'
uci set firewall.@zone[-1].input='REJECT'
uci set firewall.@zone[-1].output='ACCEPT'
uci set firewall.@zone[-1].forward='REJECT'
uci add_list firewall.@zone[-1].network='wifi'

# Zone: Services (VLAN 20)
uci add firewall zone
uci set firewall.@zone[-1].name='services'
uci set firewall.@zone[-1].input='REJECT'
uci set firewall.@zone[-1].output='ACCEPT'
uci set firewall.@zone[-1].forward='REJECT'
uci add_list firewall.@zone[-1].network='services'

# Forwarding rules for inter-VLAN routing

# LAN -> WAN
uci add firewall forwarding
uci set firewall.@forwarding[-1].src='lan'
uci set firewall.@forwarding[-1].dest='wan'

# LAN -> WiFi
uci add firewall forwarding
uci set firewall.@forwarding[-1].src='lan'
uci set firewall.@forwarding[-1].dest='wifi'

# LAN -> Services
uci add firewall forwarding
uci set firewall.@forwarding[-1].src='lan'
uci set firewall.@forwarding[-1].dest='services'

# WiFi -> WAN
uci add firewall forwarding
uci set firewall.@forwarding[-1].src='wifi'
uci set firewall.@forwarding[-1].dest='wan'

# Services -> WAN
uci add firewall forwarding
uci set firewall.@forwarding[-1].src='services'
uci set firewall.@forwarding[-1].dest='wan'


# Basic WAN input rules
uci add firewall rule
uci set firewall.@rule[-1].name='Allow-DHCP-Renew'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].dest_port='68'
uci set firewall.@rule[-1].target='ACCEPT'
uci set firewall.@rule[-1].family='ipv4'

uci add firewall rule
uci set firewall.@rule[-1].name='Allow-Ping'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].proto='icmp'
uci set firewall.@rule[-1].icmp_type='echo-request'
uci set firewall.@rule[-1].family='ipv4'
uci set firewall.@rule[-1].target='ACCEPT'

uci add firewall rule
uci set firewall.@rule[-1].name='Allow-IGMP'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].proto='igmp'
uci set firewall.@rule[-1].family='ipv4'
uci set firewall.@rule[-1].target='ACCEPT'

uci add firewall rule
uci set firewall.@rule[-1].name='Allow-DHCPv6'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].dest_port='546'
uci set firewall.@rule[-1].family='ipv6'
uci set firewall.@rule[-1].target='ACCEPT'

uci add firewall rule
uci set firewall.@rule[-1].name='Allow-MLD'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].proto='icmp'
uci set firewall.@rule[-1].src_ip='fe80::/10'
uci add_list firewall.@rule[-1].icmp_type='130/0'
uci add_list firewall.@rule[-1].icmp_type='131/0'
uci add_list firewall.@rule[-1].icmp_type='132/0'
uci add_list firewall.@rule[-1].icmp_type='143/0'
uci set firewall.@rule[-1].family='ipv6'
uci set firewall.@rule[-1].target='ACCEPT'

uci add firewall rule
uci set firewall.@rule[-1].name='Allow-ICMPv6-Input'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].proto='icmp'
uci add_list firewall.@rule[-1].icmp_type='echo-request'
uci add_list firewall.@rule[-1].icmp_type='echo-reply'
uci add_list firewall.@rule[-1].icmp_type='destination-unreachable'
uci add_list firewall.@rule[-1].icmp_type='packet-too-big'
uci add_list firewall.@rule[-1].icmp_type='time-exceeded'
uci add_list firewall.@rule[-1].icmp_type='bad-header'
uci add_list firewall.@rule[-1].icmp_type='unknown-header-type'
uci add_list firewall.@rule[-1].icmp_type='router-solicitation'
uci add_list firewall.@rule[-1].icmp_type='neighbour-solicitation'
uci add_list firewall.@rule[-1].icmp_type='router-advertisement'
uci add_list firewall.@rule[-1].icmp_type='neighbour-advertisement'
uci set firewall.@rule[-1].limit='1000/sec'
uci set firewall.@rule[-1].family='ipv6'
uci set firewall.@rule[-1].target='ACCEPT'

uci add firewall rule
uci set firewall.@rule[-1].name='Allow-ICMPv6-Forward'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].dest='*'
uci set firewall.@rule[-1].proto='icmp'
uci add_list firewall.@rule[-1].icmp_type='echo-request'
uci add_list firewall.@rule[-1].icmp_type='echo-reply'
uci add_list firewall.@rule[-1].icmp_type='destination-unreachable'
uci add_list firewall.@rule[-1].icmp_type='packet-too-big'
uci add_list firewall.@rule[-1].icmp_type='time-exceeded'
uci add_list firewall.@rule[-1].icmp_type='bad-header'
uci add_list firewall.@rule[-1].icmp_type='unknown-header-type'
uci set firewall.@rule[-1].limit='1000/sec'
uci set firewall.@rule[-1].family='ipv6'
uci set firewall.@rule[-1].target='ACCEPT'

uci add firewall rule
uci set firewall.@rule[-1].name='Allow-IPSec-ESP'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].dest='lan'
uci set firewall.@rule[-1].proto='esp'
uci set firewall.@rule[-1].target='ACCEPT'

uci add firewall rule
uci set firewall.@rule[-1].name='Allow-ISAKMP'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].dest='lan'
uci set firewall.@rule[-1].dest_port='500'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].target='ACCEPT'

uci add firewall rule
uci set firewall.@rule[-1].name='Allow-DHCP-Services'
uci set firewall.@rule[-1].src='services'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].dest_port='67-68'
uci set firewall.@rule[-1].target='ACCEPT'

uci add firewall rule
uci set firewall.@rule[-1].name='Allow-DNS-Services'
uci set firewall.@rule[-1].src='services'
uci set firewall.@rule[-1].proto='tcp udp'
uci set firewall.@rule[-1].dest_port='53'
uci set firewall.@rule[-1].target='ACCEPT'

uci add firewall rule
uci set firewall.@rule[-1].name='Allow-DHCP-WiFi'
uci set firewall.@rule[-1].src='wifi'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].dest_port='67-68'
uci set firewall.@rule[-1].target='ACCEPT'

uci add firewall rule
uci set firewall.@rule[-1].name='Allow-DNS-WiFi'
uci set firewall.@rule[-1].src='wifi'
uci set firewall.@rule[-1].proto='tcp udp'
uci set firewall.@rule[-1].dest_port='53'
uci set firewall.@rule[-1].target='ACCEPT'



echo "Firewall configuration built successfully"
echo "  - 4 zones: wan, lan, wifi, services"
echo "  - 7 forwarding rules for inter-VLAN routing"
echo "  - Standard WAN input rules configured"

# ==========================================
# WIRELESS CONFIGURATION
# ==========================================

echo ""
echo "[5/6] Attaching WiFi interfaces to VLAN 100..."

# Update wireless interfaces to use the wifi network (VLAN 100)
# This assumes radio0 and radio1 exist (2.4GHz and 5GHz)

# 2.4GHz WiFi
if uci -q get wireless.default_radio0 >/dev/null 2>&1; then
    uci set wireless.default_radio0.network='wifi'
    echo "  - 2.4GHz WiFi attached to VLAN 100"
fi

# 5GHz WiFi
if uci -q get wireless.default_radio1 >/dev/null 2>&1; then
    uci set wireless.default_radio1.network='wifi'
    echo "  - 5GHz WiFi attached to VLAN 100"
fi

# 6GHz WiFi (if available)
if uci -q get wireless.default_radio2 >/dev/null 2>&1; then
    uci set wireless.default_radio2.network='wifi'
    echo "  - 6GHz WiFi attached to VLAN 100"
fi

# ==========================================
# COMMIT AND APPLY CHANGES
# ==========================================

echo ""
echo "[6/6] Committing and applying configuration..."

# Commit all changes
uci commit network
uci commit dhcp
uci commit firewall
uci commit wireless

echo "Configuration committed successfully"
echo ""
echo "=========================================="
echo "Configuration Summary"
echo "=========================================="
echo ""
echo "VLANs configured:"
echo "  VLAN 99  - Management/LAN (192.168.99.0/24)"
echo "           - Router IP: 192.168.99.1"
echo "           - Switch trunk: Tagged on lan1"
echo "           - Untagged on lan2-5"
echo ""
echo "  VLAN 100 - WiFi only (192.168.100.0/24)"
echo "           - Router IP: 192.168.100.1"
echo "           - NOT tagged to switch"
echo ""
echo "  VLAN 20  - Services (192.168.20.0/24)"
echo "           - Router IP: 192.168.20.1"
echo "           - Switch trunk: Tagged on lan1"
echo ""
echo "Trunk port to switch: lan1 (carries VLANs 99, 20)"
echo ""
echo "DHCP ranges:"
echo "  - VLAN 99:  192.168.99.100-250"
echo "  - VLAN 100: 192.168.100.100-250"
echo "  - VLAN 20:  192.168.20.100-250"
echo ""
echo "Firewall: Inter-VLAN routing enabled"
echo ""
echo "=========================================="
echo ""
echo "IMPORTANT: The network will restart now."
echo "You may need to:"
echo "  1. Reconnect to the router at 192.168.99.1 (if on LAN)"
echo "  2. Or 192.168.100.1 (if on WiFi)"
echo "  3. Verify switch is connected to lan1 port"
echo ""
read -p "Press ENTER to restart network and apply changes (or Ctrl+C to cancel)..."

# Restart services to apply changes
echo ""
echo "Restarting services (this may take 30-60 seconds)..."
echo ""

# Restart in sequence with delays
echo "[1/3] Restarting firewall..."
/etc/init.d/firewall restart
sleep 3

echo "[2/3] Restarting network..."
/etc/init.d/network restart
sleep 5

echo "[3/3] Restarting dnsmasq..."
/etc/init.d/dnsmasq restart
sleep 2

echo ""
echo "Configuration complete!"
echo ""
echo "Next steps:"
echo "  1. Connect switch to router's lan1 port"
echo "  2. Configure switch with VLANs 99 and 20 (tagged on uplink)"
echo "  3. Set switch management IP to 192.168.99.2"
echo "  4. Verify connectivity between VLANs"
echo ""
echo "Backups saved to:"
echo "  /etc/config/network.backup.*"
echo "  /etc/config/dhcp.backup.*"
echo "  /etc/config/firewall.backup.*"
echo ""