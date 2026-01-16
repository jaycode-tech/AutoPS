# Manifest

The manifest (`automations/manifest.json`) is the central registry for all tasks, workflows, jobs, and integrations.

## Structure

```json
{
  "tasks": { ... },
  "workflows": { ... },
  "jobs": { ... },
  "integrations": { ... }
}
```

## Tasks Section

```json
{
  "tasks": {
    "task_name": {
      "file": "tasks/category/script.ps1",
      "description": "What this task does"
    }
  }
}
```

## Workflows Section

```json
{
  "workflows": {
    "workflow_name": {
      "file": "workflows/category/definition.json",
      "description": "Workflow description"
    }
  }
}
```

## Jobs Section

```json
{
  "jobs": {
    "job_name": {
      "file": "jobs/category/definition.json",
      "description": "Job description"
    }
  }
}
```

## Integrations Section

```json
{
  "integrations": {
    "filesystem": {
      "type": "LocalFilesystem",
      "core": true
    },
    "git": {
      "type": "Git",
      "config": {
        "defaultBranch": "main"
      }
    }
  }
}
```

## Naming Rules

Names must follow these rules:

- ✅ Alphanumeric and underscores only: `my_task`, `task123`
- ❌ No hyphens: `my-task`
- ❌ No spaces: `my task`
- ❌ No special characters: `my@task`

## Validation

The manifest is validated on load:

1. **Duplicate key detection** - No duplicate JSON keys
2. **Name validation** - Names match `^[a-zA-Z0-9_]+$`
3. **Cross-type uniqueness** - Names must be unique across tasks, workflows, and jobs
4. **File existence** - Referenced files must exist
