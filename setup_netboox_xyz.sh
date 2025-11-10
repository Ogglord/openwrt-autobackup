#!/bin/sh
#
# netboot.xyz Setup Script for OpenWrt
# This script configures TFTP server and downloads netboot.xyz files
#

set -e

TFTP_ROOT="/tmp/tftp"
NETBOOT_VERSION="2.0.80"  # Latest stable version as of script creation
NETBOOT_BASE_URL="https://boot.netboot.xyz/ipxe"

echo "=== netboot.xyz Setup for OpenWrt ==="
echo ""

# Function to check if a package is installed
check_package() {
    apk list -I | grep -q "^$1-"
}

# Install required packages
echo "[1/6] Checking and installing required packages..."
apk update

if ! check_package "dnsmasq-full"; then
    echo "Installing dnsmasq-full (replacing dnsmasq)..."
    # Remove standard dnsmasq and install dnsmasq-full for TFTP support
    apk del dnsmasq
    apk add dnsmasq-full
else
    echo "dnsmasq-full already installed"
fi

if ! check_package "wget"; then
    echo "Installing wget..."
    apk add wget
else
    echo "wget already installed"
fi

# Create TFTP directory
echo ""
echo "[2/6] Creating TFTP directory structure..."
mkdir -p "$TFTP_ROOT"
chmod 755 "$TFTP_ROOT"

# Download netboot.xyz files
echo ""
echo "[3/6] Downloading netboot.xyz files..."

# BIOS/Legacy boot files
echo "Downloading BIOS boot files..."
wget -O "$TFTP_ROOT/netboot.xyz.kpxe" "$NETBOOT_BASE_URL/netboot.xyz.kpxe" || {
    echo "Error: Failed to download netboot.xyz.kpxe"
    exit 1
}

wget -O "$TFTP_ROOT/netboot.xyz-undionly.kpxe" "$NETBOOT_BASE_URL/netboot.xyz-undionly.kpxe" || {
    echo "Warning: Failed to download netboot.xyz-undionly.kpxe"
}

# UEFI boot files
echo "Downloading UEFI boot files..."
wget -O "$TFTP_ROOT/netboot.xyz.efi" "$NETBOOT_BASE_URL/netboot.xyz.efi" || {
    echo "Error: Failed to download netboot.xyz.efi"
    exit 1
}

wget -O "$TFTP_ROOT/netboot.xyz-arm64.efi" "$NETBOOT_BASE_URL/netboot.xyz-arm64.efi" || {
    echo "Warning: Failed to download netboot.xyz-arm64.efi (ARM64 support)"
}

