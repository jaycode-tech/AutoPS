# Installation

## Requirements

- PowerShell 5.1 or higher
- Windows, macOS, or Linux

## Setup

1. **Clone or download** the AutoPS directory to your system

2. **Verify installation**:
   ```powershell
   cd /path/to/AutoPS
   ./autops.ps1
   ```

3. **Initialize the database**:
   ```powershell
   ./autops.ps1 init
   ```

## Directory Structure

```
AutoPS/
├── autops.ps1           # Main entry point
├── config.json          # Configuration
├── core/                # Core modules
│   ├── Database.ps1     # SQL client
│   ├── Engine.ps1       # Execution engine
│   ├── Manifest.ps1     # Manifest loader
│   └── Utils.ps1        # Utilities
├── automations/         # Your automations
│   ├── manifest.json    # Manifest definition
│   ├── tasks/           # Task scripts
│   ├── workflows/       # Workflow definitions
│   └── jobs/            # Job definitions
├── data/                # Database storage
└── logs/                # Log files
```

## Configuration

Edit `config.json` to customize:

```json
{
  "database": {
    "provider": "Json",
    "connectionString": "Data Source=./data/autops.json"
  },
  "logging": {
    "level": "Info",
    "directory": "./logs"
  }
}
```
