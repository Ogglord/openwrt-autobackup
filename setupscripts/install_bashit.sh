#!/bin/bash

# Bash-it Installation and Configuration Script
# Installs Bash-it with specified plugins and theme

set -e  # Exit on error

echo "================================================"
echo "Bash-it Installation Script"
echo "================================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if Bash-it is already installed
if [ -d "$HOME/.bash_it" ]; then
    echo -e "${YELLOW}Bash-it directory already exists at $HOME/.bash_it${NC}"
    read -p "Do you want to remove it and reinstall? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Removing existing Bash-it installation..."
        rm -rf "$HOME/.bash_it"
    else
        echo "Exiting. Remove $HOME/.bash_it manually if you want to reinstall."
        exit 1
    fi
fi

# Clone Bash-it repository
echo -e "${GREEN}Cloning Bash-it repository...${NC}"
git clone --depth=1 https://github.com/Bash-it/bash-it.git "$HOME/.bash_it"

# Install Bash-it
echo -e "${GREEN}Installing Bash-it...${NC}"
"$HOME/.bash_it/install.sh" --silent --no-modify-config

# Enable specified plugins
echo -e "${GREEN}Enabling plugins...${NC}"
PLUGINS=(
    "base"
    "xterm"
    "git"
    "ssh"
    "zoxide"
    "history-eternal"
    "history"
    "history-search"
    "history-substring-search"
)

for plugin in "${PLUGINS[@]}"; do
    echo "  - Enabling plugin: $plugin"
    bash-it enable plugin "$plugin" 2>/dev/null || echo -e "${YELLOW}    Warning: Plugin '$plugin' not found or already enabled${NC}"
done

# Set theme to metal
echo -e "${GREEN}Setting theme to 'metal'...${NC}"
bash-it enable theme metal 2>/dev/null || echo -e "${YELLOW}Warning: Theme 'metal' not found${NC}"

# Add Bash-it initialization to .bashrc if not already present
if ! grep -q "bash_it.sh" "$HOME/.bashrc"; then
    echo -e "${GREEN}Adding Bash-it to .bashrc...${NC}"
    cat >> "$HOME/.bashrc" << 'EOF'

# Load Bash-it
export BASH_IT="$HOME/.bash_it"
export BASH_IT_THEME='metal'
source "$BASH_IT/bash_it.sh"
EOF
else
    echo -e "${YELLOW}Bash-it already configured in .bashrc${NC}"
fi

# Check if zoxide is installed
if ! command -v zoxide &> /dev/null; then
    echo -e "${YELLOW}Warning: zoxide is not installed.${NC}"
    echo "The zoxide plugin requires zoxide to be installed."
    echo "Install it with: curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash"
fi

echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}Bash-it installation complete!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo "Enabled plugins:"
for plugin in "${PLUGINS[@]}"; do
    echo "  - $plugin"
done
echo ""
echo "Theme: metal"
echo ""
echo -e "${YELLOW}To apply changes, run:${NC}"
echo "  source ~/.bashrc"
echo ""
echo -e "${YELLOW}Or restart your terminal${NC}"
echo ""
echo "Your original .bashrc was backed up to: ~/.bashrc.backup"