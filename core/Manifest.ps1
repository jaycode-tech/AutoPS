#Requires -Version 5.1
<#
.SYNOPSIS
    AutoPS Beta 0.5 - Manifest.ps1
    Loads and validates the automation manifest (tasks, workflows, jobs, integrations)

.DESCRIPTION
    This module handles all manifest-related operations:
    - Loading and parsing manifest.json
    - Pre-parse validation for duplicate JSON keys
    - Name validation (alphanumeric + underscore only)
    - Cross-type uniqueness validation
    - File existence verification
    - Individual item retrieval (tasks, workflows, jobs)
    
    The manifest is the central registry that maps automation names to their
    definition files and configuration.

.NOTES
    Manifest structure:
    {
        "tasks": { "task_name": { "file": "path.ps1", "runtime": "pwsh" } },
        "workflows": { "wf_name": { "file": "path.json" } },
        "jobs": { "job_name": { "file": "path.json" } },
        "integrations": { "name": { "type": "...", "core": true } }
    }
#>

# ============================================================================
# MODULE STATE
# Script-scoped variables to cache the loaded manifest
# ============================================================================
$script:Manifest = $null       # Cached manifest PSCustomObject
$script:ManifestPath = $null   # Path to manifest.json for relative file resolution

# ============================================================================
# INITIALIZATION & VALIDATION
# ============================================================================

