# Query Command

Query and monitor job, workflow, and task executions.

## Usage

```powershell
./autops.ps1 query [options]
```

## Options

| Parameter | Values | Default | Description |
|-----------|--------|---------|-------------|
| `-Type` | job, workflow, task, all | all | Filter by execution type |
| `-Status` | Running, Completed, Failed, Waiting, All | All | Filter by status |
| `-ExecutionId` | GUID | - | Query specific execution tree |
| `-Name` | string | - | Filter by name |
| `-StartedAfter` | datetime | - | Show executions after this time |
| `-StartedBefore` | datetime | - | Show executions before this time |
| `-Top` | integer | 10 | Limit number of results |
| `-Sort` | StartedAt, EndedAt, Status, RuntimeMs | StartedAt | Sort field |
| `-SortOrder` | Asc, Desc | Desc | Sort direction |

## Examples

### Recent Executions
```powershell
./autops.ps1 query -Top 20
```

### Failed Jobs Only
```powershell
./autops.ps1 query -Type job -Status Failed
```

### Running Tasks
```powershell
./autops.ps1 query -Type task -Status Running
```

### Executions After Time
```powershell
./autops.ps1 query -StartedAfter "2026-01-13 15:00:00"
```

### Query Execution Tree
```powershell
./autops.ps1 query -ExecutionId "abc123-def456-..."
```

This returns all related jobs, workflows, and tasks sharing the same ExecutionId.

## Output Fields

| Field | Description |
|-------|-------------|
| `ExecutionId` | Unique execution identifier |
| `Type` | job, workflow, or task |
| `Name` | Automation name |
| `Status` | Running, Completed, Failed, Waiting |
| `State` | Current state (e.g., "Waiting for: TaskA") |
| `StartedAt` | Execution start time |
| `RuntimeMs` | Duration in milliseconds |
