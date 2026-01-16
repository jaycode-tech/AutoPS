# Filesystem Integration

The filesystem integration provides local file system operations.

## Configuration

```json
{
  "integrations": {
    "filesystem": {
      "type": "LocalFilesystem",
      "core": true
    }
  }
}
```

## Operations

### Read File
```powershell
$content = Read-AutoPSFile -Path "data/input.txt"
```

### Write File
```powershell
Write-AutoPSFile -Path "data/output.txt" -Content $data
```

### Check Existence
```powershell
if (Test-AutoPSPath -Path "data/file.txt") {
    # File exists
}
```

### List Directory
```powershell
$files = Get-AutoPSChildItem -Path "data/"
```

## Example Task

```powershell
# tasks/etl/read_input.ps1
param($InputFile)

$content = Get-Content $InputFile -Raw
$data = $content | ConvertFrom-Json

return @{
    records = $data.Count
    data = $data
}
```
