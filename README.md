<p align="center">
  <img src="docs/src/assets/AutoPSLogo.png" alt="AutoPS Logo" width="120">
</p>

<h1 align="center">AutoPS Beta 0.5</h1>

<p align="center">
  <strong>PowerShell Automation Framework</strong><br>
  Orchestrate tasks, workflows, and jobs with multi-language runtime support
</p>

<p align="center">
  <a href="#-features">Features</a> •
  <a href="#-quick-start">Quick Start</a> •
  <a href="#-commands">Commands</a> •
  <a href="#-documentation">Docs</a> •
  <a href="#-architecture">Architecture</a>
</p>

---

## ✨ Features

| Feature | Description |
|---------|-------------|
| 🚀 **Task Automation** | Define reusable PowerShell tasks |
| 🔄 **Workflow Orchestration** | Chain tasks with dependency management |
| 📅 **Job Scheduling** | Execute jobs manually or via cron |
| 🔁 **Retry Logic** | Configurable retries with delays |
| 📊 **Execution Tracking** | Query and monitor all executions |
| 📝 **Structured Logging** | Filter logs by level, time, keywords |
| 🌐 **Multi-Runtime** | Support for Python, Node.js, and more |
| 📦 **Manifest-Driven** | JSON-based configuration |

---

## 🚀 Quick Start

### Prerequisites

- PowerShell 5.1 or higher
- Windows, macOS, or Linux

### Installation

```bash
git clone https://github.com/yourusername/AutoPS.git
cd AutoPS
```

### Initialize

```powershell
./autops.ps1 init
```

This validates your manifest, initializes the database, checks integrations and runtimes, and builds documentation.

### Run Your First Job

```powershell
./autops.ps1 run hello_world
```

---

## 🔧 Commands

### Initialization & Health

```powershell
./autops.ps1 init              # Initialize and health check
```

### Running Jobs

```powershell
./autops.ps1 run <job_name>                     # Run a job
./autops.ps1 run data_pipeline -Params @{       # Run with parameters
    env = "production"
    debug = $true
}
```

### Querying Executions

```powershell
./autops.ps1 query                              # Recent 10 executions
./autops.ps1 query -Top 50                      # More results
./autops.ps1 query -Status Failed               # Failed only
./autops.ps1 query -Type job                    # Jobs only
./autops.ps1 query -Type task -Status Running   # Running tasks
./autops.ps1 query -ExecutionId <guid>          # Full execution tree
./autops.ps1 query -Sort RuntimeMs -SortOrder Desc  # Slowest first
```

### Viewing Logs

```powershell
./autops.ps1 logs                               # Recent 10 logs
./autops.ps1 logs -Level Error                  # Errors only
./autops.ps1 logs -Level Warn -Top 50           # Warnings
./autops.ps1 logs -Keyword "pipeline"           # Search
./autops.ps1 logs -After "2026-01-16 10:00:00"  # Time filter
```

### Listing Automations

```powershell
./autops.ps1 list                               # All automations
./autops.ps1 list -Type jobs                    # Jobs only
./autops.ps1 list -Type tasks                   # Tasks only
```

---

## 📐 Architecture

```
AutoPS/
├── autops.ps1              # Main entry point (CLI)
├── config.json             # Application configuration
├── runtime.json            # Multi-language runtime paths
├── mkdocs.yml              # Documentation config
│
├── core/                   # Core modules
│   ├── Database.ps1        # SQL client (SQLite/JSON/PostgreSQL)
│   ├── Engine.ps1          # Execution engine
│   ├── Manifest.ps1        # Manifest loader & validator
│   ├── TaskWrapper.ps1     # Task isolation wrapper
│   └── Utils.ps1           # Utilities & logging
│
├── automations/            # Your automations
│   ├── manifest.json       # Central registry
│   ├── tasks/              # Task scripts (.ps1)
│   ├── workflows/          # Workflow definitions (.json)
│   └── jobs/               # Job definitions (.json)
│
├── docs/                   # Documentation (MkDocs)
│   ├── src/                # Markdown source
│   └── site/               # Built HTML (gitignored)
│
├── runtimes/               # Language runtimes (gitignored)
│   └── python/
│       └── mkdocs_3.13/    # Python venv for MkDocs
│
├── data/                   # Database storage (gitignored)
└── logs/                   # Log files (gitignored)
```

### Execution Flow

```
Job Execution
    │
    ├── Inline Tasks
    │       └── PowerShell scripts via TaskWrapper
    │
    ├── Workflows
    │       └── Ordered tasks with dependencies
    │           └── "Waiting for: TaskA, TaskB"
    │
    └── Child Jobs
            └── Recursive job invocation
```

### Shared ExecutionId

All related executions (Job → Workflow → Tasks) share a single ExecutionId:

```
ExecutionId: abc123-def456...
├── Job: data_pipeline
├── Workflow: etl_pipeline
├── Task: Extract
├── Task: Transform
└── Task: Load
```

---

## 📚 Documentation

Full documentation is available in the `docs/` directory.

### Build & Serve Docs

```bash
# Install dependencies (one-time)
python3 -m venv runtimes/python/mkdocs_3.13
./runtimes/python/mkdocs_3.13/bin/pip install -r docs/requirements.txt

# Serve locally
./runtimes/python/mkdocs_3.13/bin/mkdocs serve

# Build static site
./runtimes/python/mkdocs_3.13/bin/mkdocs build
```

Visit `http://127.0.0.1:8000` for live preview.

---

## 🔗 Concepts

### Tasks

Atomic units of work. PowerShell scripts that receive input and return output:

```powershell
# tasks/demo/hello.ps1
param($Name = "World")
Write-Host "Hello, $Name!"
return @{ greeted = $Name }
```

### Workflows

Orchestrate multiple tasks with dependencies:

```json
{
  "name": "etl_pipeline",
  "tasks": [
    { "name": "Extract", "task": "fetch_data" },
    { "name": "Transform", "task": "transform_data", "dependsOn": ["Extract"] },
    { "name": "Load", "task": "load_data", "dependsOn": ["Transform"] }
  ]
}
```

### Jobs

Top-level execution units that combine tasks, workflows, and child jobs:

```json
{
  "name": "data_pipeline",
  "tasks": [{ "name": "Start", "task": "notify" }],
  "workflows": [{ "name": "ETL", "workflow": "etl_pipeline" }],
  "jobs": [{ "name": "Cleanup", "job": "cleanup_job" }]
}
```

---

## ⚙️ Configuration

### config.json

```json
{
  "database": {
    "provider": "Json",
    "connectionString": "Data Source=./data/autops.json"
  },
  "logging": {
    "level": "Info",
    "directory": "./logs"
  },
  "documentation": {
    "enabled": true,
    "runtime": "mkdocs_3.13"
  }
}
```

### runtime.json

Map language runtimes to executables:

```json
{
  "pwsh": { "default": "pwsh" },
  "python": {
    "default": "python3",
    "mkdocs_3.13": "./runtimes/python/mkdocs_3.13/bin/python"
  },
  "node": { "default": "node" }
}
```

---

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing`)
5. Open a Pull Request

---

## 📄 License

MIT License - See [LICENSE](LICENSE) file for details.

---

<p align="center">
  Made with ❤️ for automation enthusiasts
</p>
