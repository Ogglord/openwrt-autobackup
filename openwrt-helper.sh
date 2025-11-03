#!/bin/bash
# OpenWrt Configuration Helper Agent
# Interactive shell script to help configure OpenWrt routers

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Check if running on OpenWrt
check_openwrt() {
    if ! command -v uci &> /dev/null; then
        print_error "This script must be run on an OpenWrt system (uci command not found)"
        exit 1
    fi
}

# Main menu
show_menu() {
    clear
    print_header "OpenWrt Configuration Helper"
    echo "1)  Show current network configuration"
    echo "2)  Show current VLAN configuration"
    echo "3)  Show current firewall zones"
    echo "4)  Show DHCP configuration"
    echo "5)  Show WiFi configuration"
    echo "6)  Test inter-VLAN connectivity"
    echo "7)  Backup current configuration"
    echo "8)  Show network statistics"
    echo "9)  Verify VLAN setup"
    echo "10) Run full configuration from script"
    echo "11) Show firewall rules"
    echo "12) Restart network services"
    echo "13) Show connected clients"
    echo "14) Test DNS configuration"
    echo "15) Show DNS domains and leases"
    echo "16) Troubleshooting menu"
    echo "0)  Exit"
    echo ""
    read -p "Select an option: " choice
}

# 1. Show network configuration
show_network_config() {
    print_header "Network Configuration"

    echo -e "${YELLOW}=== Interfaces ===${NC}"
    uci show network | grep "=interface" || print_warning "No interfaces configured"

    echo -e "\n${YELLOW}=== IP Addresses ===${NC}"
    uci show network | grep "ipaddr" || print_warning "No IP addresses configured"

    echo -e "\n${YELLOW}=== Bridge Devices ===${NC}"
    uci show network | grep "device" | grep "bridge" || print_warning "No bridges configured"

    echo -e "\n${YELLOW}=== Active Interfaces (ip addr) ===${NC}"
    ip addr show | grep -E "^[0-9]+:|inet " || print_warning "Cannot show IP addresses"
}

# 2. Show VLAN configuration
show_vlan_config() {
    print_header "VLAN Configuration"

    echo -e "${YELLOW}=== Bridge VLANs ===${NC}"
    uci show network | grep "bridge-vlan" || print_warning "No VLANs configured"

    echo -e "\n${YELLOW}=== VLAN Details ===${NC}"
    for i in $(seq 0 10); do
        if uci -q get network.@bridge-vlan[$i].vlan &>/dev/null; then
            vlan=$(uci get network.@bridge-vlan[$i].vlan)
            device=$(uci get network.@bridge-vlan[$i].device 2>/dev/null || echo "N/A")
            ports=$(uci get network.@bridge-vlan[$i].ports 2>/dev/null || echo "N/A")
            echo -e "${GREEN}VLAN $vlan${NC} on ${BLUE}$device${NC}"
            echo "  Ports: $ports"
        fi
    done

    echo -e "\n${YELLOW}=== Bridge Command Output ===${NC}"
    if command -v bridge &> /dev/null; then
        bridge vlan show 2>/dev/null || print_warning "Bridge command not available"
    else
        print_warning "Bridge command not installed"
    fi
}

# 3. Show firewall zones
show_firewall_zones() {
    print_header "Firewall Zones"

    echo -e "${YELLOW}=== Zones ===${NC}"
    for i in $(seq 0 10); do
        if uci -q get firewall.@zone[$i].name &>/dev/null; then
            name=$(uci get firewall.@zone[$i].name)
            input=$(uci get firewall.@zone[$i].input 2>/dev/null || echo "N/A")
            output=$(uci get firewall.@zone[$i].output 2>/dev/null || echo "N/A")
            forward=$(uci get firewall.@zone[$i].forward 2>/dev/null || echo "N/A")
            networks=$(uci get firewall.@zone[$i].network 2>/dev/null || echo "N/A")

            echo -e "${GREEN}Zone: $name${NC}"
            echo "  Networks: $networks"
            echo "  Input: $input | Output: $output | Forward: $forward"
            echo ""
        fi
    done

    echo -e "${YELLOW}=== Forwarding Rules ===${NC}"
    for i in $(seq 0 20); do
        if uci -q get firewall.@forwarding[$i].src &>/dev/null; then
            src=$(uci get firewall.@forwarding[$i].src)
            dest=$(uci get firewall.@forwarding[$i].dest)
            echo "  $src → $dest"
        fi
    done
}

