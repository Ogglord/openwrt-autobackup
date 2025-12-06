#!/bin/sh
# Quick Setup Script for Router Configuration Git Backup
# Run this on your GL.iNet Flint 2 router
###
### PACKAGES REQUIRED: git openssh-client tree
###
### Usage: ./setup-git-backup.sh [--silent]
###   --silent    Skip prompts and run initial backup automatically

set -e

# Parse arguments
SILENT_MODE=0
for arg in "$@"; do
    case "$arg" in
        --silent)
            SILENT_MODE=1
            ;;
        --help|-h)
            echo "Usage: $0 [--silent]"
            echo ""
            echo "Options:"
            echo "  --silent    Skip prompts and run initial backup automatically"
            echo "  --help      Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo "=========================================="
echo "Router Configuration Git Backup Setup"
echo "=========================================="
echo ""

# Function to determine installer directory (cached)
_get_installer_dir() {
    if [ -z "${_INSTALLER_DIR:-}" ]; then
        if [ -f "$0" ] && [ "$0" != "-" ] && [ "$0" != "/dev/stdin" ]; then
            if [ "$(dirname "$0")" != "." ]; then
                _INSTALLER_DIR="$(cd "$(dirname "$0")" && pwd)"
            else
                _INSTALLER_DIR="$(pwd)"
            fi
        else
            _INSTALLER_DIR=""
        fi
    fi
    echo "$_INSTALLER_DIR"
}

# Function to get a file from local directory or GitHub
# Usage: _get_file <filename> [required]
# Returns path to file on success, exits on failure if required=true
_get_file() {
    local filename="$1"
    local required="${2:-true}"
    local installer_dir
    local temp_file="/tmp/$filename"
    local github_repo="${GITHUB_REPO:-ogge/openwrt-autobackup}"
    local github_branch="${GITHUB_BRANCH:-main}"
    local github_url="https://raw.githubusercontent.com/${github_repo}/${github_branch}/${filename}"
    
    installer_dir="$(_get_installer_dir)"
    
    # Try local file first
    if [ -n "$installer_dir" ] && [ -f "$installer_dir/$filename" ]; then
        echo "$installer_dir/$filename"
        return 0
    fi
    
    # Not found locally, try to download from GitHub
    if [ -z "$installer_dir" ] || [ ! -f "$installer_dir/$filename" ]; then
        if [ "$required" = "true" ]; then
            echo "  Downloading $filename from GitHub..." >&2
        fi
        
        if command -v wget >/dev/null 2>&1; then
            if wget -q -O "$temp_file" "$github_url" 2>/dev/null; then
                if [ "$required" = "true" ]; then
                    echo "  ✓ Downloaded from GitHub" >&2
                fi
                echo "$temp_file"
                return 0
            fi
        elif command -v curl >/dev/null 2>&1; then
            if curl -sSLf -o "$temp_file" "$github_url" 2>/dev/null; then
                if [ "$required" = "true" ]; then
                    echo "  ✓ Downloaded from GitHub" >&2
                fi
                echo "$temp_file"
                return 0
            fi
        fi
    fi
    
    # Failed to get file
    if [ "$required" = "true" ]; then
        echo "✗ Error: $filename not found locally and download from GitHub failed" >&2
        echo "  URL: $github_url" >&2
        echo "  You can set GITHUB_REPO environment variable to specify a different repository" >&2
        echo "  Example: GITHUB_REPO=username/repo $0" >&2
        exit 1
    fi
    
    return 1
}

# Check if git is installed
if ! command -v git >/dev/null 2>&1; then
    echo "[1/5] Installing Git..."
    apk update
    apk add git openssh-client tree
    echo "✓ Git installed"
else
    echo "[1/5] Git already installed"
fi

# Create repository directory
REPO_DIR="/root/openwrt-backup"
echo ""
echo "[2/5] Creating Git repository at $REPO_DIR..."

mkdir -p "$REPO_DIR"
cd "$REPO_DIR"

if [ ! -d .git ]; then
    git init
    git branch -M main
    git config user.name "GL.iNet Flint 2"
    git config user.email "router@openwrt.lan"
    git config init.defaultBranch main
    echo "✓ Git repository initialized"
else
    echo "✓ Git repository already exists"
fi

# Create backup script
echo ""
echo "[3/5] Installing backup script..."

BACKUP_SCRIPT_SOURCE="$(_get_file backup-config.sh)"
cp "$BACKUP_SCRIPT_SOURCE" /root/backup-config.sh
chmod +x /root/backup-config.sh
echo "✓ Backup script installed: /root/backup-config.sh"

# Cleanup temp file if we downloaded it
if [ "$BACKUP_SCRIPT_SOURCE" = "/tmp/backup-config.sh" ]; then
    rm -f /tmp/backup-config.sh
