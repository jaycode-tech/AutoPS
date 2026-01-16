# Quick Start

## Your First Job

### 1. Create a Task Script

Create `automations/tasks/demo/hello.ps1`:

```powershell
param($Name = "World")
Write-Host "Hello, $Name!"
```

### 2. Register in Manifest

Add to `automations/manifest.json`:

```json
{
  "tasks": {
    "hello": {
      "file": "tasks/demo/hello.ps1",
      "description": "Says hello"
    }
  },
  "jobs": {
    "my_first_job": {
      "file": "jobs/demo/my_first_job.json",
      "description": "My first job"
    }
  }
}
```

### 3. Create a Job Definition

Create `automations/jobs/demo/my_first_job.json`:

```json
{
  "name": "my_first_job",
  "description": "My first AutoPS job",
  "tasks": [
    {
      "name": "SayHello",
      "task": "hello",
      "params": {
        "Name": "AutoPS"
      }
    }
  ]
}
```

### 4. Run It!

```powershell
./autops.ps1 run my_first_job
```

Output:
```
[Info] Running job: my_first_job
[Info] Starting Job: my_first_job (ExecutionId: abc123...)
[Info] Starting Task: SayHello (using hello)
Hello, AutoPS!
[Info] Task SayHello completed in 150ms
[Info] Job my_first_job completed successfully
```

## What's Next?

- Learn about [Tasks](../concepts/tasks.md)
- Explore [Workflows](../concepts/workflows.md) for complex pipelines
- Use [Query](../cli/query.md) to monitor executions
