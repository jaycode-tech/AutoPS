# ETL Pipeline Example

This example demonstrates a complete Extract-Transform-Load pipeline using AutoPS.

## Architecture

```mermaid
graph LR
    A[Start] --> B[Extract]
    B --> C[Transform]
    C --> D[Load]
    D --> E[Notify]
```

## Files

### Task: fetch_data.ps1
```powershell
# automations/tasks/etl/fetch_data.ps1
param($Url = "https://api.example.com/data")

Write-Host "Fetching data from: $Url"
Start-Sleep -Seconds 1  # Simulate API call

return @{
    records = @(
        @{ id = 1; name = "Item 1" },
        @{ id = 2; name = "Item 2" }
    )
}
```

### Task: transform_data.ps1
```powershell
# automations/tasks/etl/transform_data.ps1
param($Records)

Write-Host "Transforming $($Records.Count) records..."
Start-Sleep -Seconds 1

$transformed = $Records | ForEach-Object {
    @{
        id = $_.id
        name = $_.name.ToUpper()
        processed = $true
    }
}

return @{ data = $transformed }
```

### Task: load_data.ps1
```powershell
# automations/tasks/etl/load_data.ps1
param($Data)

Write-Host "Loading $($Data.Count) records to database..."
Start-Sleep -Seconds 1

return @{ loaded = $Data.Count }
```

### Workflow: etl_pipeline.json
```json
{
  "name": "etl_pipeline",
  "description": "Extract-Transform-Load pipeline",
  "tasks": [
    {
      "name": "Extract",
      "task": "fetch_data"
    },
    {
      "name": "Transform",
      "task": "transform_data",
      "dependsOn": ["Extract"]
    },
    {
      "name": "Load",
      "task": "load_data",
      "dependsOn": ["Transform"]
    }
  ]
}
```

### Job: data_pipeline.json
```json
{
  "name": "data_pipeline",
  "description": "Full data processing pipeline",
  "cron": "0 * * * *",
  "tasks": [
    {
      "name": "Start",
      "task": "notify",
      "params": { "message": "Pipeline starting..." }
    }
  ],
  "workflows": [
    { "name": "ETL", "workflow": "etl_pipeline" }
  ],
  "jobs": [
    { "name": "Complete", "job": "notify_job" }
  ]
}
```

## Running

```powershell
./autops.ps1 run data_pipeline
```

## Output

```
[Info] Running job: data_pipeline
[Info] Starting Job: data_pipeline (ExecutionId: abc123...)
[Info] Starting Task: Start (using notify)
NOTIFICATION: Pipeline starting...
[Info] Task Start completed in 150ms
[Info] Starting Workflow: etl_pipeline
[Info] Starting Task: Extract (using fetch_data)
Fetching data from: https://api.example.com/data
[Info] Task Extract completed in 1180ms
[Info] Starting Task: Transform (using transform_data)
Transforming 2 records...
[Info] Task Transform completed in 1175ms
[Info] Starting Task: Load (using load_data)
Loading 2 records to database...
[Info] Task Load completed in 1182ms
[Info] Workflow etl_pipeline completed
[Info] Job data_pipeline completed successfully
```