# 4. Show DHCP configuration
show_dhcp_config() {
    print_header "DHCP Configuration"

    echo -e "${YELLOW}=== DHCP Servers ===${NC}"
    uci show dhcp | grep "=dhcp" || print_warning "No DHCP servers configured"

    echo -e "\n${YELLOW}=== DHCP Ranges ===${NC}"
    for section in $(uci show dhcp | grep "=dhcp$" | cut -d'.' -f2 | cut -d'=' -f1); do
        if [ "$section" != "odhcpd" ]; then
            interface=$(uci -q get dhcp.$section.interface || echo "N/A")
            start=$(uci -q get dhcp.$section.start || echo "N/A")
            limit=$(uci -q get dhcp.$section.limit || echo "N/A")
            leasetime=$(uci -q get dhcp.$section.leasetime || echo "N/A")

            echo -e "${GREEN}Interface: $interface${NC}"
            echo "  Start: $start | Limit: $limit | Lease time: $leasetime"
        fi
    done

    echo -e "\n${YELLOW}=== Active Leases ===${NC}"
    if [ -f /tmp/dhcp.leases ]; then
        cat /tmp/dhcp.leases | awk '{printf "  %s - %s (%s)\n", $3, $2, $4}'
    else
        print_warning "No lease file found"
    fi
}

# 5. Show WiFi configuration
show_wifi_config() {
    print_header "WiFi Configuration"

    echo -e "${YELLOW}=== Wireless Devices ===${NC}"
    for radio in radio0 radio1 radio2; do
        if uci -q get wireless.$radio &>/dev/null; then
            disabled=$(uci -q get wireless.$radio.disabled || echo "0")
            channel=$(uci -q get wireless.$radio.channel || echo "auto")
            hwmode=$(uci -q get wireless.$radio.hwmode || echo "N/A")

            status="enabled"
            [ "$disabled" = "1" ] && status="disabled"

            echo -e "${GREEN}$radio${NC} ($hwmode) - Channel: $channel - Status: $status"
        fi
    done

    echo -e "\n${YELLOW}=== WiFi Networks ===${NC}"
    for iface in default_radio0 default_radio1 default_radio2; do
        if uci -q get wireless.$iface &>/dev/null; then
            ssid=$(uci -q get wireless.$iface.ssid || echo "N/A")
            network=$(uci -q get wireless.$iface.network || echo "N/A")
            encryption=$(uci -q get wireless.$iface.encryption || echo "none")

            echo -e "${GREEN}$iface${NC}"
            echo "  SSID: $ssid"
            echo "  Network: $network"
            echo "  Encryption: $encryption"
        fi
    done

    echo -e "\n${YELLOW}=== WiFi Status (iw dev) ===${NC}"
    if command -v iw &> /dev/null; then
        iw dev | grep -E "Interface|ssid|channel" || print_warning "No WiFi devices active"
    else
        print_warning "iw command not available"
    fi
}

