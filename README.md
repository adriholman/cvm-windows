# cvm - Composer Version Manager for Windows

[![Latest Stable Release](https://img.shields.io/github/v/release/adriholman/cvm-windows?label=Latest%20Release)](https://github.com/adriholman/cvm-windows/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/adriholman/cvm-windows/total?label=Downloads)](https://github.com/adriholman/cvm-windows/releases)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B%20%7C%207%2B-5391FE?logo=powershell&logoColor=white)](https://learn.microsoft.com/powershell/)
[![License](https://img.shields.io/github/license/adriholman/cvm-windows?label=License)](https://github.com/adriholman/cvm-windows/blob/main/LICENSE)

> Note
> This project originated from a personal need. It may contain mistakes or rough edges. You are free to use, modify, and adapt it for your own purposes. If you prefer, you’re very welcome to contribute improvements back to this repository via issues or pull requests.

**cvm** (Composer Version Manager) is a Composer version manager for Windows, written in PowerShell. It allows you to install, switch, and manage multiple Composer versions on the same system.

## ✨ Features

- 🔄 **Multiple versions**: Install and use Composer 1.x, 2.x, stable, preview, or specific versions (e.g., `2.7.1`)
- 📁 **Per-project**: Use `.composer-version` to pin versions per project
- 🌍 **Global**: Set a default version for the entire system
- 🔐 **SHA256 verification**: Verifies checksums for exact versions (security)
- ⚡ **Transparent proxy**: Run `cvm install 2` then `cvm require vendor/package` without thinking
- 🛠️ **Clean PATH**: Only command shims are exposed in PATH, while PowerShell launchers stay internal
- 📊 **Progress downloads**: Shows approximate file size and progress bar (can be silenced with `--quiet`)
- 🧭 **Flexible caches**: Uses `%USERPROFILE%\.cvm` by default or `%LOCALAPPDATA%\cvm`/`--cache-root`
- 🧹 **Quick maintenance**: `cvm clean` to purge unused versions and `cvm selfupdate` to refresh scripts

## 📦 Installation

### Option A: Download release (recommended)

1) Download and unzip `cvm-release.zip` from the latest release.
2) In the extracted folder, run:

```powershell
# Install cvm (adds cvm and Composer global bin to your PATH)
./setup-path.ps1 -Action install
```

3) Open a new terminal to refresh PATH.
4) Verify:

```powershell
cvm which
```

### Option B: Clone the repository

```powershell
git clone https://github.com/adriholman/cvm-windows.git
cd cvm-windows
./scripts/setup-path.ps1 -Action install
```

Then open a new terminal and validate with `cvm which`.

## 🚀 Usage

### Install versions

```powershell
# Install Composer 2 (latest stable from 2.x branch)
cvm install 2

# Install Composer 1 (latest stable from 1.x branch)
cvm install 1

# Install the latest stable version (any branch)
cvm install stable

# Install the latest preview
cvm install preview

# Install a specific version
cvm install 2.7.1
```

### Set default version

```powershell
# Set Composer 2 as global default version
cvm default 2

# Or use a specific version
cvm default 2.7.1
```

### View active version information

```powershell
cvm which
```

Shows:
- Version source (`.composer-version` file, environment variable, or global default)
- Current version
- `composer.phar` file path
- Cache directory
- Configuration path

### List installed versions

```powershell
cvm list
```

### Use Composer normally

Once installed, you can use the `composer` command directly. The launcher resolves the version (env var, `.composer-version`, or global default), ensures it’s installed, and runs Composer. The installer also adds Composer's default global bin directory to your user `PATH`, so tools installed with `composer global require` remain invokable.

```powershell
composer --version
composer require symfony/console
composer update
composer install --no-dev
```

Tip: `cvm` is for version management: `cvm install <version>`, `cvm default <version>`, `cvm which`, `cvm list`.

### Global options

You can prepend options to any `cvm` command:

- `--quiet` (`-q`): Reduce output (also via `CVM_QUIET=1`)
- `--verbose` (`-v`): Extra details (also `CVM_VERBOSE=1`)
- `--no-verify`: Skip checksum verification (useful offline; also `CVM_NO_VERIFY=1`)
- `--cache-root <path>`: Use custom cache path (or `CVM_CACHE_ROOT`)
- `--use-localappdata`: Use `%LOCALAPPDATA%\cvm` instead of `%USERPROFILE%\.cvm`

## 🎯 Version Resolution

cvm resolves the version to use in the following priority order:

1. **Environment variable `CVM_VERSION`**: For temporary sessions
   ```powershell
   $env:CVM_VERSION = "1"
   cvm --version  # Will use Composer 1.x
   ```

2. **`.composer-version` file**: For specific projects
   - cvm searches for `.composer-version` in the current directory and all parents
   - Create a `.composer-version` file at your project root:
     ```
     2
     ```
   - Now any `cvm` command executed in that project will use Composer 2

3. **Global default version**: Configured with `cvm default <version>`
   - Saved in `%USERPROFILE%\.cvm\config.json`
   - Used if there's no `.composer-version` or `CVM_VERSION`

4. **Fallback**: If no configuration exists, uses `stable`

## 📂 File Structure

```
%USERPROFILE%\.cvm\
├── bin\
│   ├── cvm.cmd              # Public command shim used by PowerShell/cmd
│   ├── composer.cmd         # Public command shim used by PowerShell/cmd
│   ├── cvm-launcher.ps1     # Internal PowerShell launcher
│   ├── composer-launcher.ps1# Internal PowerShell launcher
│   └── cvm-common.psm1      # Shared module
├── versions\
│   ├── 1\
│   │   └── composer.phar    # Composer 1.x (latest version)
│   ├── 2\
│   │   └── composer.phar    # Composer 2.x (latest version)
│   ├── stable\
│   │   └── composer.phar    # Latest stable version
│   └── 2.7.1\
│       ├── composer.phar
│       └── composer.phar.sha256sum
└── config.json              # { "default": "2" }
```

