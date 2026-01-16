# Git Integration

The Git integration provides repository operations.

## Configuration

```json
{
  "integrations": {
    "git": {
      "type": "Git",
      "config": {
        "defaultBranch": "main"
      }
    }
  }
}
```

## Operations

### Clone Repository
```powershell
git clone https://github.com/user/repo.git
```

### Commit Changes
```powershell
git add .
git commit -m "Automated update"
```

### Push Changes
```powershell
git push origin main
```

## Example Task

```powershell
# tasks/deploy/git_push.ps1
param($Message = "Automated commit")

Set-Location $env:REPO_PATH

git add -A
git commit -m $Message
git push origin main

return @{
    status = "pushed"
    message = $Message
}
```