fi
# Create .gitignore
echo ""
echo "[4/5] Creating .gitignore..."

GITIGNORE_SOURCE="$(_get_file example.gitignore)"
cp "$GITIGNORE_SOURCE" "$REPO_DIR/.gitignore"
echo "✓ .gitignore created"

# Cleanup temp file if we downloaded it
if [ "$GITIGNORE_SOURCE" = "/tmp/example.gitignore" ]; then
    rm -f /tmp/example.gitignore
fi

# Set up cron job
echo ""
echo "[5/5] Setting up automatic backups..."

# Check if cron job already exists
if crontab -l 2>/dev/null | grep -q "backup-config.sh"; then
    echo "✓ Cron job already configured"
else
    # Add cron job (every 6 hours)
    { crontab -l 2>/dev/null || true; echo "0 */6 * * * /root/backup-config.sh >> /var/log/config-backup.log 2>&1"; } | crontab -
    echo "✓ Cron job added (runs every 6 hours)"
fi

# Ensure cron service is enabled and running
echo ""
echo "Ensuring cron service is running..."

# Enable cron service
/etc/init.d/cron enable 2>/dev/null
echo "✓ Cron service enabled"

# Start cron if not running
if ! ps | grep -v grep | grep -q crond; then
    /etc/init.d/cron start
    echo "✓ Cron service started"
else
    echo "✓ Cron service already running"
fi

# Verify cron is actually running
if ps | grep -v grep | grep -q crond; then
    echo "✓ Cron service verified running"
else
    echo "⚠ WARNING: Cron service may not be running properly"
    echo "  Try manually: /etc/init.d/cron start"
fi


# Check if repo already has a remote configured
cd "$REPO_DIR"
if git remote | grep -q 'origin'; then
    echo "=========================================="
    echo "Update Complete!"
    echo "=========================================="
    REMOTE_URL=$(git remote get-url origin 2>/dev/null)
    echo "✓ Git remote already configured: $REMOTE_URL"    
    echo ""
    echo "To manually run a backup: /root/backup-config.sh"
    echo "To view backup log: tail -f /var/log/config-backup.log"
    echo "=========================================="
else
    # Summary
    echo ""
    echo "=========================================="
    echo "Setup Complete!"
    echo "=========================================="
    echo ""
    echo "✓ Git repository: $REPO_DIR"
    echo "✓ Backup script: /root/backup-config.sh"
    echo "✓ Automatic backups: Every 6 hours"
    echo "✓ Initial backup: Done"
    echo ""
    echo "Next steps:"
    echo ""
    echo "  1. Install SSH client (for ssh-keygen):"
    echo "     apk add openssh-client"
    echo ""
    echo "  2. Generate SSH key for GitHub:"
    echo "     ssh-keygen -t ed25519 -C \"router@openwrt.lan\" -f /root/.ssh/github_router"
    echo "     # Press Enter to accept defaults (no passphrase recommended for automation)"
    echo ""
    echo "  3. Display your public key:"
    echo "     cat /root/.ssh/github_router.pub"
    echo "     # Copy the entire output"
    echo ""
    echo "  4. Add the SSH key to GitHub:"
    echo "     - Go to: https://github.com/settings/ssh/new"
    echo "     - Title: \"OpenWrt Router Backup\""
    echo "     - Key type: Authentication Key"
    echo "     - Paste the public key from step 3"
    echo "     - Click \"Add SSH key\""
    echo ""
    echo "  5. Configure SSH to use the key:"
    echo "     mkdir -p /root/.ssh"
    echo "     cat >> /root/.ssh/config << 'EOFSSH'"
    echo "Host github.com"
    echo "  HostName github.com"
    echo "  User git"
    echo "  IdentityFile /root/.ssh/github_router"
    echo "  StrictHostKeyChecking accept-new"
    echo "EOFSSH"
    echo ""
    echo "  6. Create a private GitHub repository:"
    echo "     - Go to: https://github.com/new"
    echo "     - Name: router-config (or your choice)"
    echo "     - Set to Private (recommended for router configs)"
    echo "     - Do NOT initialize with README, .gitignore, or license"
    echo ""
    echo "  7. Set up remote and push:"
    echo "     cd $REPO_DIR"
    echo "     git branch -M main  # Rename branch to main if needed"
    echo "     git remote add origin git@github.com:username/openwrt-backup.git"
    echo "     git push -u origin main"
    echo ""
    echo "  8. View backup history:"
    echo "     cd $REPO_DIR && git log --oneline"
    echo ""
    echo "  9. Manual backup anytime:"
    echo "     /root/backup-config.sh"
    echo ""
    echo "  10. View backup log:"
    echo "     tail -f /var/log/config-backup.log"
    echo ""
    echo "=========================================="
fi
