# Entware Setup for Synology DSM 7.2+

Secure installation and configuration of **Entware** (with `opkg`) on Synology NAS running DSM 7.2+.
Entware provides a lightweight package manager with thousands of Linux CLI tools, without interfering with DSM updates.

## What You Get

Well, you get Entware, and the ability to install packages such as:

- `jq` – JSON processor
- `git` – version control
- `ripgrep (rg)` – fast recursive search
- `htop` – process monitor
- `tmux` – terminal multiplexer

### Basic Installation

After remoting into your Synology NAS via SSH:

1. Clone and navigate to the repository
2. From `synlogy/entware`, run the setup script:

```bash
sudo -i
bash setup-entware.sh
```

### Installation Options

You can pass commands to the script for:

- **Dry Run**: Preview changes without making them
- **Verbose Output**: Get detailed logs during installation
- **Custom Package List**: Specify which packages to install automatically after setting up Entware
- **Skip Scheduler Task Creation**: Avoid automatic creation of the DSM Task Scheduler job (default)

> Note: The DSM Task Scheduler job is recommended to be done manually via the Synology UI to avoid DSM updates from overwriting your task.

```bash
# Dry run to preview changes
sudo bash setup-entware-refactored.sh --dry-run

# Verbose output
sudo bash setup-entware-refactored.sh --verbose

# Custom package list
sudo bash setup-entware-refactored.sh --packages "git htop nano"

# Skip automatic scheduler task creation
sudo bash setup-entware-refactored.sh --no-scheduler
```

### Verification

After installation, verify the tools:

```bash
/opt/bin/opkg --version
/opt/bin/jq --version
/opt/bin/git --version
```

## ⚙️ Configuration

### Auto-start on Reboot

The script automatically creates a **DSM Task Scheduler** job called `Entware Startup` that runs:

```bash
/opt/etc/init.d/rc.unslung start
```

### Environment Variables

Configure the installation with environment variables:

```bash
# Custom installation path
export ENTWARE_INSTALL_PATH="/volume1/@entware"

# Skip package installation
export ENTWARE_INSTALL_PACKAGES=""

# Force specific architecture
export ENTWARE_ARCH="armv7sf-k3.2"
```

## 🔧 Package Management

```bash
# Update package lists
opkg update

# Search for packages
opkg list | grep <package>

# Install packages
opkg install <package>

# Remove packages
opkg remove <package>
```

## 🗑️ Uninstall / Reset

To completely remove Entware:

```bash
sudo -i
synoschedtask --del "Entware Startup"
mv /opt "/opt.removed.$(date +%Y%m%d%H%M%S)"
```

Then re-run the setup script if needed.

## 📚 References

- [Entware Project](https://github.com/Entware/Entware)
- [Synology Community Wiki](https://github.com/Entware/Entware/wiki/Install-on-Synology-NAS)
