# Logs Command

Query and filter log entries from AutoPS log files.

## Usage

```powershell
./autops.ps1 logs [options]
```

## Options

| Parameter | Values | Default | Description |
|-----------|--------|---------|-------------|
| `-Level` | Info, Warn, Error, Debug, All | All | Filter by log level |
| `-After` | datetime | - | Show logs after this time |
| `-Before` | datetime | - | Show logs before this time |
| `-Keyword` | string | - | Search for text in log messages |
| `-Top` | integer | 10 | Limit number of results |

## Examples

### Recent Logs
```powershell
./autops.ps1 logs -Top 20
```

### Errors Only
```powershell
./autops.ps1 logs -Level Error
```

### Debug Messages
```powershell
./autops.ps1 logs -Level Debug -Top 50
```

### Logs After Time
```powershell
./autops.ps1 logs -After "2026-01-13 15:00:00"
```

### Search by Keyword
```powershell
./autops.ps1 logs -Keyword "Waiting for"
./autops.ps1 logs -Keyword "data_pipeline"
```

### Combined Filters
```powershell
./autops.ps1 logs -Level Error -After "2026-01-13 14:00:00" -Top 5
```

## Output

Logs are displayed with color-coded levels:

- **Info** - White
- **Warn** - Yellow
- **Error** - Red
- **Debug** - Gray

```
[2026-01-13 15:07:43] [Info] Starting Job: hello_world
[2026-01-13 15:07:43] [Error] Task failed: Connection refused
[2026-01-13 15:07:43] [Debug] Task Load is Waiting for: Transform
```

## Log File Location

Logs are stored in `logs/autops_YYYYMMDD.log` (one file per day).
