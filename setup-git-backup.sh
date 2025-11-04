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

# Check if git is installed
if ! command -v git >/dev/null 2>&1; then
    echo "[1/6] Installing Git..."
    apk update
    apk add git openssh-client tree
    echo "✓ Git installed"
else
    echo "[1/6] Git already installed"
fi

# Create repository directory
REPO_DIR="/root/openwrt-backup"
echo ""
echo "[2/6] Creating Git repository at $REPO_DIR..."

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
echo "[3/6] Creating backup script..."

cat > /root/backup-config.sh << 'EOFSCRIPT'
#!/bin/sh
# Automatic Router Configuration Backup Script

REPO_DIR="/root/openwrt-backup"
BACKUP_DIR="$REPO_DIR/root_dir"

# Create backup directory structure
mkdir -p "$BACKUP_DIR"

# Copy configuration files
echo "Backing up configuration files..."

# Get the list of files that sysupgrade would backup
# This includes all files marked for preservation during firmware upgrades
sysupgrade -l | while read -r file; do
    if [ -f "$file" ]; then
        # Create the directory structure in backup
        target_dir="$BACKUP_DIR/$(dirname "$file")"
        mkdir -p "$target_dir"

        # Copy the file preserving the path structure
        cp "$file" "$BACKUP_DIR$file"
        echo "  Backed up: $file"
    fi
done

# Backup installed packages list
apk list --installed > "$BACKUP_DIR/installed-packages.txt"

# Change to repo directory
cd "$REPO_DIR"

# Add all files to git (respecting .gitignore)
git add -A

# Create README with file tree using git ls-files (only tracked files)
cat > "$REPO_DIR/README.md" << EOREADME
# Router Configuration Backup

**Router:** GL.iNet Flint 2 (OpenWrt)


**Firmware:** Custom pesa1234 firmware


**Date :** $(date '+%Y-%m-%d %H:%M:%S')

## Contents

\`\`\`
EOREADME

# Generate tree structure using git ls-files (respects .gitignore)
if command -v tree >/dev/null 2>&1; then
    # Use tree command if available, strip root_dir/ prefix
    git ls-files root_dir/ | sed 's|^root_dir/||' | tree --fromfile -F --noreport >> "$REPO_DIR/README.md"
else
    # Fallback: simple sorted list with full paths, strip root_dir/ prefix
    git ls-files root_dir/ | sed 's|^root_dir/||' | sort >> "$REPO_DIR/README.md"
fi

cat >> "$REPO_DIR/README.md" << EOREADME
\`\`\`

## Package Information

Total packages installed: $(wc -l < "$BACKUP_DIR/installed-packages.txt")

See [installed-packages.txt](root_dir/installed-packages.txt) for full list.
EOREADME

# Re-add README since we just modified it
git add README.md

# Check if there are changes
if git status --porcelain | grep -q '^'; then
    
    CHANGES=$(git status --short | wc -l)
    COMMIT_MSG="Auto-backup: $CHANGES file(s) changed - $(date '+%Y-%m-%d %H:%M:%S')"
    
    git commit -m "$COMMIT_MSG"
    
    echo "✓ Committed: $COMMIT_MSG"

    # Push to remote if configured
    if git remote | grep -q 'origin'; then
        echo "Pushing to remote..."

        # Try normal push first
        if git push origin main 2>&1; then
            echo "✓ Push succeeded"
        else
            echo "⚠ Normal push failed, retrying with --force-with-lease..."

            # Try force-with-lease (safer force push)
            if git push --force-with-lease origin main 2>&1; then
                echo "✓ Force push succeeded"
            else
                echo "⚠ Force-with-lease failed, trying full force push..."

                # Last resort: force push
                if git push --force origin main 2>&1; then
                    echo "✓ Force push succeeded"
                else
                    echo "✗ All push attempts failed - check remote configuration"
                fi
            fi
        fi
    fi
else
    echo "✓ No changes detected"
fi

# Cleanup old commits (keep last 100)
COMMIT_COUNT=$(git rev-list --count HEAD 2>/dev/null || echo 0)
if [ "$COMMIT_COUNT" -gt 100 ]; then
    echo "Pruning old commits..."
    git gc --aggressive --prune=now
fi

echo "Backup complete!"
EOFSCRIPT

chmod +x /root/backup-config.sh
echo "✓ Backup script created: /root/backup-config.sh"

# Copy this setup script to the repository for reference
echo ""
echo "[3b/6] Copying setup script to repository..."
if [ -n "$0" ] && [ -f "$0" ]; then
    cp "$0" "$REPO_DIR/setup-git-backup.sh"
    echo "✓ Setup script copied to repository"
else
    echo "⚠ Could not determine script location, skipping copy"
fi

# Create .gitignore
echo ""
echo "[4/6] Creating .gitignore..."

cat > "$REPO_DIR/.gitignore" << 'EOFIGNORE'
# Ignore sensitive files
root_dir/etc/dropbear/
root_dir/etc/ssh/*_key
root_dir/etc/ssh/*_key.pub
**/*.key
**/*_key
**/*.pem
**/*.crt
**/*.csr

# Ignore logs
**/*.log
**/README
**/.placeholder

# Ignore backup files (created by UCI)
**/*.backup.*

# Ignore temporary files
**/*.tmp
EOFIGNORE

echo "✓ .gitignore created"

# Run initial backup
echo ""
echo "[5/6] Initial backup..."

if [ "$SILENT_MODE" -eq 1 ]; then
    echo "Running initial backup (silent mode)..."
    /root/backup-config.sh
else
    echo "Would you like to run an initial backup now? (y/N)"
    printf "Choice [n]: "
    read -r RUN_BACKUP

    # Default to 'y' if user just presses enter
    RUN_BACKUP=${RUN_BACKUP:-n}

    case "$RUN_BACKUP" in
        [Yy]|[Yy][Ee][Ss])
            echo "Running initial backup..."
            /root/backup-config.sh
            ;;
        *)
            echo "Skipping initial backup"
            echo "You can run it manually later with: /root/backup-config.sh"
            ;;
    esac
fi

# Set up cron job
echo ""
echo "[6/6] Setting up automatic backups..."

# Check if cron job already exists
if crontab -l 2>/dev/null | grep -q "backup-config.sh"; then
    echo "✓ Cron job already configured"
else
    # Add cron job (every 6 hours)
    (crontab -l 2>/dev/null; echo "0 */6 * * * /root/backup-config.sh >> /var/log/config-backup.log 2>&1") | crontab -
    echo "✓ Cron job added (runs every 6 hours)"
fi

# Ensure cron service is enabled and running
echo ""
echo "Ensuring cron service is running..."
if ! /etc/init.d/cron enabled 2>/dev/null; then
    /etc/init.d/cron enable
    echo "✓ Cron service enabled"
fi

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