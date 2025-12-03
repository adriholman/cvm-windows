# cvm Usage Examples

This directory contains examples of how to use cvm in different scenarios.

## `modern-project/` - Project with Composer 2

Contains a `.composer-version` file with the value `2`, which makes cvm automatically use Composer 2.x when you run commands from this directory.

```powershell
cd examples\modern-project
cvm which        # Will show it's using version 2
cvm --version    # Will show Composer 2.x.x
```

## `legacy-project/` - Project with Composer 1

Contains a `.composer-version` file with the value `1`, which makes cvm automatically use Composer 1.x.

```powershell
cd examples\legacy-project
cvm which        # Will show it's using version 1
cvm --version    # Will show Composer 1.x.x
```

## How to use in your projects

1. Navigate to your project root
2. Create a `.composer-version` file with the desired version:
   ```powershell
   echo "2" > .composer-version
   ```
3. Run cvm from any subdirectory of the project and it will automatically use that version

## Supported versions

You can use any of these values in `.composer-version`:

- `1` - Latest Composer 1.x version
- `2` - Latest Composer 2.x version
- `stable` - Latest stable version (any branch)
- `preview` - Latest preview/beta version
- `2.7.1` - A specific exact version

