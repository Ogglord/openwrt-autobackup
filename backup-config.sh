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
    # Skip files within the backup repository directory to avoid recursion
    case "$file" in
        "$REPO_DIR"|"$REPO_DIR"/*)
            echo "  INFO: Excluding repository directory: $file"
            continue
            ;;
    esac
    
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
# OpenWrt Configuration Backup

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

## Restoring Files

To restore a single file from a specific commit:

\`\`\`bash
git show <commit>:root_dir/etc/config/network > /etc/config/network
\`\`\`

Replace \`<commit>\` with the commit hash and adjust the file path as needed.
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

