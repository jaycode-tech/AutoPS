# Integrations Overview

AutoPS supports integrations with external systems and services.

## Built-in Integrations

| Integration | Type | Description |
|-------------|------|-------------|
| **filesystem** | Core | Local file system operations |
| **git** | Optional | Git repository operations |
| **http** | Optional | HTTP/REST API calls |

## Configuration

Integrations are defined in `automations/manifest.json`:

```json
{
  "integrations": {
    "filesystem": {
      "type": "LocalFilesystem",
      "core": true
    },
    "git": {
      "type": "Git",
      "config": {
        "defaultBranch": "main"
      }
    },
    "http": {
      "type": "Http",
      "config": {
        "timeout": 30000
      }
    }
  }
}
```

## Health Checks

Integrations are validated during health checks:

```
./autops.ps1

Integrations:
[✓] filesystem [CORE]
[✓] git 
[✓] http 
```

## Using Integrations in Tasks

Access integrations via the `$Integrations` variable in task scripts:

```powershell
# Read a file
$content = $Integrations.filesystem.Read("path/to/file.txt")

# Make HTTP request
$response = $Integrations.http.Get("https://api.example.com/data")

# Git operations
$Integrations.git.Commit("Updated config")
```

## Custom Integrations

You can add custom integrations by:

1. Creating an integration module in `core/integrations/`
2. Registering it in the manifest
3. Implementing the required interface methods
