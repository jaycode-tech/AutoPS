# Retry Logic Example

This example demonstrates AutoPS retry logic for handling transient failures.

## Use Case

APIs and external services can fail temporarily. Instead of failing the entire pipeline, AutoPS can automatically retry failed tasks.

## Configuration

```json
{
  "name": "RetryTest",
  "task": "unstable_api",
  "retries": 3,
  "retry_delay": 10
}
```

| Parameter | Value | Description |
|-----------|-------|-------------|
| `retries` | 3 | Try up to 3 times after initial failure |
| `retry_delay` | 10 | Wait 10 seconds between attempts |

## Example Task

```powershell
# automations/tasks/tests/retry_test.ps1
$attempt = $env:AUTOPS_ATTEMPT
if (-not $attempt) { $attempt = 1 }

if ($attempt -lt 3) {
    Write-Host "Simulating Failure (Attempt $attempt)..."
    exit 1
}

Write-Host "Success on Attempt $attempt!"
exit 0
```

## Job Definition

```json
{
  "name": "retry_job",
  "description": "Test retry logic",
  "tasks": [
    {
      "name": "RetryTest",
      "task": "retry_test",
      "retries": 4,
      "retry_delay": 2
    }
  ]
}
```

## Running

```powershell
./autops.ps1 run retry_job
```

## Output

```
[Info] Running job: retry_job
[Info] Starting Task: RetryTest (using retry_test)
Simulating Failure (Attempt 1)...
[Warn] Task attempted 1 failed with ExitCode 1
Task failed. Retrying in 2 seconds (Attempt 2/5)...
Simulating Failure (Attempt 2)...
[Warn] Task attempted 2 failed with ExitCode 1
Task failed. Retrying in 2 seconds (Attempt 3/5)...
Success on Attempt 3!
[Info] Task RetryTest completed in 6500ms
[Info] Job retry_job completed successfully
```

## State Tracking

During retries, the task state shows the retry status:

```
State: Retrying (Attempt 2/5)
State: Retrying (Attempt 3/5)
```

## Viewing Retry Logs

```powershell
./autops.ps1 logs -Keyword "Retrying"
./autops.ps1 logs -Level Warn
```

## Best Practices

1. **Set appropriate delays** - APIs may need time to recover
2. **Limit retries** - Don't retry indefinitely (3-5 is typical)
3. **Log failures** - Monitor retry patterns to identify systemic issues
4. **Idempotent tasks** - Ensure tasks can safely re-run