# Set permissions
chmod 644 "$TFTP_ROOT"/*

echo "Downloaded files:"
ls -lh "$TFTP_ROOT"

# Configure dnsmasq for TFTP and PXE
echo ""
echo "[4/6] Configuring dnsmasq for TFTP and PXE boot..."

# Backup existing dnsmasq config
if [ -f /etc/config/dhcp ]; then
    cp /etc/config/dhcp /etc/config/dhcp.backup.$(date +%Y%m%d_%H%M%S)
fi

# Check if dnsmasq section exists, create if it doesn't
if ! uci get dhcp.@dnsmasq[0] >/dev/null 2>&1; then
    echo "Creating dnsmasq section..."
    uci add dhcp dnsmasq
    uci commit dhcp
fi

# Add TFTP configuration to dnsmasq
# Enable TFTP server
echo "Enabling TFTP server..."
uci set dhcp.@dnsmasq[0].enable_tftp='1' || {
    echo "Error: Failed to set enable_tftp"
    exit 1
}

echo "Setting TFTP root directory..."
uci set dhcp.@dnsmasq[0].tftp_root="$TFTP_ROOT" || {
    echo "Error: Failed to set tftp_root"
    exit 1
}

# Optional: Set up different boot files for UEFI and BIOS
# This uses dnsmasq's ability to detect client architecture
# First, remove any existing dhcp_match and dhcp_boot entries
echo "Cleaning up existing boot configuration..."
uci -q delete dhcp.@dnsmasq[0].dhcp_match || true
uci -q delete dhcp.@dnsmasq[0].dhcp_boot || true

# Add architecture matching rules
echo "Configuring architecture matching rules..."
uci add_list dhcp.@dnsmasq[0].dhcp_match='set:efi-x86_64,option:client-arch,7' || {
    echo "Error: Failed to add dhcp_match for efi-x86_64 (arch 7)"
    exit 1
}
uci add_list dhcp.@dnsmasq[0].dhcp_match='set:efi-x86_64,option:client-arch,9' || {
    echo "Error: Failed to add dhcp_match for efi-x86_64 (arch 9)"
    exit 1
}
uci add_list dhcp.@dnsmasq[0].dhcp_match='set:efi-x86,option:client-arch,6' || {
    echo "Error: Failed to add dhcp_match for efi-x86"
    exit 1
}
uci add_list dhcp.@dnsmasq[0].dhcp_match='set:bios,option:client-arch,0' || {
    echo "Error: Failed to add dhcp_match for bios"
    exit 1
}
uci add_list dhcp.@dnsmasq[0].dhcp_match='set:efi-arm64,option:client-arch,11' || {
    echo "Error: Failed to add dhcp_match for efi-arm64"
    exit 1
}

# Set boot files based on architecture (using list format for LuCI compatibility)
echo "Configuring boot files for each architecture..."
uci add_list dhcp.@dnsmasq[0].dhcp_boot='tag:efi-x86_64,netboot.xyz.efi' || {
    echo "Error: Failed to add dhcp_boot for efi-x86_64"
    exit 1
}
uci add_list dhcp.@dnsmasq[0].dhcp_boot='tag:efi-x86,netboot.xyz.efi' || {
    echo "Error: Failed to add dhcp_boot for efi-x86"
    exit 1
}
uci add_list dhcp.@dnsmasq[0].dhcp_boot='tag:bios,netboot.xyz.kpxe' || {
    echo "Error: Failed to add dhcp_boot for bios"
    exit 1
}
uci add_list dhcp.@dnsmasq[0].dhcp_boot='tag:efi-arm64,netboot.xyz-arm64.efi' || {
    echo "Error: Failed to add dhcp_boot for efi-arm64"
    exit 1
}

echo "Committing DHCP configuration..."
uci commit dhcp || {
    echo "Error: Failed to commit DHCP configuration"
    exit 1
}

# Configure firewall to allow TFTP
echo ""
echo "[5/6] Configuring firewall for TFTP..."

# Allow TFTP from lan zone
if ! uci show firewall | grep -q "name='Allow-TFTP-lan'"; then
    uci add firewall rule
    uci set firewall.@rule[-1].name='Allow-TFTP-lan'
    uci set firewall.@rule[-1].src='lan'
    uci set firewall.@rule[-1].proto='udp'
    uci set firewall.@rule[-1].dest_port='69'
    uci set firewall.@rule[-1].target='ACCEPT'
    echo "Firewall rule added for TFTP (lan zone)"
else
    echo "TFTP firewall rule for lan already exists"
fi

# Allow TFTP from services zone (VLAN 20)
if ! uci show firewall | grep -q "name='Allow-TFTP-services'"; then
    uci add firewall rule
    uci set firewall.@rule[-1].name='Allow-TFTP-services'
    uci set firewall.@rule[-1].src='services'
    uci set firewall.@rule[-1].proto='udp'
    uci set firewall.@rule[-1].dest_port='69'
    uci set firewall.@rule[-1].target='ACCEPT'
    echo "Firewall rule added for TFTP (services zone)"
else
    echo "TFTP firewall rule for services already exists"
fi

# Allow TFTP from wifi zone (VLAN 100)
if ! uci show firewall | grep -q "name='Allow-TFTP-wifi'"; then
    uci add firewall rule
    uci set firewall.@rule[-1].name='Allow-TFTP-wifi'
    uci set firewall.@rule[-1].src='wifi'
    uci set firewall.@rule[-1].proto='udp'
    uci set firewall.@rule[-1].dest_port='69'
    uci set firewall.@rule[-1].target='ACCEPT'
    echo "Firewall rule added for TFTP (wifi zone)"
else
    echo "TFTP firewall rule for wifi already exists"
fi

uci commit firewall
/etc/init.d/firewall reload

# Restart services
echo ""
echo "[6/6] Restarting services..."
/etc/init.d/dnsmasq restart

# Verify TFTP configuration
echo ""
echo "Verifying TFTP configuration..."
if uci get dhcp.@dnsmasq[0].enable_tftp 2>/dev/null | grep -q '1'; then
    echo "✓ TFTP is enabled"
    TFTP_ROOT_VERIFY=$(uci get dhcp.@dnsmasq[0].tftp_root 2>/dev/null)
    echo "✓ TFTP root directory: $TFTP_ROOT_VERIFY"
    if [ -d "$TFTP_ROOT_VERIFY" ]; then
        FILE_COUNT=$(ls -1 "$TFTP_ROOT_VERIFY"/*.kpxe "$TFTP_ROOT_VERIFY"/*.efi 2>/dev/null | wc -l)
        echo "✓ TFTP files found: $FILE_COUNT"
    else
        echo "⚠ Warning: TFTP root directory does not exist: $TFTP_ROOT_VERIFY"
    fi
else
    echo "✗ Error: TFTP is not enabled in configuration"
fi

echo ""
echo "=== Setup Complete! ==="
echo ""
echo "netboot.xyz has been configured successfully!"
echo ""
echo "TFTP Root: $TFTP_ROOT"
echo "Files available:"
echo "  - netboot.xyz.kpxe (BIOS/Legacy)"
echo "  - netboot.xyz.efi (UEFI x86_64)"
echo "  - netboot.xyz-arm64.efi (UEFI ARM64)"
echo ""
echo "Firewall rules added for zones: lan, services (VLAN 20), wifi (VLAN 100)"
echo ""
echo "To test PXE boot:"
echo "1. Configure your client machine to boot from network (PXE)"
echo "2. Ensure the client is connected to one of your networks:"
echo "   - LAN (VLAN 99 - mgmt)"
echo "   - Services (VLAN 20)"
echo "   - WiFi (VLAN 100)"
echo "3. Boot the client - it should load netboot.xyz"
echo ""
echo "IMPORTANT: Files in /tmp will be lost on reboot!"
echo "For persistent storage on OpenWrt snapshot, you should:"
echo "  1. Move files to /root/tftp or /etc/tftp"
echo "  2. Update uci tftp_root: uci set dhcp.@dnsmasq[0].tftp_root='/root/tftp'"
echo "  3. Add download commands to /etc/rc.local to run on boot"
echo ""
echo "Viewing TFTP Configuration in LuCI:"
echo "  1. Go to: Network > DHCP and DNS"
echo "  2. Click on the 'Advanced Settings' tab"
echo "  3. Look for 'TFTP Settings' section"
echo "  4. You should see:"
echo "     - Enable TFTP server: ✓ (checked)"
echo "     - TFTP root: $TFTP_ROOT"
echo "     - DHCP boot options: (list of boot files by architecture)"
echo ""
echo "If TFTP settings don't appear in LuCI:"
echo "  1. Refresh the page (Ctrl+F5 or Cmd+Shift+R)"
echo "  2. Check: uci show dhcp.@dnsmasq[0] | grep tftp"
echo "  3. Restart dnsmasq: /etc/init.d/dnsmasq restart"
echo ""
echo "=== Testing PXE Boot ==="
echo ""
echo "IMPORTANT: PXE boot requires Ethernet connection!"
echo "  - Standard PXE specification does NOT support WiFi"
echo "  - ThinkPad T470s and most laptops only support PXE over Ethernet"
echo "  - If your laptop lacks Ethernet port, use a USB-to-Ethernet adapter"
echo "  - WiFi PXE is extremely rare and not supported on T470s"
echo ""
echo "For ThinkPad T470s (or similar):"
echo "  1. Connect laptop to router via Ethernet cable (REQUIRED)"
echo "  2. Power on and press F1 to enter BIOS/UEFI settings"
echo "  3. Go to: Startup > Boot Priority"
echo "  4. Enable 'Network Boot' or 'PXE Boot'"
echo "  5. Move 'Network Boot' to top of boot order (or use F12 boot menu)"
echo "  6. Save and exit"
echo "  7. Power on - it should boot from network"
echo ""
echo "Note: Firewall rules are configured for WiFi zone, but PXE boot"
echo "      will only work over Ethernet. WiFi rules are for future-proofing."
echo ""
echo "=== Debugging on Router ==="
echo ""
echo "Enable dnsmasq query logging (recommended for debugging):"
echo "  uci set dhcp.@dnsmasq[0].logqueries='1'"
echo "  uci commit dhcp"
echo "  /etc/init.d/dnsmasq restart"
echo ""
echo "Monitor dnsmasq logs in real-time:"
echo "  logread -f | grep dnsmasq"
echo ""
echo "Or view recent dnsmasq logs:"
echo "  logread | grep dnsmasq | tail -50"
echo ""
echo "Check if dnsmasq is running and listening:"
echo "  ps | grep dnsmasq"
echo "  netstat -ulnp | grep :67"
echo "  netstat -ulnp | grep :69"
echo ""
echo "Monitor DHCP/TFTP traffic (in separate terminal):"
echo "  tcpdump -i any -n port 67 or port 68 or port 69"
echo ""
echo "Check DHCP leases:"
echo "  cat /tmp/dhcp.leases"
echo ""
echo "Verify TFTP files are accessible:"
echo "  ls -lh $TFTP_ROOT"
echo "  file $TFTP_ROOT/*.kpxe $TFTP_ROOT/*.efi"
echo ""
echo "Test TFTP server manually (from another machine):"
echo "  tftp <router-ip>"
echo "  > get netboot.xyz.kpxe"
echo "  > quit"
echo ""
echo "Check current TFTP configuration:"
echo "  uci show dhcp.@dnsmasq[0] | grep -E '(tftp|boot)'"
echo ""
echo "=== Troubleshooting PXE Timeout ==="
echo ""
echo "If PXE starts but times out (like 'Start PXE over IPv4' then nothing):"
echo ""
echo "1. Check if TFTP files exist and are readable:"
echo "   ls -lh /tmp/tftp/"
echo "   test -r /tmp/tftp/netboot.xyz.kpxe && echo 'kpxe readable' || echo 'kpxe NOT readable'"
echo "   test -r /tmp/tftp/netboot.xyz.efi && echo 'efi readable' || echo 'efi NOT readable'"
echo ""
echo "2. Check dnsmasq is actually running TFTP:"
echo "   ps aux | grep dnsmasq"
echo "   cat /var/etc/dnsmasq.conf | grep -i tftp"
echo ""
echo "3. Test TFTP from router itself:"
echo "   tftp localhost"
echo "   > get netboot.xyz.kpxe /tmp/test.kpxe"
echo "   > quit"
echo "   ls -lh /tmp/test.kpxe"
echo ""
echo "4. Check for architecture mismatch (UEFI vs BIOS):"
echo "   - T470s in UEFI mode needs: netboot.xyz.efi"
echo "   - T470s in Legacy/BIOS mode needs: netboot.xyz.kpxe"
echo "   - Try setting a simple boot file first:"
echo "     uci -q delete dhcp.@dnsmasq[0].dhcp_match"
echo "     uci -q delete dhcp.@dnsmasq[0].dhcp_boot"
echo "     uci set dhcp.@dnsmasq[0].dhcp_boot='netboot.xyz.kpxe'"
echo "     uci commit dhcp"
echo "     /etc/init.d/dnsmasq restart"
echo ""
echo "5. Check firewall isn't blocking (should see TFTP in logs if blocked):"
echo "   logread | grep -i 'tftp\|69'"
echo ""
echo "6. Verify dnsmasq-full has TFTP support:"
echo "   dnsmasq --test 2>&1 | grep -i tftp"
echo ""
echo "7. Check dnsmasq error log:"
echo "   logread | grep -i 'dnsmasq.*error\|dnsmasq.*fail'"
echo ""
echo "8. Try simpler configuration (single boot file, no architecture matching):"
echo "   uci -q delete dhcp.@dnsmasq[0].dhcp_match"
echo "   uci -q delete dhcp.@dnsmasq[0].dhcp_boot"
echo "   uci set dhcp.@dnsmasq[0].enable_tftp='1'"
echo "   uci set dhcp.@dnsmasq[0].tftp_root='/tmp/tftp'"
echo "   uci set dhcp.@dnsmasq[0].dhcp_boot='netboot.xyz.kpxe'"
echo "   uci commit dhcp"
echo "   /etc/init.d/dnsmasq restart"
echo ""
echo "Configuration backup saved to /etc/config/dhcp.backup.*"