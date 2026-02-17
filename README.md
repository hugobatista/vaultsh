# vaultsh 🔐

**Execute commands with secrets from keyring, not from disk.**

vaultsh is a bash utility that runs commands with environment secrets loaded from your system's secure keyring, eliminating the need to store `.env` files on disk. Perfect for developers who want to keep credentials off the filesystem while maintaining a smooth development workflow.

## Quick Example

Instead of this (storing secrets on disk):
```bash
# ❌ Dangerous: secrets exposed on filesystem
cat .env  # DATABASE_PASSWORD=super_secret
python app.py
```

Do this (secrets from keyring):
```bash
# ✅ Secure: secrets loaded from keyring, never persisted to disk
vaultsh python app.py
```

**Under the hood:** vaultsh retrieves your secrets from the system keyring (encrypted and managed by the OS), creates a temporary file with secure permissions only your process can read, passes it to your command, and deletes it immediately after—leaving no trace on disk.


## Prerequisites

- **Linux** with a keyring service (GNOME Keyring, KWallet, etc.)
- **bash** (4.0+)
- **secret-tool** from `libsecret-tools` package


## Installation

### One-liner (Recommended)

```bash
curl -fsSL https:/go.hugobatista.com/gh/vaultsh/blob/main/install.sh | sh
```

### Or clone and install locally

Download the repository and run the installer:

```bash
git clone https:/go.hugobatista.com/gh/vaultsh.git
cd vaultsh
./install.sh
```

The installer will:
1. Check for dependencies
2. Let you choose between system-wide (`/usr/local/bin`) or user-local (`~/.local/bin`) installation
3. Set up the `vaultsh` command
4. Verify the installation

## Usage

```bash
vaultsh [OPTIONS] COMMAND [ARGS...]
```

### Options

| Option | Description |
|--------|-------------|
| `--file FILE`, `-f FILE` | Secrets file path (default: `.env`) |
| `--app APP`, `-a APP` | Keyring app identifier (default: current folder name) |
| `--use-fd` | Use file descriptor instead of temp file (no disk I/O) |
| `--help`, `-h` | Show help message |


## Examples

### Example 1: Python development with uv

```bash
vaultsh uv run pywrangler dev
```

**What happens:**
1. Loads `.env` from keyring for current folder
2. Creates temporary `.env` file
3. Runs `uv run pywrangler dev` with secrets available
4. Deletes `.env` after command completes

### Example 2: Python project with hatch

```bash
vaultsh hatch run dev
```

Perfect for running development servers where you need environment variables but don't want them persisted on disk.

### Example 3: GitHub Actions local testing with act

```bash
vaultsh --file .secrets act --secret-file .secrets
```

**What happens:**
1. Uses custom file name `.secrets` instead of `.env`
2. Loads or prompts for secrets under that filename
3. Runs `act` with the secrets file
4. Cleans up `.secrets` after execution

This is especially useful for testing GitHub Actions workflows locally while keeping production secrets secure.

### Example 4: Multiple environments with custom app names

```bash
# Development environment
vaultsh --app myproject-dev npm start

# Production environment
vaultsh --app myproject-prod npm start
```

Each `--app` name is a separate keyring entry, allowing you to manage different secret sets (dev, staging, prod) for the same project.

### Example 5: Docker commands

```bash
vaultsh docker-compose up
```

Great for docker-compose files that source `.env` for configuration.

### Example 6: Just viewing the secrets file path

```bash
vaultsh env | grep SECRETS_FILE
```

The `SECRETS_FILE` environment variable contains the absolute path to the secrets file created by vaultsh.

### Example 7: File descriptor mode (no disk I/O)

```bash
vaultsh --use-fd act --secret-file "$SECRETS_FILE"
```

**What happens:**
1. Loads secrets from keyring into memory
2. Creates file descriptor at `/dev/fd/9` (no disk write)
3. Sets `SECRETS_FILE=/dev/fd/9`
4. Runs `act` which reads secrets from the file descriptor
5. FD automatically closes - no cleanup needed

**Perfect for:**
- GitHub Actions local testing with `act`
- Docker with `--env-file`
- Any tool that can read from file descriptors

**Won't work for:**
- Shell sourcing (`source $SECRETS_FILE`)
- Tools that verify file exists with stat checks
- Tools that need to read the file multiple times

### Example 8: Docker with FD mode

```bash
vaultsh --use-fd docker run --env-file "$SECRETS_FILE" myimage
```

Secrets are loaded from keyring and passed to Docker without ever touching the disk.

## Advanced Features

### Preventing Auto-Cleanup

Create a `.keep` file to prevent automatic deletion of the secrets file:

```bash
touch .env.keep
vaultsh your-command
# .env will remain after execution
```

This is useful for:
- Debugging secrets content
- Running multiple commands without reloading
- IDE integration where the editor expects a persistent file

### Custom Secrets File Locations

```bash
# Use a different file name
vaultsh --file .env.production npm run build

# Use a path in a different directory
vaultsh --file /tmp/my-secrets ./deploy.sh
```

### SECRETS_FILE Environment Variable

Your command receives the `SECRETS_FILE` environment variable pointing to the secrets file:

```bash
vaultsh bash -c 'echo "Secrets are at: $SECRETS_FILE"'
```

You can use this in scripts that need to know the file location explicitly.

### File Descriptor Mode (No Disk I/O)

For maximum security, use `--use-fd` to pass secrets via file descriptor without writing to disk:

```bash
vaultsh --use-fd COMMAND
```

