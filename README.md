# OpenWrt Configuration Scripts for GL.iNet Flint 2

Bash script for backing up a GL.iNet Flint 2 router running OpenWrt.

**[install-autobackup.sh](install-autobackup.sh)** sets up automated git-based backup of router configuration with optional GitHub sync

## Quick Install: Git Backup System

Bootstrap the backup system directly on your router:

```bash
wget -O - https://raw.githubusercontent.com/Ogglord/openwrt-autobackup/main/install-autobackup.sh | sh
```

Or using curl:

```bash
curl -sSL https://raw.githubusercontent.com/Ogglord/openwrt-autobackup/main/install-autobackup.sh | sh
```

Unattended install:

```bash
wget -O - https://raw.githubusercontent.com/Ogglord/openwrt-autobackup/main/install-autobackup.sh | sh -s -- --silent
```


The install script will:
- Install git, openssh-client, and tree (if missing)
- Create `/root/openwrt-backup/` git repository
- Set up automated backups every 6 hours via cron
- Ensure cron service is enabled and running
- Backup all files from `sysupgrade -l` and list the installed packages
- **Note!** The backup cron job does nothing if there are no config changes

## Manual Install

```bash
cd ~
git clone https://github.com/Ogglord/openwrt-autobackup
./openwrt-autobackup/install-autobackup.sh
```

Or with silent mode:

```bash
./openwrt-autobackup/install-autobackup.sh --silent
```

---

## Other scripts in this repo:

- **[openwrt-helper.sh](openwrt-helper.sh)** - Interactive menu-driven helper tool for managing, monitoring, and troubleshooting OpenWrt configurations
- **[openwrt-initial-setup.sh](openwrt-initial-setup.sh)** - Configures multi-VLAN network with segmented zones (Management, WiFi, Services)

## Network Layout Overview

This `setup_from_scratch/openwrt-initial-setup.sh` creates a segmented network with three VLANs:

```
┌──────────────────────────────────────────────────────────┐
│                  GL.iNet Flint 2 Router                  │
│                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐    │
│  │   VLAN 99    │  │  VLAN 100    │  │   VLAN 20    │    │
│  │ Management   │  │    WiFi      │  │  Services    │    │
│  │192.168.99.1  │  │192.168.100.1 │  │192.168.20.1  │    │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘    │
│         │                 │                 │            │
│    ┌────┴─────────────────┴─────────────────┴────┐       │
│    │         Physical Port Mapping               │       │
│    │  lan1: Trunk (VLAN 99, 20 tagged)           │       │
│    │  lan2-5: VLAN 99 untagged                   │       │
│    │  WiFi radios: VLAN 100 only                 │       │
│    └─────────────────────────────────────────────┘       │
└──────────────────────────────────────────────────────────┘
         │
         │ (lan1 - Trunk port)
         ▼
┌─────────────────────┐
│  Managed Switch     │
│  VLAN 99, 20 tagged │
│  IP: 192.168.99.2   │
└─────────────────────┘
```

## VLAN Details

### VLAN 99 - Management/LAN
- **Network**: 192.168.99.0/24
- **Router IP**: 192.168.99.1
- **DHCP Range**: 192.168.99.100-250
- **Physical Ports**:
  - **lan1**: Tagged (trunk to switch)
  - **lan2-5**: Untagged

### VLAN 100 - WiFi only
- **Network**: 192.168.100.0/24
- **Router IP**: 192.168.100.1
- **DHCP Range**: 192.168.100.100-250


### VLAN 20 - Services
- **Network**: 192.168.20.0/24
- **Router IP**: 192.168.20.1
- **DHCP Range**: 192.168.20.100-250
- **Physical Ports**:
  - **lan1**: Tagged (trunk to switch)

## Firewall Configuration

### Zones and Forwarding

```
WAN Zone
  ├─> Internet access
  └─> Standard input rules (DHCP, ping, ICMPv6, etc.)

LAN Zone (VLAN 99)
  └─> Full access to all zones

WiFi Zone (VLAN 100)
  └─> WAN only (internet access)

Services Zone (VLAN 20)
  └─> WAN only (internet access)
```

## Prerequisites

Before running the configuration script:

1. **Router IP**: Set to 192.168.99.1
2. **WiFi SSIDs**: Already configured with desired names/passwords
3. **Stock OpenWrt**: Fresh or stock configuration otherwise
4. **Access**: SSH or console access to the router

## Installation

1. Copy the script to your router:
   ```bash
   scp openwrt-initial-setup.sh root@192.168.99.1:/tmp/
   ```

2. SSH into the router:
   ```bash
   ssh root@192.168.99.1
   ```

3. Make the script executable:
   ```bash
   chmod +x /tmp/openwrt-initial-setup.sh
   ```