## 🔧 Examples

### Project with Composer 1 (legacy)

```powershell
cd my-old-project
echo "1" > .composer-version
cvm which                    # Shows version 1
cvm install                  # Installs dependencies with Composer 1
```

### Project with Composer 2

```powershell
cd my-new-project
echo "2" > .composer-version
cvm install
cvm require symfony/console
```

### Test a specific version temporarily

```powershell
$env:CVM_VERSION = "preview"
cvm --version                # Shows preview version
cvm selfupdate              # Updates Composer (within preview version)
Remove-Item Env:\CVM_VERSION # Return to normal version
```

## 🚀 Updating cvm

### Automatic updates

Simply run:

```powershell
cvm selfupdate
```

This command will:
1. Check the latest release on GitHub
2. Download and extract the release files
3. Update your local installation in `~/.cvm/bin/`
4. Update the VERSION file

### Check for updates without installing

```powershell
cvm selfupdate --check
```

This shows if a newer version is available without installing it.

### Manual update

If automatic update fails, you can manually download releases from:
[github.com/adriholman/cvm-windows/releases](https://github.com/adriholman/cvm-windows/releases)

Then run `.\scripts\setup-path.ps1 -Action install` to reinstall.

---

## 🏭 CI usage (GitHub Actions example)

```yaml
jobs:
   build:
      runs-on: windows-latest
      steps:
         - uses: actions/checkout@v4
         - name: Install cvm
            shell: pwsh
            run: .\scripts\setup-path.ps1 -Action install
         - name: Ensure Composer 2 and install deps
            shell: pwsh
            run: |
               cvm install 2
               cvm which
               composer install --no-dev --no-interaction
```

Remarks:
- The `composer` wrapper uses cvm's version resolution (environment, .composer-version, default)
- Global Composer binaries resolve from `%APPDATA%\Composer\vendor\bin` unless you override `COMPOSER_HOME`
- Use `--quiet`/`--verbose` with `cvm` to control noise in CI logs
- For cache in `%LOCALAPPDATA%`, use: `cvm --use-localappdata install 2`

## 🗑️ Uninstallation

```powershell
# Uninstall cvm from PATH
.\scripts\setup-path.ps1 -Action uninstall

# Remove cached versions (optional)
Remove-Item -Recurse -Force "$env:USERPROFILE\.cvm"
```

## ⚙️ Requirements

- **Windows** with PowerShell 5.1+ or PowerShell 7+
- **PHP CLI** in PATH (required to run Composer)
  - Verify with: `php -v`
  - If you don't have PHP, download it from [windows.php.net](https://windows.php.net/download/)

## 📋 Available Commands

| Command | Description |
|---------|-------------|
| `cvm install <version>` | Downloads and caches the specified version |
| `cvm default <version>` | Sets the global default version |
| `cvm which` | Shows current resolution (version and path) |
| `cvm list` | Lists locally installed versions |
| `cvm <other-args>` | Proxy to composer - any other argument is forwarded |
| `cvm selfupdate` | Copies the local scripts and VERSION into the cache bin |
| `cvm clean [--all] [--keep <v>]` | Removes cached versions (keeps default/active unless `--all`) |

## 🐛 Troubleshooting

| Error / Symptom | Probable Cause | Quick Fix |
|-----------------|----------------|-----------|
| `PHP not found in PATH` | PHP CLI not installed or not in PATH | Install PHP (`winget install --id PHP.PHP`) and verify with `php -v` |
| `PHP X.Y too old for Composer Z` | PHP version below Composer requirements (Composer 2: ≥7.2.5, Composer 1: ≥5.3.2) | Upgrade PHP or use `cvm default 1` if you need Composer 1 with older PHP |
| `Invalid checksum` | Corrupted download | `Remove-Item "$env:USERPROFILE\.cvm\versions\<v>" -Recurse -Force; cvm install <v>`. Use `--no-verify` only offline |
| Slow download / timeout | Slow network or mirror down | Retry; use `--use-localappdata` for local cache; automatic fallback to mirrors and retries |
| Space not cleaned | Versions in use | Run `cvm clean --all` (or `--keep 2`) to force cleanup |
| Aliases/commands not found after install | PATH not reloaded | Open a new terminal or reload `$PROFILE` |
| `composer` blocked by PowerShell signing policy | Old installs exposed `composer.ps1` directly in PATH | Re-run `setup-path.ps1 -Action install` to replace direct `.ps1` entrypoints with `.cmd` shims |
| `laravel` or another global Composer tool is not recognized | Composer global bin directory missing from PATH | Re-run `setup-path.ps1 -Action install` or add `%APPDATA%\Composer\vendor\bin` to your user PATH |

## 🤝 Contributing

Contributions are welcome! This is a community-friendly project that started as a personal need, so improvements and fixes are highly appreciated. Please:

1. Fork the repository
2. Create a branch for your feature (`git checkout -b feature/new-feature`)
3. Commit your changes (`git commit -am 'Add new feature'`)
4. Push to the branch (`git push origin feature/new-feature`)
5. Open a Pull Request

## 📄 License

Apache License 2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE) for details and attribution requirements.
Copyright (c) 2025-2026 Adrian Holman.

## 🐛 Report Issues

If you find a bug or have a suggestion, please open an [issue](https://github.com/adriholman/cvm/issues).

---

**Made with ❤️ for the PHP community on Windows**
