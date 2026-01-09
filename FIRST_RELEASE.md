# First Release Checklist - cvm v1.1.0

This checklist helps you publish the first GitHub release for cvm v1.1.0.

## Prerequisites

- [ ] You have push access to the GitHub repository
- [ ] You have updated VERSION to `1.1.0`
- [ ] You have committed all changes locally
- [ ] CHANGELOG.md is updated

## Step 1: Create the Release Archive

```powershell
# Navigate to project root
cd c:\Users\adrih\Documents\cvm-windows

# Create temporary directory
$version = "1.1.0"
$tempDir = "cvm-release-$version"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

# Copy all necessary files
Copy-Item -Path "bin/cvm.ps1" -Destination $tempDir
Copy-Item -Path "bin/composer.ps1" -Destination $tempDir
Copy-Item -Path "bin/cvm-common.psm1" -Destination $tempDir
Copy-Item -Path "VERSION" -Destination $tempDir
Copy-Item -Path "CHANGELOG.md" -Destination $tempDir
Copy-Item -Path "README.md" -Destination $tempDir

# Create zip archive
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory(
    (Resolve-Path $tempDir).Path,
    "cvm-release.zip",
    [System.IO.Compression.CompressionLevel]::Optimal,
    $false
)

# Verify zip was created
if (Test-Path "cvm-release.zip") {
    Write-Host "✓ Release archive created successfully" -ForegroundColor Green
    Get-Item "cvm-release.zip" | Select-Object FullName, @{Name="Size(KB)";Expression={[math]::Round($_.Length/1KB)}}
} else {
    Write-Host "✗ Failed to create release archive" -ForegroundColor Red
}

# Cleanup
Remove-Item -Recurse -Force $tempDir
```

## Step 2: Create Git Tag and Push

```powershell
# Stage all changes
git add .
git commit -m "Release v1.1.0 - GitHub-based selfupdate and release workflow"

# Create annotated tag
git tag -a v1.1.0 -m "Release version 1.1.0: GitHub-based selfupdate, improved error handling, PowerShell best practices"

# Push to GitHub
git push origin main
git push origin v1.1.0

# Verify
git tag --list v1.1.0 -n 5
```

## Step 3: Create GitHub Release (Manual)

1. Go to: https://github.com/adriholman/cvm-windows/releases/new
2. Select tag: `v1.1.0`
3. Release title: `Release v1.1.0`
4. Copy CHANGELOG.md content into description (## [1.1.0] section)
5. Upload `cvm-release.zip` as release asset
6. Click "Publish release"

## Step 4: Verify Release Works

```powershell
# The GitHub Actions workflow should automatically create the release
# Once published, test that cvm selfupdate can find it:

pwsh -NoLogo -NoProfile -File .\bin\cvm.ps1 selfupdate --check

# Should output something like:
# [cvm] Checking for updates... (current: 1.1.0)
# [cvm] Latest available: 1.1.0
# [cvm] You are already running the latest version (1.1.0)
```

## Step 5: Announce Release

- [ ] Create GitHub discussion (optional)
- [ ] Update website/wiki (if applicable)
- [ ] Notify users

## Troubleshooting

### "Response status code does not indicate success: 404"
- The release hasn't been created yet
- Make sure you pushed the tag: `git push origin v1.1.0`
- Wait a moment for GitHub to sync

### zip file not created
- Verify .NET 4.5+ is installed
- Try using PowerShell 7+ which has better zip support
- Or manually create zip using Windows Explorer

### Cannot push tag
- Verify you have push permissions: `git remote -v`
- Try: `git push --all && git push --tags`

## Future Releases

For future releases (v1.1.1, v1.2.0, etc.):

1. Update VERSION file
2. Update CHANGELOG.md
3. Run `git add VERSION CHANGELOG.md && git commit -m "Release vX.Y.Z"`
4. Run `git tag -a vX.Y.Z -m "Release version X.Y.Z"`
5. Run `git push origin main && git push origin vX.Y.Z`
6. GitHub Actions will automatically create the release!

The workflow file `.github/workflows/create-release.yml` will handle the rest.
