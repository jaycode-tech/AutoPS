# CLI Commands Reference

Complete reference for all AutoPS Beta 0.5 CLI commands with examples.

## Usage Syntax

```powershell
./autops.ps1 <command> [options]
```

---

## Commands Overview

| Command | Description |
|---------|-------------|
| `init` | Initialize system and run health checks |
| `run` | Execute a job immediately |
| `query` | Query execution history |
| `logs` | View and filter log entries |
| `list` | List available automations |
| `submit` | Submit job for async execution |
| `service` | Run in daemon/service mode |
| `health` | *(Deprecated)* Use `init` instead |

---

## init

Initializes the system: validates manifest, database, integrations, runtimes, and builds documentation.

### Examples

```powershell
# Full initialization with health checks
./autops.ps1 init
```

### Output

```
  ╔═══════════════════════════════════════╗
  ║        AutoPS Initialization          ║
  ╚═══════════════════════════════════════╝

  [✓] Manifest  (8 tasks, 1 workflows, 5 jobs)
  [✓] Database  (Json)

  Integrations:
  [✓] filesystem [CORE]
  [✓] git
  [✓] http

  Runtimes:
  [✓] python/mkdocs_3.13

  Documentation:
  [✓] Built to ./docs/site

  Initialization complete.
```

---

## run

Executes a job immediately and displays output.

### Syntax

```powershell
./autops.ps1 run <job_name> [-Params @{...}]
```

### Examples

```powershell
# Run a simple job
./autops.ps1 run hello_world

# Run with parameters
./autops.ps1 run data_pipeline -Params @{ env = "production" }

# Run with multiple parameters
./autops.ps1 run data_pipeline -Params @{ 
    env = "staging"
    debug = $true
    maxRetries = 5 
}

# Run ETL job
./autops.ps1 run etl_job

# Run notification job
./autops.ps1 run notify_job

# Run retry test job
./autops.ps1 run retry_job
```

---

## query

Query and filter execution history.

### Syntax

```powershell
./autops.ps1 query [options]
```

### Parameters

| Parameter | Values | Default | Description |
|-----------|--------|---------|-------------|
| `-Type` | `job`, `workflow`, `task`, `all` | `all` | Filter by type |
| `-Status` | `Running`, `Completed`, `Failed`, `Waiting`, `All` | `All` | Filter by status |
| `-ExecutionId` | GUID | - | Get specific execution tree |
| `-Name` | string | - | Filter by name |
| `-StartedAfter` | datetime | - | Filter by start time |
| `-StartedBefore` | datetime | - | Filter by start time |
| `-Top` | integer | `10` | Limit results |
| `-Sort` | `StartedAt`, `EndedAt`, `Status`, `RuntimeMs` | `StartedAt` | Sort field |
| `-SortOrder` | `Asc`, `Desc` | `Desc` | Sort direction |

### Examples - Basic Queries

```powershell
# List recent executions (default: top 10)
./autops.ps1 query

# List more results
./autops.ps1 query -Top 50

# List only jobs
./autops.ps1 query -Type job

# List only workflows
./autops.ps1 query -Type workflow

# List only tasks
./autops.ps1 query -Type task
```

### Examples - Status Filters

```powershell
# All failed executions
./autops.ps1 query -Status Failed

# All running executions
./autops.ps1 query -Status Running

# All waiting executions
./autops.ps1 query -Status Waiting

# All completed executions
./autops.ps1 query -Status Completed

# Failed jobs only
./autops.ps1 query -Type job -Status Failed

# Running tasks only
./autops.ps1 query -Type task -Status Running
```

### Examples - Time Filters

```powershell
# Executions after specific time
./autops.ps1 query -StartedAfter "2026-01-16 10:00:00"

# Executions before specific time
./autops.ps1 query -StartedBefore "2026-01-16 18:00:00"

# Executions in time range
./autops.ps1 query -StartedAfter "2026-01-16 09:00:00" -StartedBefore "2026-01-16 17:00:00"

# Today's failures
./autops.ps1 query -Status Failed -StartedAfter (Get-Date).Date
```

### Examples - Sorting

```powershell
# Sort by runtime (slowest first)
./autops.ps1 query -Sort RuntimeMs -SortOrder Desc

# Sort by runtime (fastest first)
./autops.ps1 query -Sort RuntimeMs -SortOrder Asc

# Sort by end time
./autops.ps1 query -Sort EndedAt -SortOrder Desc

# Sort by status
./autops.ps1 query -Sort Status

# Oldest executions first
./autops.ps1 query -SortOrder Asc
```

### Examples - Execution Tree