# 6. Test inter-VLAN connectivity
test_intervlan() {
    print_header "Inter-VLAN Connectivity Test"

    echo "Testing connectivity from this router..."
    echo ""

    # Get configured IPs
    lan_ip=$(uci -q get network.lan.ipaddr || echo "")
    wifi_ip=$(uci -q get network.wifi.ipaddr || echo "")
    services_ip=$(uci -q get network.services.ipaddr || echo "")

    if [ -n "$lan_ip" ]; then
        echo -e "${YELLOW}VLAN 99 (LAN): $lan_ip${NC}"
        ping -c 2 -W 2 $lan_ip &>/dev/null && print_success "Reachable" || print_error "Unreachable"
    fi

    if [ -n "$wifi_ip" ]; then
        echo -e "${YELLOW}VLAN 100 (WiFi): $wifi_ip${NC}"
        ping -c 2 -W 2 $wifi_ip &>/dev/null && print_success "Reachable" || print_error "Unreachable"
    fi

    if [ -n "$services_ip" ]; then
        echo -e "${YELLOW}VLAN 20 (Services): $services_ip${NC}"
        ping -c 2 -W 2 $services_ip &>/dev/null && print_success "Reachable" || print_error "Unreachable"
    fi

    echo ""
    echo -e "${YELLOW}Internet connectivity (8.8.8.8):${NC}"
    ping -c 2 -W 2 8.8.8.8 &>/dev/null && print_success "Reachable" || print_error "Unreachable"
}

# 7. Backup configuration
backup_config() {
    print_header "Backup Configuration"

    timestamp=$(date +%Y%m%d_%H%M%S)
    backup_dir="/etc/config"

    echo "Creating backups with timestamp: $timestamp"

    for config in network dhcp firewall wireless; do
        if [ -f "$backup_dir/$config" ]; then
            cp "$backup_dir/$config" "$backup_dir/${config}.backup.$timestamp"
            print_success "Backed up: ${config}.backup.$timestamp"
        else
            print_warning "Config not found: $config"
        fi
    done

    echo ""
    print_info "Backups saved to: $backup_dir/"
}

# 8. Show network statistics
show_network_stats() {
    print_header "Network Statistics"

    echo -e "${YELLOW}=== Interface Statistics ===${NC}"
    ip -s link show | grep -E "^[0-9]+:|RX:|TX:" || print_warning "Cannot show statistics"

    echo -e "\n${YELLOW}=== Routing Table ===${NC}"
    ip route show || print_warning "Cannot show routes"

    echo -e "\n${YELLOW}=== Active Connections ===${NC}"
    if [ -f /proc/net/nf_conntrack ]; then
        conntrack_count=$(cat /proc/net/nf_conntrack | wc -l)
        echo "Active connections: $conntrack_count"
    else
        print_warning "Conntrack not available"
    fi
}

# 9. Verify VLAN setup
verify_vlan_setup() {
    print_header "VLAN Setup Verification"

    errors=0

    echo -e "${YELLOW}Checking VLAN 99 (Management)...${NC}"
    if uci show network | grep -q "vlan='99'"; then
        print_success "VLAN 99 configured"
        if uci show network | grep "bridge-vlan" | grep -q "lan1:t"; then
            print_success "VLAN 99 tagged on lan1"
        else
            print_error "VLAN 99 not tagged on lan1"
            errors=$((errors+1))
        fi
    else
        print_error "VLAN 99 not found"
        errors=$((errors+1))
    fi

    echo -e "\n${YELLOW}Checking VLAN 100 (WiFi)...${NC}"
    if uci -q get network.wifi.ipaddr &>/dev/null; then
        print_success "WiFi interface configured"
        wifi_net=$(uci -q get wireless.default_radio0.network || echo "")
        if [ "$wifi_net" = "wifi" ]; then
            print_success "WiFi radios attached to wifi network"
        else
            print_warning "WiFi radios may not be configured"
        fi
    else
        print_error "WiFi interface not found"
        errors=$((errors+1))
    fi

    echo -e "\n${YELLOW}Checking VLAN 20 (Services)...${NC}"
    if uci show network | grep -q "vlan='20'"; then
        print_success "VLAN 20 configured"
        if uci show network | grep "bridge-vlan" | grep -q "vlan='20'" && uci show network | grep -A3 "vlan='20'" | grep -q "lan1:t"; then
            print_success "VLAN 20 tagged on lan1"
        else
            print_error "VLAN 20 not tagged on lan1"
            errors=$((errors+1))
        fi
    else
        print_error "VLAN 20 not found"
        errors=$((errors+1))
    fi

    echo -e "\n${YELLOW}Checking Firewall Zones...${NC}"
    for zone in lan wifi services wan; do
        if uci show firewall | grep "name='$zone'" &>/dev/null; then
            print_success "Zone '$zone' exists"
        else
            print_error "Zone '$zone' missing"
            errors=$((errors+1))
        fi
    done

    echo ""
    if [ $errors -eq 0 ]; then
        print_success "All checks passed!"
    else
        print_error "Found $errors error(s)"
    fi
}

