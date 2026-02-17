#!/bin/bash
set -euo pipefail

# vaultsh - Execute commands with secrets from keyring, avoiding .env files on disk
# Automatically loads secrets from keyring, creates temporary .env, and cleans up

# Default configuration
secrets_file=".env"
app_name=$(basename "$PWD")
use_fd=false  # Use file descriptor instead of temp file

# Setup colored output for terminal
color_on=""
color_off=""
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
	color_on="$(tput setaf 6)"
	color_off="$(tput sgr0)"
fi

# Parse command-line options
while [[ $# -gt 0 ]]; do
  case $1 in
    --file|-f)
      secrets_file="$2"; shift 2 ;;
    --app|-a)
      app_name="$2"; shift 2 ;;
    --use-fd)
      use_fd=true; shift ;;
    --help|-h)
      cat << 'EOF'
Usage: vaultsh [OPTIONS] COMMAND [ARGS...]

vaultsh executes commands with secrets loaded from your system keyring,
avoiding the need to store .env files on disk.

Options:
  --file FILE, -f FILE    Secrets file path (default: .env)
  --app APP, -a APP       Keyring app identifier (default: current folder name)
  --use-fd                Use file descriptor instead of temp file (no disk I/O)
  --help, -h              Show this help message

How it works:
  1. If secrets file exists locally → use it directly
  2. Otherwise, load from keyring (app name) → create temporary file (or FD with --use-fd)
  3. Execute your command with SECRETS_FILE environment variable set
  4. Automatically delete temporary file after execution (not needed with --use-fd)

Examples:
  vaultsh uv run pywrangler dev
    Creates .env from keyring, runs command, removes .env

  vaultsh hatch run dev
    Loads secrets and runs hatch development server

  vaultsh --file .secrets act --secret-file .secrets
    Uses custom secrets file for GitHub Actions local testing

  vaultsh --app myproject-prod npm start
    Uses specific keyring entry for production secrets

  vaultsh --use-fd act --secret-file "$SECRETS_FILE"
    No disk I/O - secrets passed via file descriptor (/dev/fd/N)

  vaultsh --use-fd docker run --env-file "$SECRETS_FILE" myimage
    Load env vars from FD without creating temporary file

Advanced:
  - Create <secrets-file>.keep (e.g., .env.keep) to prevent auto-deletion
  - SECRETS_FILE env var is set to the file path (or /dev/fd/N with --use-fd)
  - First run prompts for secrets and stores them in keyring automatically
  - --use-fd mode: No disk writes, but requires command support for file descriptors
    (won't work with shell sourcing or tools requiring regular files)

EOF
      exit 0 ;;
    *)
      break ;;
  esac
done

# Print colored info messages to stdout
info() {
	printf '%s%s%s\n' "$color_on" "$*" "$color_off"
}

# Cleanup function: removes secrets file unless .keep file exists
# No cleanup needed in FD mode (file descriptor auto-closes)
cleanup() {
  if [[ "$use_fd" == "false" ]] && [[ -f "$secrets_file" && ! -e "${secrets_file}.keep" ]]; then
    rm -f "$secrets_file"
    info "✓ $secrets_file deleted after run"
  fi
}

# Validate that a command was provided
if [[ $# -eq 0 ]]; then
  echo "Error: No command provided. Use --help for usage information." >&2
  exit 1
fi

# Setup cleanup trap to remove temporary secrets file on exit
trap cleanup EXIT INT TERM

# If secrets file already exists locally, use it directly (no keyring needed)
if [[ -f "$secrets_file" ]]; then
  info "ℹ Using existing local file: $secrets_file"
  info "→ Running: $*"
  SECRETS_FILE="$secrets_file" "$@"
  exit $?
fi

# Load secrets from keyring
if [[ "$use_fd" == "true" ]]; then
  info "Loading secrets for app='$app_name' (FD mode - no disk I/O)..."
else
  info "Loading secrets for app='$app_name' → $secrets_file..."
fi

# Check for required dependency
if ! command -v secret-tool >/dev/null 2>&1; then
  echo "Error: secret-tool not found. Please install libsecret-tools:" >&2
  echo "  Fedora/RHEL: sudo dnf install libsecret-tools" >&2
  echo "  Ubuntu/Debian: sudo apt install libsecret-tools" >&2
  echo "  Arch: sudo pacman -S libsecret" >&2
  exit 127
fi

# Try to load secrets from keyring
secrets_content=""
if secrets_content=$(secret-tool lookup app "$app_name" 2>/dev/null) && [[ -n "$secrets_content" ]]; then
  line_count=$(echo "$secrets_content" | wc -l)
  
  if [[ "$use_fd" == "true" ]]; then
    info "✓ Loaded from keyring ($line_count lines)"
  else
    # Write to file with secure permissions
    echo "$secrets_content" > "$secrets_file"
    chmod 600 "$secrets_file"
    info "✓ Loaded from keyring ($(wc -l < "$secrets_file") lines)"
  fi
else
  # Secrets not found in keyring - prompt user to provide them
	info "⚠ No secrets found for app='$app_name' in keyring."
	info "Paste your secrets content (KEY=VALUE format), then press Ctrl-D to finish:"
	info "(Press Ctrl-C to cancel)"
	
	secrets_input="$(cat)"
	
	if [[ -z "$secrets_input" ]]; then
		echo "Error: No secrets provided. Aborting." >&2
		exit 1
	fi
	
	label="Secrets for $app_name"
	
	if echo "$secrets_input" | secret-tool store --label "$label" app "$app_name"; then
		# Retrieve from keyring
		if secrets_content=$(secret-tool lookup app "$app_name" 2>/dev/null); then
			line_count=$(echo "$secrets_content" | wc -l)
			
			if [[ "$use_fd" == "true" ]]; then
				info "✓ Stored in keyring as '$label' ($line_count lines)"
			else
				# Write to file with secure permissions
				echo "$secrets_content" > "$secrets_file"
				chmod 600 "$secrets_file"
				info "✓ Stored in keyring as '$label' ($(wc -l < "$secrets_file") lines)"
			fi
		else
			echo "Error: Failed to retrieve secrets from keyring. Aborting." >&2
			exit 1
		fi
	else
		echo "Error: Failed to store secrets in keyring. Aborting." >&2
		exit 1
	fi
fi

# Execute the command with SECRETS_FILE environment variable
info "→ Running: $*"

if [[ "$use_fd" == "true" ]]; then
  # Use file descriptor mode - no disk I/O
  # Open FD 9 for reading from secrets content (using heredoc to avoid ps exposure)
  exec 9< <(cat <<< "$secrets_content")
  SECRETS_FILE="/dev/fd/9" "$@"
  exec_status=$?
  # Close the file descriptor
  exec 9<&-
  exit $exec_status
else
  # Use file mode - traditional temp file approach
  SECRETS_FILE="$secrets_file" "$@"
fi
