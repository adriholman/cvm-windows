# Changelog - cvm (Composer Version Manager)

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.6] - 2026-01-08

### Fixed
- `cvm list` now handles empty or single-version cases correctly (fixed .Count property error)
- `cvm selfupdate --check` properly respects check-only flag without downloading

### Changed
- **release.ps1 enhancements**: Added `-Major`, `-Minor`, `-Patch` flags for semantic version auto-increment
- Dry-run mode no longer mutates VERSION file; changes only applied with `-Push`
- Improved tag reuse: existing local tags can be pushed without recreation

## [1.1.5] - 2026-01-08

### Fixed
- `cvm selfupdate --check` now only reports availability and no longer downloads/installs

## [1.1.4] - 2026-01-08

### Added
- Release archives now include LICENSE and NOTICE files for attribution compliance

## [1.1.3] - 2026-01-08

### Changed
- License clarified to Apache 2.0 with attribution; added LICENSE/NOTICE notices and updated years to 2025-2026

## [1.1.2] - 2026-01-08

### Fixed
- **setup-path.ps1 now works from release archives**: Script auto-detects flat structure (release) vs nested structure (repository)
- Installation from downloaded releases now works correctly without path errors

## [1.1.1] - 2026-01-08

### Fixed
- **Release archives now include setup-path.ps1**: Installation script was missing from release downloads
- **Simplified release process**: Removed redundant local ZIP creation from release.ps1 (GitHub Actions handles it)

## [1.1.0] - 2026-01-08

### Added
- **GitHub-based selfupdate**: `cvm selfupdate` now downloads the latest release from GitHub instead of copying local files
- **Update notifications**: cvm checks for newer versions on each run (can be disabled)
- **Version check command**: `cvm selfupdate --check` to see available updates without installing
- **PowerShell best practices**: All function names aligned with approved PowerShell verbs (New-, Test-, Invoke-, Install-)
- **Improved error messages**: More descriptive error handling with helpful suggestions
- **cvm-common.psm1 in releases**: Shared module now included in GitHub releases for easy distribution

### Changed
- **Cmd-SelfUpdate**: Enhanced to download from GitHub releases instead of local repo
- **Version resolution**: More robust version detection with better fallbacks
- **.gitignore**: Updated to allow .psm1 files (code should be versioned)
- **README**: Translated remaining Spanish sections to English, added release notes references

### Fixed
- Function naming warnings removed (no more -DisableNameChecking needed)
- Array type coercion issues in version management
- Edge case handling in clean command with no versions installed

### Deprecated
- Local-only selfupdate (now fetches from GitHub by default)

## [1.0.0] - 2026-01-07

### Added
- **Composer version management**: Install and switch between multiple Composer versions (1.x, 2.x, stable, preview, specific x.y.z)
- **Per-project versioning**: `.composer-version` file support for project-specific versions
- **Global defaults**: Set system-wide default Composer version via `cvm default <version>`
- **SHA256 verification**: Automatic checksum validation for exact versions
- **Progress tracking**: Download progress bars with file size estimates
- **Global options**:
  - `--quiet` / `-q`: Reduce output noise
  - `--verbose` / `-v`: Extra logging details
  - `--no-verify`: Skip checksum verification (offline mode)
  - `--cache-root <path>`: Custom cache location
  - `--use-localappdata`: Store cache in %LOCALAPPDATA%\cvm
- **Version maintenance**:
  - `cvm clean [--all] [--keep <version>]`: Remove unused cached versions
  - `cvm selfupdate`: Update cvm scripts to latest version
  - `cvm list`: List all installed versions
  - `cvm which`: Show current active version and its source
- **Transparent proxy**: `cvm <composer-args>` automatically routes to the correct Composer version
- **Fallback mirrors**: Automatic retry with mirror endpoints if primary download fails
- **Retry logic**: Exponential backoff (3 retries by default, configurable)
- **PHP validation**: Verifies PHP version meets Composer requirements before execution
- **Flexible caching**: Supports %USERPROFILE%\.cvm, %LOCALAPPDATA%\cvm, or custom paths
- **Environment configuration**: Support for CVM_VERSION, CVM_QUIET, CVM_VERBOSE, CVM_NO_VERIFY, CVM_CACHE_ROOT, CVM_USE_LOCALAPPDATA
- **PowerShell integration**: Cross-shell .cmd wrappers for compatibility
- **Installation script**: `setup-path.ps1` for easy PATH configuration
- **Comprehensive documentation**: README with usage examples, troubleshooting table, CI/CD integration examples

---

## Versioning Notes

- **1.x**: Stable releases for production use
- **2.0.0** (future): Major rewrite or feature changes that break backward compatibility
- Breaking changes are avoided when possible and clearly documented

## How to Update

Run `cvm selfupdate` to download and install the latest version from GitHub.

To check for updates without installing: `cvm selfupdate --check`