# 11. Show firewall rules
show_firewall_rules() {
    print_header "Firewall Rules"

    echo -e "${YELLOW}=== NFTables Ruleset ===${NC}"
    if command -v nft &> /dev/null; then
        nft list ruleset 2>/dev/null || print_warning "Cannot list ruleset"
    else
        print_warning "nft command not available"
    fi

    echo -e "\n${YELLOW}=== UCI Firewall Rules ===${NC}"
    uci show firewall | grep "=rule" || print_warning "No custom rules"
}

# 12. Restart network services
restart_services() {
    print_header "Restart Network Services"

    print_warning "This will restart network services and may interrupt connectivity!"
    read -p "Continue? (y/N): " confirm

    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        echo ""
        echo "Restarting firewall..."
        /etc/init.d/firewall restart
        sleep 2

        echo "Restarting network..."
        /etc/init.d/network restart
        sleep 3

        echo "Restarting dnsmasq..."
        /etc/init.d/dnsmasq restart
        sleep 1

        print_success "Services restarted"
    else
        print_info "Cancelled"
    fi
}

# 13. Show connected clients
show_connected_clients() {
    print_header "Connected Clients"

    echo -e "${YELLOW}=== DHCP Leases ===${NC}"
    if [ -f /tmp/dhcp.leases ]; then
        printf "%-15s %-17s %-20s %s\n" "IP Address" "MAC Address" "Hostname" "Lease Expires"
        echo "--------------------------------------------------------------------"
        while read -r line; do
            lease_time=$(echo $line | awk '{print $1}')
            mac=$(echo $line | awk '{print $2}')
            ip=$(echo $line | awk '{print $3}')
            hostname=$(echo $line | awk '{print $4}')

            # Convert lease time to readable format
            if [ "$lease_time" != "0" ]; then
                expires=$(date -d @$lease_time 2>/dev/null || echo "N/A")
            else
                expires="N/A"
            fi

            printf "%-15s %-17s %-20s %s\n" "$ip" "$mac" "$hostname" "$expires"
        done < /tmp/dhcp.leases
    else
        print_warning "No DHCP leases found"
    fi

    echo -e "\n${YELLOW}=== ARP Table ===${NC}"
    ip neigh show | grep -v "FAILED" || print_warning "No ARP entries"
}