```powershell
# Get full execution tree by ID (shows job + workflows + tasks)
./autops.ps1 query -ExecutionId "abc12345-def6-7890-abcd-ef1234567890"
```

### Examples - Combined Filters

```powershell
# Failed jobs in last hour, sorted by runtime
./autops.ps1 query -Type job -Status Failed -StartedAfter ((Get-Date).AddHours(-1)) -Sort RuntimeMs

# Top 5 slowest completed tasks
./autops.ps1 query -Type task -Status Completed -Sort RuntimeMs -SortOrder Desc -Top 5

# All workflow executions today
./autops.ps1 query -Type workflow -StartedAfter (Get-Date).Date -Top 100
```

---

## logs

View and filter log entries.

### Syntax

```powershell
./autops.ps1 logs [options]
```

### Parameters

| Parameter | Values | Default | Description |
|-----------|--------|---------|-------------|
| `-Level` | `Info`, `Warn`, `Error`, `Debug`, `All` | `All` | Filter by severity |
| `-After` | datetime | - | Logs after this time |
| `-Before` | datetime | - | Logs before this time |
| `-Keyword` | string | - | Search in message text |
| `-Top` | integer | `10` | Limit results |

### Examples - Level Filters

```powershell
# All recent logs
./autops.ps1 logs

# More logs
./autops.ps1 logs -Top 50

# Errors only
./autops.ps1 logs -Level Error

# Warnings only
./autops.ps1 logs -Level Warn

# Info only
./autops.ps1 logs -Level Info

# Debug messages
./autops.ps1 logs -Level Debug -Top 100
```

### Examples - Time Filters

```powershell
# Logs after specific time
./autops.ps1 logs -After "2026-01-16 12:00:00"

# Logs before specific time
./autops.ps1 logs -Before "2026-01-16 13:00:00"

# Logs in time range
./autops.ps1 logs -After "2026-01-16 12:00:00" -Before "2026-01-16 13:00:00"

# Today's logs
./autops.ps1 logs -After (Get-Date).Date -Top 100
```

### Examples - Keyword Search

```powershell
# Search for job name
./autops.ps1 logs -Keyword "data_pipeline"

# Search for specific task
./autops.ps1 logs -Keyword "Transform"

# Search for dependency states
./autops.ps1 logs -Keyword "Waiting for"

# Search for errors containing text
./autops.ps1 logs -Level Error -Keyword "connection"

# Search for retries
./autops.ps1 logs -Keyword "Retrying"
```

### Examples - Combined Filters

```powershell
# Errors in last hour
./autops.ps1 logs -Level Error -After ((Get-Date).AddHours(-1))

# Warnings about specific job today
./autops.ps1 logs -Level Warn -Keyword "etl" -After (Get-Date).Date

# Debug logs for troubleshooting
./autops.ps1 logs -Level Debug -After "2026-01-16 13:00:00" -Top 200
```

---

## list

List available automations registered in the manifest.

### Syntax

```powershell
./autops.ps1 list [-Type <type>]
```

### Examples

```powershell
# List all (jobs, workflows, tasks)
./autops.ps1 list

# List only jobs
./autops.ps1 list -Type jobs

# List only workflows
./autops.ps1 list -Type workflows

# List only tasks
./autops.ps1 list -Type tasks
```

---

## submit

Submit a job for asynchronous execution (returns immediately).

### Syntax

```powershell
./autops.ps1 submit <job_name> [-Params @{...}]
```

### Examples

```powershell
# Submit job for background execution
./autops.ps1 submit data_pipeline

# Submit with parameters
./autops.ps1 submit etl_job -Params @{ source = "api" }
```

---

## service

Run AutoPS in service/daemon mode for scheduled job execution.

### Syntax

```powershell
./autops.ps1 service
```

### Examples

```powershell
# Start service mode
./autops.ps1 service

# Run in background (Unix)
nohup pwsh ./autops.ps1 service &

# Run as background job (PowerShell)
Start-Job { ./autops.ps1 service }
```

---

## Quick Reference Card

```powershell
# Initialization
./autops.ps1 init

# Run jobs
./autops.ps1 run <job_name>
./autops.ps1 run <job_name> -Params @{ key = "value" }

# Query executions
./autops.ps1 query                              # Recent 10
./autops.ps1 query -Top 50                      # More results
./autops.ps1 query -Status Failed               # Failed only
./autops.ps1 query -Type job                    # Jobs only
./autops.ps1 query -ExecutionId <guid>          # Full tree

# View logs  
./autops.ps1 logs                               # Recent 10
./autops.ps1 logs -Level Error                  # Errors only
./autops.ps1 logs -Keyword "text"               # Search

# List automations
./autops.ps1 list
./autops.ps1 list -Type jobs
```