4. Run the script:
   ```bash
   /tmp/openwrt-initial-setup.sh
   ```

5. Review the configuration summary and press ENTER to apply

## What the Script Does

1. **Backup**: Creates timestamped backups of network, DHCP, and firewall configs
2. **Network**: Configures bridge VLANs and interfaces for all three networks
3. **DHCP**: Sets up DHCP servers for each VLAN with appropriate ranges
4. **Firewall**: Completely rebuilds firewall from scratch with proper zones
5. **Wireless**: Attaches WiFi radios to VLAN 100
6. **Apply**: Commits changes and restarts services

## OpenWrt Helper Tool

The [openwrt-helper.sh](openwrt-helper.sh) script provides an interactive menu-driven interface for managing, monitoring, and troubleshooting your OpenWrt router configuration. It's particularly useful after running the initial setup script to verify and maintain your network.

### Using the Helper

1. Copy the helper script to your router:
   ```bash
   scp openwrt-helper.sh root@192.168.99.1:/tmp/
   ```

2. SSH into the router and run it:
   ```bash
   ssh root@192.168.99.1
   chmod +x /tmp/openwrt-helper.sh
   /tmp/openwrt-helper.sh
   ```

### Available Features

The helper provides 16+ menu options organized into categories:

**Configuration Viewing**:
- Show current network configuration (interfaces, IP addresses, bridges)
- Show VLAN configuration with detailed port mappings
- Show firewall zones and forwarding rules
- Show DHCP configuration and active leases
- Show WiFi configuration and status

**Network Monitoring**:
- Show network statistics (interface stats, routing table, active connections)
- Show connected clients (DHCP leases and ARP table)
- Show DNS domains and leases by VLAN
- Test DNS configuration and resolution

**Testing & Verification**:
- Test inter-VLAN connectivity (ping tests between VLANs)
- Verify VLAN setup (checks for proper configuration)
- Test DNS resolution for local and external domains

**Maintenance**:
- Backup current configuration (timestamped backups)
- Restart network services (firewall, network, dnsmasq)
- Run full configuration from script

**Troubleshooting Menu**:
- Check if VLANs are in kernel
- Show bridge status
- Check firewall status
- Show system log and kernel log
- Show interface details
- Check for configuration errors



## Post-Installation

### Switch Configuration
After running the script, configure your managed switch:

1. Connect switch uplink to router's **lan1** port
2. Configure switch with VLANs 99 and 20:
   - Uplink port: Tagged for VLAN 99 and 20
   - Access ports: Untagged for appropriate VLANs
3. Set switch management IP to 192.168.99.2
4. Set default gateway to 192.168.99.1

### Verification

Test connectivity:
```bash
# From LAN (192.168.99.x)
ping 192.168.99.1    # Router LAN interface
ping 192.168.100.1   # Router WiFi interface
ping 192.168.20.1    # Router Services interface
ping 8.8.8.8         # Internet

# From WiFi (192.168.100.x)
ping 192.168.100.1   # Should work
ping 192.168.99.1    # Should fail (blocked by firewall)

# From Services (192.168.20.x)
ping 192.168.20.1    # Should work
ping 192.168.99.1    # Should fail (blocked by firewall)
```

## Recovery

If something goes wrong, backups are located at:
- `/etc/config/network.backup.YYYYMMDD_HHMMSS`
- `/etc/config/dhcp.backup.YYYYMMDD_HHMMSS`
- `/etc/config/firewall.backup.YYYYMMDD_HHMMSS`

To restore:
```bash
cp /etc/config/network.backup.XXXXXXXX_XXXXXX /etc/config/network
cp /etc/config/dhcp.backup.XXXXXXXX_XXXXXX /etc/config/dhcp
cp /etc/config/firewall.backup.XXXXXXXX_XXXXXX /etc/config/firewall
/etc/init.d/network restart
/etc/init.d/firewall restart
/etc/init.d/dnsmasq restart
```

## Use Cases

### Example Device Placement

**VLAN 99 (Management/LAN)**:
- Admin devices
- Managed switch

**VLAN 100 (WiFi)**:
- Laptops
- Phones
- Tablets
- Guests

**VLAN 20 (Services)**:
- Docker containers
- Plex Media Server / *arr apps
- IoT devices
- Security cameras
- Homeassistant

## Security Considerations

- WiFi clients are isolated from wired networks
- Services network is isolated from management network
- Only LAN zone has full access
- All zones can reach internet
- Firewall drops invalid packets and enables SYN flood protection

## Customization

To modify the configuration:
- Edit IP ranges in the script before running
- Adjust firewall rules for specific access requirements
- Change DHCP ranges and lease times as needed
- Add additional VLANs by following the existing pattern