# 14. Test DNS configuration
test_dns_config() {
    print_header "DNS Configuration Test"

    echo -e "${YELLOW}=== DNS Server Configuration ===${NC}"
    echo "Configured DNS domains:"
    echo ""

    # Check each VLAN's DNS configuration
    for iface in lan wifi services; do
        if uci -q get dhcp.$iface.domain &>/dev/null; then
            domain=$(uci get dhcp.$iface.domain)
            ip=$(uci -q get network.$iface.ipaddr || echo "N/A")
            echo -e "${GREEN}$iface${NC}: .$domain (DNS: $ip)"
        fi
    done

    echo ""
    echo -e "${YELLOW}=== Testing DNS Resolution ===${NC}"
    echo ""

    # Test external DNS
    echo "Testing external DNS (google.com)..."
    if nslookup google.com >/dev/null 2>&1; then
        print_success "External DNS resolution working"
    else
        print_error "External DNS resolution failed"
    fi

    echo ""
    echo "Testing local domain resolution..."
    echo "Note: Hostnames must exist in DHCP leases to be resolvable"
    echo ""

    # Get first hostname from each VLAN from leases file
    if [ -f /tmp/dhcp.leases ]; then
        echo "Testing with actual leased hostnames:"
        echo ""

        # Test .lan domain
        lan_host=$(grep "192.168.99" /tmp/dhcp.leases 2>/dev/null | head -1 | awk '{print $4}')
        if [ -n "$lan_host" ] && [ "$lan_host" != "*" ]; then
            echo "Testing: $lan_host.lan"
            if nslookup "$lan_host.lan" >/dev/null 2>&1; then
                print_success "$lan_host.lan resolves"
            else
                print_error "$lan_host.lan does not resolve"
            fi
        else
            print_warning "No .lan hosts with hostnames found in leases"
        fi

        # Test .wifi domain
        wifi_host=$(grep "192.168.100" /tmp/dhcp.leases 2>/dev/null | head -1 | awk '{print $4}')
        if [ -n "$wifi_host" ] && [ "$wifi_host" != "*" ]; then
            echo "Testing: $wifi_host.wifi"
            if nslookup "$wifi_host.wifi" >/dev/null 2>&1; then
                print_success "$wifi_host.wifi resolves"
            else
                print_error "$wifi_host.wifi does not resolve"
            fi
        else
            print_warning "No .wifi hosts with hostnames found in leases"
        fi

        # Test .services domain
        services_host=$(grep "192.168.20" /tmp/dhcp.leases 2>/dev/null | head -1 | awk '{print $4}')
        if [ -n "$services_host" ] && [ "$services_host" != "*" ]; then
            echo "Testing: $services_host.services"
            if nslookup "$services_host.services" >/dev/null 2>&1; then
                print_success "$services_host.services resolves"
            else
                print_error "$services_host.services does not resolve"
            fi
        else
            print_warning "No .services hosts with hostnames found in leases"
        fi
    else
        print_warning "No DHCP leases file found - no hosts to test"
    fi

    echo ""
    echo -e "${YELLOW}=== dnsmasq Configuration ===${NC}"
    uci show dhcp.@dnsmasq[0] | grep -E "domain|local|expand" || print_warning "No DNS settings found"
}

# 15. Show DNS domains and leases
show_dns_domains() {
    print_header "DNS Domains and Leases"

    echo -e "${YELLOW}=== Configured DNS Domains ===${NC}"
    echo ""

    for iface in lan wifi services; do
        if uci -q get dhcp.$iface &>/dev/null; then
            domain=$(uci -q get dhcp.$iface.domain || echo "N/A")
            ip=$(uci -q get network.$iface.ipaddr || echo "N/A")
            start=$(uci -q get dhcp.$iface.start || echo "N/A")
            limit=$(uci -q get dhcp.$iface.limit || echo "N/A")

            echo -e "${GREEN}Interface: $iface${NC}"
            echo "  Domain: .$domain"
            echo "  DNS Server: $ip"
            echo "  DHCP Range: $start - $limit"

            # Show DHCP options
            options=$(uci -q get dhcp.$iface.dhcp_option 2>/dev/null)
            if [ -n "$options" ]; then
                echo "  DHCP Options: $options"
            fi
            echo ""
        fi
    done

    echo -e "${YELLOW}=== Active DHCP Leases by VLAN ===${NC}"
    echo ""

    if [ -f /tmp/dhcp.leases ]; then
        # VLAN 99 - LAN
        echo -e "${GREEN}VLAN 99 (LAN) - .lan domain:${NC}"
        grep "192.168.99" /tmp/dhcp.leases 2>/dev/null | \
            awk '{printf "  %s -> %s (%s.lan)\n", $3, $2, $4}' || echo "  No leases"

        echo ""
        # VLAN 100 - WiFi
        echo -e "${GREEN}VLAN 100 (WiFi) - .wifi domain:${NC}"
        grep "192.168.100" /tmp/dhcp.leases 2>/dev/null | \
            awk '{printf "  %s -> %s (%s.wifi)\n", $3, $2, $4}' || echo "  No leases"

        echo ""
        # VLAN 20 - Services
        echo -e "${GREEN}VLAN 20 (Services) - .services domain:${NC}"
        grep "192.168.20" /tmp/dhcp.leases 2>/dev/null | \
            awk '{printf "  %s -> %s (%s.services)\n", $3, $2, $4}' || echo "  No leases"
    else
        print_warning "No DHCP leases file found"
    fi

    echo ""
    echo -e "${YELLOW}=== DNS Query Log (if enabled) ===${NC}"
    if logread | grep -q "dnsmasq"; then
        logread | grep "dnsmasq" | tail -20
    else
        print_info "No dnsmasq logs found (query logging may not be enabled)"
    fi
}

