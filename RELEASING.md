# Releasing cvm

This document describes how to create and publish a new release of cvm.

## Version Format

cvm uses [Semantic Versioning](https://semver.org/):

- **MAJOR**: Breaking changes (e.g., 1.0.0 → 2.0.0)
- **MINOR**: New features, backward compatible (e.g., 1.0.0 → 1.1.0)
- **PATCH**: Bug fixes (e.g., 1.0.0 → 1.0.1)

## Release Process

### 1. Update Version and Changelog

```powershell
# Edit VERSION file with new version (e.g., 1.1.0)
Set-Content -Path VERSION -Value "1.1.0" -NoNewline -Encoding UTF8

# Update CHANGELOG.md with release date and summary
# Format: ## [X.Y.Z] - YYYY-MM-DD
```

### 2. Create Release Tag

```powershell
git add VERSION CHANGELOG.md
git commit -m "Release v1.1.0"
git tag -a v1.1.0 -m "Release version 1.1.0"
git push origin main
git push origin v1.1.0
```

### 3. Create GitHub Release

The release will be automatically created via GitHub Actions when the tag is pushed.

**Or manually from GitHub:**

1. Go to [Releases](https://github.com/adriholman/cvm-windows/releases)
2. Click "Draft a new release"
3. Select the tag you just pushed
4. Add release notes from CHANGELOG.md
5. Upload `cvm-release.zip` as an asset

### 4. Create Release Archive

Before the GitHub Actions creates the release, prepare the zip file locally:

```powershell
# Create a temporary directory
$tempDir = "cvm-release-1.1.0"
New-Item -ItemType Directory -Path $tempDir

# Copy files
Copy-Item -Path "bin/cvm.ps1" -Destination $tempDir
Copy-Item -Path "bin/composer.ps1" -Destination $tempDir
Copy-Item -Path "bin/cvm-common.psm1" -Destination $tempDir
Copy-Item -Path "VERSION" -Destination $tempDir
Copy-Item -Path "CHANGELOG.md" -Destination $tempDir
Copy-Item -Path "README.md" -Destination $tempDir

# Create zip (requires .NET 4.5+)
[System.IO.Compression.ZipFile]::CreateFromDirectory(
    (Resolve-Path $tempDir).Path,
    "cvm-release.zip",
    [System.IO.Compression.CompressionLevel]::Optimal,
    $false
)

# Cleanup
Remove-Item -Recurse -Force $tempDir
```

### 5. Announce Update

After release is published:
- Add release notes to GitHub discussions or wiki
- Update any relevant documentation
- (Optional) Post in community channels

## Verifying a Release

Users can verify the release works with:

```powershell
cvm selfupdate --check    # See available version
cvm selfupdate            # Install latest
cvm version              # Verify new version
```

## Troubleshooting

### GitHub API rate limits

If `cvm selfupdate` fails with rate limit errors:
- Wait an hour before retrying (API limit resets)
- Users can manually download from releases page

### Release zip structure

The `cvm-release.zip` must contain files in the root:
```
cvm-release.zip
├── cvm.ps1
├── composer.ps1
├── cvm-common.psm1
├── VERSION
├── CHANGELOG.md
└── README.md
```

**NOT** in a subfolder. The extraction expects files directly in root.

## Automated Releases (Future)

To enable automatic releases on version file changes, use GitHub Actions:

```yaml
name: Create Release

on:
  push:
    paths:
      - 'VERSION'
    branches:
      - main

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Read version
        id: version
        run: echo "VERSION=$(cat VERSION)" >> $GITHUB_OUTPUT
      - name: Create release archive
        run: |
          mkdir cvm-release
          cp bin/*.ps1 cvm-release/
          cp bin/*.psm1 cvm-release/
          cp VERSION cvm-release/
          zip -r cvm-release.zip cvm-release/
      - name: Create GitHub Release
        uses: actions/create-release@v1
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          tag_name: v${{ steps.version.outputs.VERSION }}
          release_name: Release v${{ steps.version.outputs.VERSION }}
          body_path: CHANGELOG.md
          draft: false
          prerelease: false
      - name: Upload Release Asset
        uses: actions/upload-release-asset@v1
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          upload_url: ${{ steps.create_release.outputs.upload_url }}
          asset_path: ./cvm-release.zip
          asset_name: cvm-release.zip
          asset_content_type: application/zip
```

## Questions?

For questions about releases, open an issue on GitHub.