function Initialize-AutoPSManifest {
    <#
    .SYNOPSIS
        Loads and validates the manifest file.
    .DESCRIPTION
        Performs comprehensive validation:
        1. Pre-parse: Detects duplicate JSON keys (before PowerShell silently merges)
        2. Name validation: All names must match ^[a-zA-Z0-9_]+$
        3. Uniqueness: No duplicate names across tasks/workflows/jobs
        4. File exists: Warns if referenced files are missing
    .PARAMETER Path
        Path to manifest.json (defaults to ../automations/manifest.json)
    .OUTPUTS
        Validated manifest PSCustomObject
    #>
    param([string]$Path)
    
    # Default path relative to this script's location
    if (-not $Path) {
        $Path = Join-Path $PSScriptRoot "../automations/manifest.json"
    }
    
    if (-not (Test-Path $Path)) {
        throw "Manifest not found at: $Path"
    }
    
    $script:ManifestPath = $Path
    $rawContent = Get-Content $Path -Raw
    
    # ========================================================================
    # PRE-PARSE VALIDATION: Detect duplicate JSON keys
    # PowerShell's ConvertFrom-Json silently overwrites duplicate keys,
    # which can cause confusing bugs. We detect them before parsing.
    # ========================================================================
    
    # Regex matches lines like: "keyName": { (key followed by opening brace)
    $keyPattern = '^\s*\"([^\"]+)\"\s*:\s*\{'
    $lines = $rawContent -split "`n"
    
    # Stack tracks keys at each nesting level
    $keyStack = [System.Collections.Generic.Stack[hashtable]]::new()
    $keyStack.Push(@{})  # Root level
    $duplicateKeys = @()
    
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        
        # Check for key definitions (object properties with { on same line)
        if ($line -match $keyPattern) {
            $key = $Matches[1]
            $currentScope = $keyStack.Peek()
            
            # Check if key already exists in current scope
            if ($currentScope.ContainsKey($key)) {
                $duplicateKeys += "Line $($i + 1): Duplicate key '$key' (first defined at line $($currentScope[$key]))"
            }
            else {
                $currentScope[$key] = $i + 1  # Store line number
            }
            
            # Push new scope for nested object
            $keyStack.Push(@{})
        }
        # Pop scope on closing brace
        elseif ($line -match '^\s*}') {
            if ($keyStack.Count -gt 1) { $keyStack.Pop() | Out-Null }
        }
    }
    
    if ($duplicateKeys.Count -gt 0) {
        throw "Manifest contains duplicate JSON keys:`n$($duplicateKeys -join "`n")"
    }
    
    # ========================================================================
    # PARSE JSON
    # ========================================================================
    $script:Manifest = $rawContent | ConvertFrom-Json
    
    # ========================================================================
    # NAME VALIDATION & UNIQUENESS CHECK
    # ========================================================================
    
    $allNames = @{}        # Track all names: { name: "type" }
    $duplicates = @()      # Duplicate name errors
    $invalidNames = @()    # Invalid character errors
    $nameRegex = '^[a-zA-Z0-9_]+$'  # Only letters, numbers, underscores
    
    # Validate task names
    foreach ($taskName in $script:Manifest.tasks.PSObject.Properties.Name) {
        if ($taskName -notmatch $nameRegex) {
            $invalidNames += "Task name '$taskName' contains invalid characters. Use only letters, numbers, and underscores."
        }
        if ($allNames.ContainsKey($taskName)) {
            $duplicates += "Duplicate name '$taskName' found in tasks (already defined as $($allNames[$taskName]))"
        }
        else {
            $allNames[$taskName] = "task"
        }
    }
    
    # Validate workflow names
    foreach ($wfName in $script:Manifest.workflows.PSObject.Properties.Name) {
        if ($wfName -notmatch $nameRegex) {
            $invalidNames += "Workflow name '$wfName' contains invalid characters. Use only letters, numbers, and underscores."
        }
        if ($allNames.ContainsKey($wfName)) {
            $duplicates += "Duplicate name '$wfName' found in workflows (already defined as $($allNames[$wfName]))"
        }
        else {
            $allNames[$wfName] = "workflow"
        }
    }
    
    # Validate job names
    foreach ($jobName in $script:Manifest.jobs.PSObject.Properties.Name) {
        if ($jobName -notmatch $nameRegex) {
            $invalidNames += "Job name '$jobName' contains invalid characters. Use only letters, numbers, and underscores."
        }
        if ($allNames.ContainsKey($jobName)) {
            $duplicates += "Duplicate name '$jobName' found in jobs (already defined as $($allNames[$jobName]))"
        }
        else {
            $allNames[$jobName] = "job"
        }
    }
    
    # Report invalid names
    if ($invalidNames.Count -gt 0) {
        foreach ($inv in $invalidNames) {
            Write-Error $inv
        }
        throw "Manifest contains invalid names. Names must only contain letters, numbers, and underscores."
    }
    
    # Report duplicates
    if ($duplicates.Count -gt 0) {
        foreach ($dup in $duplicates) {
            Write-Error $dup
        }
        throw "Manifest contains duplicate names. All tasks, workflows, and jobs must have unique names."
    }
    
    # ========================================================================
    # FILE EXISTENCE VALIDATION
    # Warn (don't error) if referenced files are missing
    # ========================================================================
    
    $basePath = Split-Path $Path -Parent
    $warnings = @()
    
    # Check task files
    foreach ($taskName in $script:Manifest.tasks.PSObject.Properties.Name) {
        $taskFile = Join-Path $basePath $script:Manifest.tasks.$taskName.file
        if (-not (Test-Path $taskFile)) {
            $warnings += "Task '$taskName' file not found: $taskFile"
        }
    }
    
    # Check workflow files
    foreach ($wfName in $script:Manifest.workflows.PSObject.Properties.Name) {
        $wfFile = Join-Path $basePath $script:Manifest.workflows.$wfName.file
        if (-not (Test-Path $wfFile)) {
            $warnings += "Workflow '$wfName' file not found: $wfFile"
        }
    }
    
    # Check job files
    foreach ($jobName in $script:Manifest.jobs.PSObject.Properties.Name) {
        $jobFile = Join-Path $basePath $script:Manifest.jobs.$jobName.file
        if (-not (Test-Path $jobFile)) {
            $warnings += "Job '$jobName' file not found: $jobFile"
        }
    }
    
    # Display warnings (non-fatal)
    foreach ($warn in $warnings) {
        Write-Warning $warn
    }
    
    return $script:Manifest
}

# ============================================================================
# MANIFEST RETRIEVAL
# ============================================================================

function Get-AutoPSManifest {
    <#
    .SYNOPSIS
        Returns the cached manifest object.
    .NOTES
        Must call Initialize-AutoPSManifest first.
    #>
    if (-not $script:Manifest) {
        throw "Manifest not initialized. Call Initialize-AutoPSManifest first."
    }
    return $script:Manifest
}

# ============================================================================
# TASK RETRIEVAL
# ============================================================================

function Get-AutoPSTask {
    <#
    .SYNOPSIS
        Retrieves a task definition by name.
    .PARAMETER Name
        Task name as defined in manifest
    .OUTPUTS
        PSCustomObject with Name, File (absolute path), Runtime, RuntimeEnv, Description
    #>
    param([string]$Name)
    
    $manifest = Get-AutoPSManifest
    $task = $manifest.tasks.$Name
    
    if (-not $task) {
        throw "Task '$Name' not found in manifest."
    }
    
    # Resolve file path relative to manifest location
    $basePath = Split-Path $script:ManifestPath -Parent
    return [PSCustomObject]@{
        Name        = $Name
        File        = Join-Path $basePath $task.file
        Runtime     = if ($task.runtime) { $task.runtime } else { "pwsh" }    # Default to PowerShell
        RuntimeEnv  = if ($task.runtimeEnv) { $task.runtimeEnv } else { "default" }
        Description = $task.description
    }
}

# ============================================================================
# WORKFLOW RETRIEVAL
# ============================================================================

function Get-AutoPSWorkflowDef {
    <#
    .SYNOPSIS
        Loads and validates a workflow definition JSON.
    .PARAMETER Name
        Workflow name as defined in manifest
    .OUTPUTS
        Parsed workflow definition with tasks, dependencies, etc.
    .NOTES
        Validates that step names don't match task references
        (prevents ambiguity in dependency resolution)
    #>
    param([string]$Name)
    
    $manifest = Get-AutoPSManifest
    $wf = $manifest.workflows.$Name
    
    if (-not $wf) {
        throw "Workflow '$Name' not found in manifest."
    }
    
    $basePath = Split-Path $script:ManifestPath -Parent
    $wfPath = Join-Path $basePath $wf.file
    
    # Parse workflow JSON
    $definition = Get-Content $wfPath -Raw | ConvertFrom-Json
    
    # Validate: step name cannot equal task reference (prevents confusion)
    if ($definition.tasks) {
        foreach ($step in $definition.tasks) {
            if ($step.name -eq $step.task) {
                throw "Workflow '$Name': Step name '$($step.name)' cannot be the same as task reference '$($step.task)'"
            }
        }
    }
    
    return $definition
}

# ============================================================================
# JOB RETRIEVAL
# ============================================================================

function Get-AutoPSJobDef {
    <#
    .SYNOPSIS
        Loads and validates a job definition JSON.
    .PARAMETER Name
        Job name as defined in manifest
    .OUTPUTS
        Parsed job definition with tasks, workflows, child jobs
    .NOTES
        Validates step names don't match their references
    #>
    param([string]$Name)
    
    $manifest = Get-AutoPSManifest
    $job = $manifest.jobs.$Name
    
    if (-not $job) {
        throw "Job '$Name' not found in manifest."
    }
    
    $basePath = Split-Path $script:ManifestPath -Parent
    $jobPath = Join-Path $basePath $job.file
    
    $definition = Get-Content $jobPath -Raw | ConvertFrom-Json
    
    # Validate: step names cannot equal their references
    if ($definition.tasks) {
        foreach ($step in $definition.tasks) {
            if ($step.name -eq $step.task) {
                throw "Job '$Name': Step name '$($step.name)' cannot be the same as task reference '$($step.task)'"
            }
        }
    }
    
    if ($definition.workflows) {
        foreach ($step in $definition.workflows) {
            if ($step.name -eq $step.workflow) {
                throw "Job '$Name': Step name '$($step.name)' cannot be the same as workflow reference '$($step.workflow)'"
            }
        }
    }
    
    if ($definition.jobs) {
        foreach ($step in $definition.jobs) {
            if ($step.name -eq $step.job) {
                throw "Job '$Name': Step name '$($step.name)' cannot be the same as job reference '$($step.job)'"
            }
        }
    }
    
    return $definition
}

# ============================================================================
# LIST FUNCTIONS
# Return summary objects for all items of each type
# ============================================================================

function Get-AutoPSJobs {
    <#
    .SYNOPSIS
        Returns a list of all jobs with summary info.
    .OUTPUTS
        Array of PSCustomObjects with Name, Description, TriggerType, TaskCount, WorkflowCount
    #>
    $manifest = Get-AutoPSManifest
    $jobs = @()
    
    foreach ($jobName in $manifest.jobs.PSObject.Properties.Name) {
        try {
            $jobDef = Get-AutoPSJobDef -Name $jobName
            $jobs += [PSCustomObject]@{
                Name          = $jobName
                Description   = $manifest.jobs.$jobName.description
                TriggerType   = $jobDef.triggerType
                TaskCount     = ($jobDef.tasks | Measure-Object).Count
                WorkflowCount = ($jobDef.workflows | Measure-Object).Count
            }
        }
        catch {
            Write-Warning "Failed to load job '$jobName': $_"
        }
    }
    
    return $jobs
}

function Get-AutoPSWorkflows {
    <#
    .SYNOPSIS
        Returns a list of all workflows with summary info.
    #>
    $manifest = Get-AutoPSManifest
    $workflows = @()
    
    foreach ($wfName in $manifest.workflows.PSObject.Properties.Name) {
        try {
            $wfDef = Get-AutoPSWorkflowDef -Name $wfName
            $workflows += [PSCustomObject]@{
                Name        = $wfName
                Description = $manifest.workflows.$wfName.description
                TaskCount   = ($wfDef.tasks | Measure-Object).Count
            }
        }
        catch {
            Write-Warning "Failed to load workflow '$wfName': $_"
        }
    }
    
    return $workflows
}

function Get-AutoPSTasks {
    <#
    .SYNOPSIS
        Returns a list of all tasks with summary info.
    #>
    $manifest = Get-AutoPSManifest
    $tasks = @()
    
    foreach ($taskName in $manifest.tasks.PSObject.Properties.Name) {
        $task = $manifest.tasks.$taskName
        $tasks += [PSCustomObject]@{
            Name        = $taskName
            Runtime     = if ($task.runtime) { $task.runtime } else { "pwsh" }
            Description = $task.description
        }
    }
    
    return $tasks
}