**How it works:**
- Secrets loaded from keyring into memory only
- File descriptor created at `/dev/fd/9`
- `SECRETS_FILE` env var set to `/dev/fd/9`
- Your command reads from the FD as if it were a file
- No temp file created, no cleanup needed
- FD automatically closes when command completes

**Security benefits:**
- Zero disk I/O - secrets never hit the filesystem
- No directory entry visible in `ls`
- Automatic cleanup (pipe closes on exit)
- No permission race conditions
- Immune to `.keep` file accidents

**Compatibility:**

✅ **Works with these tools:**
```bash
vaultsh --use-fd act --secret-file "$SECRETS_FILE"
vaultsh --use-fd docker run --env-file "$SECRETS_FILE" image
vaultsh --use-fd kubectl create secret --from-env-file="$SECRETS_FILE"
vaultsh --use-fd bash -c 'cat "$SECRETS_FILE"'
```

❌ **Won't work with:**
- Shell sourcing: `source "$SECRETS_FILE"` (expects regular file)
- Tools checking file type: may reject `/dev/fd/N`
- Multiple-read tools: FDs are sequential, single-pass
- Tools extracting parent directory from path

**When to use:**
- Running on shared systems where disk writes are risky
- Maximum security paranoia mode
- Tools that explicitly support FD input (act, docker, kubectl)
- When you want zero filesystem footprint

**When NOT to use:**
- Sourcing secrets in shell scripts
- Tools requiring regular files
- When temp file approach works fine

### First-Run Setup

On first use (when secrets aren't in keyring):

1. vaultsh prompts: "Paste your secrets content..."
2. Paste your `.env` content (KEY=VALUE format)
3. Press `Ctrl-D` to finish (or `Ctrl-C` to cancel)
4. Secrets are encrypted and stored in system keyring
5. Future runs load automatically

## Security Notes

- **Keyring encryption**: Secrets stored in your system's encrypted keyring service
- **File permissions**: Temporary files created with `600` permissions (owner read/write only)
- **Short-lived exposure**: Files on disk exist only during command execution
- **File descriptor mode**: Use `--use-fd` for zero disk I/O (most secure option)
- **No git commits**: Temporary files are created/deleted, reducing risk of accidental commits
- **Session isolation**: Each terminal session can use different secrets with `--app` flag

**⚠️ Important**: While vaultsh improves security, temporary files are still written to disk briefly (in default mode). For maximum security:
- **Use `--use-fd` flag** for zero disk writes (when your tool supports it)
- Use encrypted home directories
- Ensure your keyring is properly locked when not in use
- Be cautious running vaultsh on shared systems

## Troubleshooting

### "secret-tool not found" error

Install libsecret-tools package (see [Prerequisites](#prerequisites))

### "Command fails with --use-fd"

The command may require a regular file instead of a file descriptor. Try without `--use-fd`:

```bash
# If this fails:
vaultsh --use-fd mycommand

# Try this instead:
vaultsh mycommand
```

**Common scenarios:**
- **Shell sourcing**: `source "$SECRETS_FILE"` needs a real file, not an FD
- **Stat checks**: Tool checks if file is regular file type
- **Multiple reads**: Tool tries to read the file twice (FDs are single-pass)

**Compatible tools:** act, docker, kubectl, most modern CLI tools that just read input

**Incompatible:** shell source command, some config parsers, editors

### Keyring prompts for password repeatedly

Your keyring daemon might not be running. Check:

```bash
# Check if gnome-keyring is running
ps aux | grep gnome-keyring

# Or for KDE
ps aux | grep kwalletd
```

Start your desktop environment's keyring service if it's not running.

### "No secrets found" on every run

Check if secrets are actually stored:

```bash
secret-tool search app "$(basename $PWD)"
```

If nothing appears, the keyring store failed. Try storing manually:

```bash
secret-tool store --label "Test" app "my-test"
# Paste your secret, press Ctrl-D
secret-tool lookup app "my-test"
```

### Secrets file not deleted after run

Check for a `.keep` file:

```bash
ls -la .env.keep
```

Remove it to restore auto-cleanup:

```bash
rm .env.keep
```

### Want to delete stored secrets

```bash
# List secrets for current folder
secret-tool search app "$(basename $PWD)"

# Delete specific entry
secret-tool clear app "$(basename $PWD)"

# Or for a specific app name
secret-tool clear app "myproject-prod"
```

### Command fails but secrets file remains

If your command crashes before vaultsh's cleanup trap runs, manually remove:

```bash
rm .env  # or your custom secrets file name
```

## Uninstallation

Run the uninstall script:

```bash
./uninstall.sh
```

This will:
1. Remove the `vaultsh` binary
2. Optionally help you clear keyring entries

To manually clear all vaultsh secrets from keyring:

```bash
# List all entries
secret-tool search app ""

# Remove specific ones
secret-tool clear app "your-app-name"
```

## Contributing

vaultsh is a single-file bash script designed for simplicity. Contributions welcome!

- **Bug reports**: Open an issue with details
- **Feature requests**: Describe your use case
- **Pull requests**: Keep changes focused and well-tested

## License

This project is released as open source. Feel free to use, modify, and distribute.

## Similar Tools

- **direnv**: Loads environment from `.envrc` files (but still requires files on disk)
- **pass**: CLI password manager (requires manual sourcing)
- **1Password CLI**: Commercial tool with similar goals
- **AWS Secrets Manager/HashiCorp Vault**: Enterprise solutions for secret management

vaultsh fills the gap for local development where you want system keyring integration without complex setup.

---

**Made with ❤️ for developers who care about secrets on disk**