# 16. Troubleshooting menu
troubleshooting_menu() {
    clear
    print_header "Troubleshooting Menu"
    echo "1) Check if VLANs are in kernel"
    echo "2) Show bridge status"
    echo "3) Check firewall status"
    echo "4) Show system log (last 50 lines)"
    echo "5) Show kernel log (dmesg)"
    echo "6) Test DNS resolution"
    echo "7) Show interface details"
    echo "8) Check for configuration errors"
    echo "0) Back to main menu"
    echo ""
    read -p "Select an option: " choice

    case $choice in
        1)
            print_header "VLAN Interfaces in Kernel"
            ip -d link show | grep -E "br-lan|vlan" || print_warning "No VLAN interfaces found"
            ;;
        2)
            print_header "Bridge Status"
            if command -v brctl &> /dev/null; then
                brctl show
            else
                bridge link show || print_warning "Bridge tools not available"
            fi
            ;;
        3)
            print_header "Firewall Status"
            /etc/init.d/firewall status || print_warning "Cannot get firewall status"
            ;;
        4)
            print_header "System Log (last 50 lines)"
            logread | tail -50
            ;;
        5)
            print_header "Kernel Log"
            dmesg | tail -50
            ;;
        6)
            print_header "DNS Resolution Test"
            echo "Testing DNS resolution..."
            nslookup google.com 2>/dev/null || print_error "DNS resolution failed"
            ;;
        7)
            print_header "Interface Details"
            ip -d addr show
            ;;
        8)
            print_header "Configuration Errors"
            echo "Checking for UCI syntax errors..."
            uci show network >/dev/null 2>&1 && print_success "Network config OK" || print_error "Network config has errors"
            uci show dhcp >/dev/null 2>&1 && print_success "DHCP config OK" || print_error "DHCP config has errors"
            uci show firewall >/dev/null 2>&1 && print_success "Firewall config OK" || print_error "Firewall config has errors"
            uci show wireless >/dev/null 2>&1 && print_success "Wireless config OK" || print_error "Wireless config has errors"
            ;;
        0)
            return
            ;;
        *)
            print_error "Invalid option"
            ;;
    esac

    echo ""
    read -p "Press ENTER to continue..."
}

# Main program loop
main() {
    check_openwrt

    while true; do
        show_menu

        case $choice in
            1) show_network_config ;;
            2) show_vlan_config ;;
            3) show_firewall_zones ;;
            4) show_dhcp_config ;;
            5) show_wifi_config ;;
            6) test_intervlan ;;
            7) backup_config ;;
            8) show_network_stats ;;
            9) verify_vlan_setup ;;
            10)
                print_header "Run Configuration Script"
                if [ -f "/tmp/openwrt-initial-setup.sh" ]; then
                    /tmp/openwrt-initial-setup.sh
                else
                    print_error "Script not found at /tmp/openwrt-initial-setup.sh"
                    print_info "Please upload the script first"
                fi
                ;;
            11) show_firewall_rules ;;
            12) restart_services ;;
            13) show_connected_clients ;;
            14) test_dns_config ;;
            15) show_dns_domains ;;
            16) troubleshooting_menu ;;
            0)
                print_info "Exiting..."
                exit 0
                ;;
            *)
                print_error "Invalid option"
                ;;
        esac

        echo ""
        read -p "Press ENTER to continue..."
    done
}

# Run main program
main