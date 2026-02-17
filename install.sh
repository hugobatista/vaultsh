#!/bin/bash
set -euo pipefail

# vaultsh installer
# Installs vaultsh to system-wide or user-local bin directory

# Colors for output
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
	GREEN="$(tput setaf 2)"
	YELLOW="$(tput setaf 3)"
	RED="$(tput setaf 1)"
	CYAN="$(tput setaf 6)"
	BOLD="$(tput bold)"
	RESET="$(tput sgr0)"
else
	GREEN=""
	YELLOW=""
	RED=""
	CYAN=""
	BOLD=""
	RESET=""
fi

info() {
	echo "${CYAN}➜${RESET} $*"
}

success() {
	echo "${GREEN}✓${RESET} $*"
}

warning() {
	echo "${YELLOW}⚠${RESET} $*"
}

error() {
	echo "${RED}✗${RESET} $*" >&2
}

header() {
	echo ""
	echo "${BOLD}${CYAN}$*${RESET}"
	echo ""
}

header "vaultsh Installer"

REPO_URL="https://go.hugobatista.com/gh/vaultsh"
REPO_DIR="vaultsh-repo-$$"
CLEANUP_REPO=false

# Check if we're in the right directory or need to clone the repo
if [[ ! -f "vault.sh" ]]; then
	info "Cloning vaultsh repository..."
	if ! git clone --depth 1 "$REPO_URL" "$REPO_DIR" 2>/dev/null; then
		error "Failed to clone repository. Make sure git is installed."
		exit 1
	fi
	cd "$REPO_DIR"
	CLEANUP_REPO=true
	success "Repository cloned"
fi

# Check for bash
info "Checking for bash..."
if ! command -v bash >/dev/null 2>&1; then
	error "bash not found. Please install bash first."
	exit 1
fi
success "bash found: $(bash --version | head -n1)"

# Check for secret-tool dependency
info "Checking for secret-tool..."
if ! command -v secret-tool >/dev/null 2>&1; then
	warning "secret-tool not found"
	echo ""
	echo "  vaultsh requires secret-tool from the libsecret-tools package."
	echo "  Please install it using your package manager:"
	echo ""
	echo "    ${BOLD}Fedora/RHEL:${RESET}    sudo dnf install libsecret-tools"
	echo "    ${BOLD}Ubuntu/Debian:${RESET}  sudo apt install libsecret-tools"
	echo "    ${BOLD}Arch Linux:${RESET}     sudo pacman -S libsecret"
	echo "    ${BOLD}openSUSE:${RESET}       sudo zypper install libsecret-tools"
	echo ""
	read -p "Continue anyway? (y/N) " -n 1 -r
	echo
	if [[ ! $REPLY =~ ^[Yy]$ ]]; then
		error "Installation cancelled"
		exit 1
	fi
else
	success "secret-tool found"
fi

# Determine installation location
header "Choose Installation Location"

echo "  1) ${BOLD}System-wide${RESET}  → /usr/local/bin/vaultsh (requires sudo)"
echo "  2) ${BOLD}User-local${RESET}   → ~/.local/bin/vaultsh (no sudo needed)"
echo ""

while true; do
	read -p "Enter choice [1-2]: " choice
	case $choice in
		1)
			INSTALL_DIR="/usr/local/bin"
			NEEDS_SUDO=true
			break
			;;
		2)
			INSTALL_DIR="$HOME/.local/bin"
			NEEDS_SUDO=false
			break
			;;
		*)
			warning "Invalid choice. Please enter 1 or 2."
			;;
	esac
done

TARGET_FILE="$INSTALL_DIR/vaultsh"

# Check if target already exists
if [[ -f "$TARGET_FILE" ]]; then
	warning "vaultsh already exists at $TARGET_FILE"
	read -p "Overwrite? (y/N) " -n 1 -r
	echo
	if [[ ! $REPLY =~ ^[Yy]$ ]]; then
		error "Installation cancelled"
		exit 1
	fi
fi

# Create directory if it doesn't exist
if [[ ! -d "$INSTALL_DIR" ]]; then
	info "Creating directory: $INSTALL_DIR"
	if [[ "$NEEDS_SUDO" == true ]]; then
		sudo mkdir -p "$INSTALL_DIR"
	else
		mkdir -p "$INSTALL_DIR"
	fi
fi

# Install the script
info "Installing vaultsh to $TARGET_FILE..."
if [[ "$NEEDS_SUDO" == true ]]; then
	sudo cp vault.sh "$TARGET_FILE"
	sudo chmod +x "$TARGET_FILE"
else
	cp vault.sh "$TARGET_FILE"
	chmod +x "$TARGET_FILE"
fi

success "Installed vaultsh to $TARGET_FILE"

# Verify installation
info "Verifying installation..."
if [[ "$NEEDS_SUDO" == true ]] || [[ ":$PATH:" == *":$INSTALL_DIR:"* ]]; then
	if command -v vaultsh >/dev/null 2>&1; then
		success "Installation verified - vaultsh is in PATH"
	else
		warning "vaultsh installed but not found in PATH"
		warning "You may need to open a new terminal or run: hash -r"
	fi
else
	# User-local installation and not in PATH
	warning "$INSTALL_DIR is not in your PATH"
	echo ""
	echo "  Add this to your shell's rc file (~/.bashrc, ~/.zshrc, etc.):"
	echo ""
	echo "    ${BOLD}export PATH=\"\$HOME/.local/bin:\$PATH\"${RESET}"
	echo ""
	echo "  Then reload your shell or run:"
	echo ""
	echo "    ${BOLD}source ~/.bashrc${RESET}  # or your shell's rc file"
	echo ""
fi

# Show version/help
echo ""
header "Installation Complete!"
echo ""
echo "Try running: ${BOLD}vaultsh --help${RESET}"
echo ""
echo "Quick start:"
echo "  1. Navigate to a project directory"
echo "  2. Run: ${BOLD}vaultsh your-command${RESET}"
echo "  3. On first run, paste your .env content (Ctrl-D to finish)"
echo "  4. Secrets stored in keyring - future runs load automatically!"
echo ""
echo "Examples:"
echo "  ${BOLD}vaultsh uv run pywrangler dev${RESET}"
echo "  ${BOLD}vaultsh hatch run dev${RESET}"
echo "  ${BOLD}vaultsh --file .secrets act --secret-file .secrets${RESET}"
echo ""
echo "For more information, see: ${CYAN}README.md${RESET}"
echo ""

success "Happy secure coding! 🔐"

# Cleanup temporary repo if it was cloned
if [[ "$CLEANUP_REPO" == true ]]; then
	cd ..
	rm -rf "$REPO_DIR"
fi
