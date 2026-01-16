# HTTP Integration

The HTTP integration provides REST API capabilities.

## Configuration

```json
{
  "integrations": {
    "http": {
      "type": "Http",
      "config": {
        "timeout": 30000,
        "defaultHeaders": {
          "User-Agent": "AutoPS/2.1"
        }
      }
    }
  }
}
```

## Operations

### GET Request
```powershell
$response = Invoke-RestMethod -Uri "https://api.example.com/data" -Method GET
```

### POST Request
```powershell
$body = @{ key = "value" } | ConvertTo-Json
$response = Invoke-RestMethod -Uri "https://api.example.com/data" -Method POST -Body $body -ContentType "application/json"
```

## Example Task

```powershell
# tasks/etl/fetch_data.ps1
param(
    $Url = "https://api.example.com/data"
)

Write-Host "Fetching data from: $Url"

try {
    $response = Invoke-RestMethod -Uri $Url -Method GET -TimeoutSec 30
    
    return @{
        success = $true
        records = $response.data
        count = $response.data.Count
    }
}
catch {
    Write-Error "Failed to fetch: $_"
    throw
}
```

## Authentication

For authenticated APIs, use environment variables or secure storage:

```powershell
$headers = @{
    "Authorization" = "Bearer $env:API_TOKEN"
}
$response = Invoke-RestMethod -Uri $Url -Headers $headers
```
