#Requires -Version 5.1
<#
.SYNOPSIS
    AutoPS Beta 0.5 - PowerShell Automation Framework
    
.DESCRIPTION
    Main entry point for the AutoPS automation system. Provides CLI interface
    for running jobs, querying executions, viewing logs, and system initialization.
    
.PARAMETER Command
    The action to perform: run, submit, service, list, health, init, query, logs
    
.PARAMETER Name
    Name of the job/workflow to execute (used with 'run' command)
    
.PARAMETER Params
    Hashtable of parameters to pass to the job (e.g., -Params @{key="value"})

.EXAMPLE
    ./autops.ps1 init                           # Initialize and health check
    ./autops.ps1 run hello_world                # Run a job
    ./autops.ps1 query -Status Failed -Top 5    # Query failed executions
    ./autops.ps1 logs -Level Error              # View error logs
#>

# ============================================================================
# SCRIPT PARAMETERS
# ============================================================================
param(
    # Primary command to execute (defaults to 'health' which redirects to 'init')
    [Parameter(Position = 0)]
    [ValidateSet('run', 'submit', 'service', 'list', 'health', 'init', 'query', 'logs')]
    [string]$Command = 'health',
    
    # Name of job/workflow/task to run or query
    [Parameter(Position = 1)]
    [string]$Name,
    
    # Custom parameters passed to job execution
    [hashtable]$Params = @{},
    
    # ---- Query Command Parameters ----
    # Filter by execution type (job/workflow/task/all)
    [ValidateSet('job', 'workflow', 'task', 'all')]
    [string]$Type = 'all',
    
    # Filter by execution status
    [ValidateSet('Running', 'Completed', 'Failed', 'Waiting', 'All')]
    [string]$Status = 'All',
    
    # Query specific execution by GUID (returns full execution tree)
    [string]$ExecutionId,
    
    # Filter executions started after this datetime
    [datetime]$StartedAfter,
    
    # Filter executions started before this datetime
    [datetime]$StartedBefore,
    
    # Limit number of results returned
    [int]$Top = 10,
    
    # Field to sort results by
    [ValidateSet('StartedAt', 'EndedAt', 'Status', 'RuntimeMs')]
    [string]$Sort = 'StartedAt',
    
    # Sort direction (ascending or descending)
    [ValidateSet('Asc', 'Desc')]
    [string]$SortOrder = 'Desc',
    
    # ---- Logs Command Parameters ----
    # Filter logs by severity level
    [ValidateSet('Info', 'Warn', 'Error', 'Debug', 'All')]
    [string]$Level = 'All',
    
    # Show logs after this datetime
    [datetime]$After,
    
    # Show logs before this datetime
    [datetime]$Before,
    
    # Search for keyword in log messages
    [string]$Keyword
)

# Stop on any error to prevent partial execution
$ErrorActionPreference = 'Stop'

# Store script root for relative path resolution
$ScriptRoot = $PSScriptRoot

# ============================================================================
# LOAD CORE MODULES
# Dot-source required PowerShell modules in dependency order
# ============================================================================
. "$ScriptRoot/core/Utils.ps1"      # Utility functions, logging, config
. "$ScriptRoot/core/Database.ps1"   # SQL client and schema management
. "$ScriptRoot/core/Manifest.ps1"   # Manifest loading and validation
. "$ScriptRoot/core/Engine.ps1"     # Job/workflow/task execution engine

# ============================================================================
# INITIALIZATION
# Load configuration and set up logging
# ============================================================================

# Load application configuration from config.json
$config = Get-AutoPSConfig -ConfigPath "$ScriptRoot/config.json"

# Resolve log directory path (convert relative ./logs to absolute)
$logDir = Join-Path $ScriptRoot ($config.logging.directory -replace '^\\./', '')

# Initialize the logging system with configured directory
Initialize-AutoPSLogger -LogDir $logDir

Write-AutoPSLog -Message "AutoPS Beta 0.5 starting..." -Level 'Info' -NoConsole

try {
    Write-AutoPSLog -Message "Loading manifest..." -Level 'Info' -NoConsole
    Initialize-AutoPSManifest -Path "$ScriptRoot/automations/manifest.json" | Out-Null
    Write-AutoPSLog -Message "Manifest loaded successfully" -Level 'Info' -NoConsole
}
catch {
    Write-AutoPSLog -Message "Failed to load manifest: $_" -Level 'Error'
    exit 1
}

# ============================================================================
# DATABASE SETUP
# ============================================================================

$Client = $null

function Initialize-Database {
    $dbConfig = $config.database
    
    if ($dbConfig) {
        $connStr = $dbConfig.connectionString
        if ($connStr -match 'Data Source=\.\/') {
            $connStr = $connStr -replace '\./', "$ScriptRoot/"
        }
        
        $Client = [AutoPSSqlClient]::new($connStr, $dbConfig.provider)
        
        if (-not (Test-AutoPSDatabaseConnection -Client $Client)) {
            Write-AutoPSLog -Message "Database connection failed" -Level 'Warn'
            
            $response = Read-AutoPSPrompt -Message "Fallback to local JSON database? (Y/n)" -Default 'Y'
            if ($response -notmatch '^[Yy]') {
                throw "Database connection required. Exiting."
            }
            
            $localPath = Join-Path $ScriptRoot "data/autops.json"
            $Client = [AutoPSSqlClient]::new("Data Source=$localPath", 'Json')
        }
        
        if (-not (Test-AutoPSDatabaseSchema -Client $Client)) {
            Write-AutoPSLog -Message "Database schema not found" -Level 'Warn'
            
            $response = Read-AutoPSPrompt -Message "Initialize database schema? (Y/n)" -Default 'Y'
            if ($response -match '^[Yy]') {
                Initialize-AutoPSDatabase -Client $Client
                Write-AutoPSLog -Message "Database initialized" -Level 'Info'
            }
            else {
                Write-AutoPSLog -Message "Running without database." -Level 'Warn'
                $Client = $null
            }
        }
        
        return $Client
    }
    else {
        $localPath = Join-Path $ScriptRoot "data/autops.json"
        
        if (Test-Path $localPath) {
            Write-AutoPSLog -Message "Using existing local database" -Level 'Info'
            return [AutoPSSqlClient]::new("Data Source=$localPath", 'Json')
        }
        
        $response = Read-AutoPSPrompt -Message "No database configured. Create local database? (Y/n)" -Default 'Y'
        if ($response -match '^[Yy]') {
            $Client = [AutoPSSqlClient]::new("Data Source=$localPath", 'Json')
            Initialize-AutoPSDatabase -Client $Client
            Write-AutoPSLog -Message "Local database created" -Level 'Info'
            return $Client
        }
        
        return $null
    }
}

# ============================================================================
# HEALTH CHECKS
# ============================================================================

function Invoke-HealthChecks {
    Write-AutoPSLog -Message "Running integration health checks..." -Level 'Info' -NoConsole
    
    $integrations = $config.integrations
    if (-not $integrations -or $integrations.Count -eq 0) {
        Write-AutoPSLog -Message "No integrations configured" -Level 'Info' -NoConsole
        return $true
    }
    
    $results = Test-AutoPSIntegrations -Integrations $integrations -Silent
    
    if ($results.CoreFailure) {
        Write-AutoPSLog -Message "Core integration failure detected. Stopping." -Level 'Error'
        return $false
    }
    
    Write-AutoPSLog -Message "Health checks completed" -Level 'Info' -NoConsole
    return $true
}

# ============================================================================
# COMMAND HANDLERS
# ============================================================================

try {
    if ($Command -notin @('init', 'health', 'query', 'logs')) {
        if (-not (Invoke-HealthChecks)) {
            exit 1
        }
    }
    
    $Client = Initialize-Database
    
    switch ($Command) {
        'run' {
            if (-not $Name) { throw "Name required. Usage: autops.ps1 run <job|workflow|task> [-Params @{...}]" }
            
            $manifest = Get-AutoPSManifest
            
            # Check if it's a job
            if ($manifest.jobs.$Name) {
                Write-AutoPSLog -Message "Running job: $Name" -Level 'Info'
                Invoke-AutoPSJob -JobName $Name -Client $Client -InputParams $Params
            }
            # Check if it's a workflow
            elseif ($manifest.workflows.$Name) {
                Write-AutoPSLog -Message "Running workflow: $Name" -Level 'Info'
                Invoke-AutoPSWorkflow -WorkflowName $Name -InputParams $Params -Client $Client
            }
            # Check if it's a task
            elseif ($manifest.tasks.$Name) {
                Write-AutoPSLog -Message "Running task: $Name" -Level 'Info'
                $result = Invoke-AutoPSTask -TaskName $Name -InputParams $Params -Client $Client
                if ($result) {
                    Write-Host "`nOutput:" -ForegroundColor Cyan
                    $result | ConvertTo-Json -Depth 4 | Write-Host
                }
            }
            else {
                throw "Job, workflow, or task '$Name' not found in manifest."
            }
        }
        
        'submit' {
            if (-not $Name) { throw "Job name required. Usage: autops.ps1 submit <name>" }
            if (-not $Client) { throw "Database required for submit command." }
            
            $manifest = Get-AutoPSManifest
            if (-not $manifest.jobs.$Name) { throw "Job '$Name' not found." }
            
            $jobId = [Guid]::NewGuid().ToString()
            $Client.ExecuteNonQuery(
                "INSERT INTO Jobs (JobId, Name, TriggerType, Status, CreatedAt, CreatedBy, InputParams) VALUES (@JobId, @Name, 'Manual', 'Pending', @CreatedAt, 'Any', @InputParams)",
                @{
                    JobId       = $jobId
                    Name        = $Name
                    CreatedAt   = (Get-Date).ToString('o')
                    InputParams = ($Params | ConvertTo-Json -Compress)
                }
            )
            
            Write-AutoPSLog -Message "Job '$Name' submitted (ID: $jobId)" -Level 'Info'
            Show-AutoPSStatus -Component "Submit" -Success $true -Message "Job ID: $jobId"
        }
        
        'service' {
            if (-not $Client) { throw "Database required for service mode." }
            Start-AutoPSService -Client $Client -PollIntervalSeconds $config.service.pollIntervalSeconds
        }
        
        'list' {
            Write-Host "`n=== Jobs ===" -ForegroundColor Cyan
            $jobs = Get-AutoPSJobs
            if ($jobs) {
                $jobs | ForEach-Object {
                    Write-Host "  $($_.Name)" -ForegroundColor White
                    Write-Host "    Tasks: $($_.TaskCount), Workflows: $($_.WorkflowCount), Trigger: $($_.TriggerType)" -ForegroundColor Gray
                }
            }
            else { Write-Host "  (none)" -ForegroundColor Gray }
            
            Write-Host "`n=== Workflows ===" -ForegroundColor Cyan
            $workflows = Get-AutoPSWorkflows
            if ($workflows) {
                $workflows | ForEach-Object {
                    Write-Host "  $($_.Name)" -ForegroundColor White
                    Write-Host "    Tasks: $($_.TaskCount)" -ForegroundColor Gray
                }
            }
            else { Write-Host "  (none)" -ForegroundColor Gray }
            
            Write-Host "`n=== Tasks ===" -ForegroundColor Cyan
            $tasks = Get-AutoPSTasks
            if ($tasks) {
                $tasks | ForEach-Object {
                    Write-Host "  $($_.Name) [$($_.Runtime)]" -ForegroundColor White
                }
            }
            else { Write-Host "  (none)" -ForegroundColor Gray }
            
            Write-Host ""
        }
        
        'query' {
            if (-not $Client) { throw "Database required for query command." }
            
            # Get specific execution by ID
            if ($ExecutionId) {
                $results = Get-AutoPSExecution -Client $Client -ExecutionId $ExecutionId
                if ($results) {
                    Write-Host "`n=== Execution Details ===" -ForegroundColor Cyan
                    # Sort by StartedAt Ascending for execution tree (chronological)
                    $results = $results | Sort-Object -Property StartedAt
                    
                    $results | Format-Table -Property Type, Name, Status, State, @{Label = "StartedAt"; Expression = { if ($_.StartedAt) { Get-Date $_.StartedAt -Format "dd/MM/yyyy h:mm:ss.fff tt" }else { $null } } }, RuntimeMs, TriggerType -AutoSize
                }
                else {
                    Write-Host "No execution found with ID: $ExecutionId" -ForegroundColor Yellow
                }
            }
            else {
                # Query executions with filters
                $queryParams = @{
                    Client    = $Client
                    Type      = $Type
                    Status    = $Status
                    Top       = $Top
                    Sort      = $Sort
                    SortOrder = $SortOrder
                }
                
                if ($Name) { $queryParams.Name = $Name }
                if ($StartedAfter) { $queryParams.StartedAfter = $StartedAfter }
                if ($StartedBefore) { $queryParams.StartedBefore = $StartedBefore }
                
                $results = Get-AutoPSExecutions @queryParams
                
                if ($results -and $results.Count -gt 0) {
                    Write-Host "`n=== Executions ($($results.Count)) ===" -ForegroundColor Cyan
                    $results | Format-Table -Property ExecutionId, Type, Name, Status, State, @{Label = "StartedAt"; Expression = { if ($_.StartedAt) { Get-Date $_.StartedAt -Format "dd/MM/yyyy h:mm:ss.fff tt" }else { $null } } }, RuntimeMs -AutoSize
                }
                else {
                    Write-Host "No executions found matching criteria." -ForegroundColor Yellow
                }
            }
        }
        
        'health' {
            # Redirect to init for backwards compatibility
            Write-Host "Note: 'health' is now part of 'init' command" -ForegroundColor Yellow
        }
        
        'init' {
            Write-Host ""
            Write-Host "  ╔═══════════════════════════════════════╗" -ForegroundColor Cyan
            Write-Host "  ║        AutoPS Initialization          ║" -ForegroundColor Cyan
            Write-Host "  ╚═══════════════════════════════════════╝" -ForegroundColor Cyan
            Write-Host ""
            
            # 1. Manifest check
            try {
                $manifest = Get-AutoPSManifest
                $taskCount = ($manifest.tasks.PSObject.Properties | Measure-Object).Count
                $wfCount = ($manifest.workflows.PSObject.Properties | Measure-Object).Count
                $jobCount = ($manifest.jobs.PSObject.Properties | Measure-Object).Count
                Write-Host "  [✓] Manifest" -ForegroundColor Green -NoNewline
                Write-Host "  ($taskCount tasks, $wfCount workflows, $jobCount jobs)" -ForegroundColor Gray
            }
            catch {
                Write-Host "  [✗] Manifest - $_" -ForegroundColor Red
            }
            
            # 2. Database initialization
            $Client = Initialize-Database
            if ($Client) {
                Write-Host "  [✓] Database" -ForegroundColor Green -NoNewline
                Write-Host "  ($($config.database.provider))" -ForegroundColor Gray
            }
            else {
                Write-Host "  [✗] Database - Not connected" -ForegroundColor Red
            }
            
            # 3. Integrations check
            if ($manifest.integrations) {
                Write-Host ""
                Write-Host "  Integrations:" -ForegroundColor White
                foreach ($intName in $manifest.integrations.PSObject.Properties.Name) {
                    $int = $manifest.integrations.$intName
                    $coreTag = if ($int.core) { "[CORE]" } else { "" }
                    
                    $success = $true
                    switch ($int.type) {
                        'LocalFilesystem' { $success = Test-Path $ScriptRoot }
                        'Git' { $success = $null -ne (Get-Command git -ErrorAction SilentlyContinue) }
                        'Http' { $success = $true }
                    }
                    
                    if ($success) {
                        Write-Host "  [✓] $intName $coreTag" -ForegroundColor Green
                    }
                    else {
                        Write-Host "  [✗] $intName $coreTag" -ForegroundColor Red
                    }
                }
            }
            
            # 4. Verify Runtimes from runtime.json
            Write-Host ""
            Write-Host "  Runtimes:" -ForegroundColor White
            $runtimeConfig = Get-AutoPSRuntimeConfig
            
            foreach ($runtimeType in $runtimeConfig.PSObject.Properties) {
                $typeName = $runtimeType.Name
                foreach ($env in $runtimeType.Value.PSObject.Properties) {
                    $envName = $env.Name
                    $runtimePath = $env.Value
                    
                    # Skip system commands (no ./ prefix)
                    if ($runtimePath -notmatch '^\./') {
                        continue
                    }
                    
                    $fullPath = Join-Path $ScriptRoot $runtimePath.TrimStart('./')
                    if (Test-Path $fullPath) {
                        Write-Host "  [✓] $typeName/$envName" -ForegroundColor Green
                    }
                    else {
                        Write-Host "  [✗] $typeName/$envName" -ForegroundColor Red
                    }
                }
            }
            
            # 5. Build Documentation (if enabled in config)
            $configPath = Join-Path $ScriptRoot "config.json"
            if (Test-Path $configPath) {
                $appConfig = Get-Content $configPath -Raw | ConvertFrom-Json
                
                if ($appConfig.documentation -and $appConfig.documentation.enabled) {
                    Write-Host ""
                    Write-Host "  Documentation:" -ForegroundColor White
                    
                    $docsRuntime = $appConfig.documentation.runtime
                    $docsConfig = $appConfig.documentation.configPath
                    $docsOutput = $appConfig.documentation.outputPath
                    
                    $pythonPath = Get-RuntimePath -Runtime "python" -Env $docsRuntime
                    if ($pythonPath -match '^\./') {
                        $mkdocsPath = $pythonPath -replace '/python$', '/mkdocs'
                        $mkdocsPath = Join-Path $ScriptRoot $mkdocsPath.TrimStart('./')
                    }
                    else {
                        $mkdocsPath = "mkdocs"
                    }
                    
                    if (Test-Path $mkdocsPath) {
                        try {
                            $configFile = Join-Path $ScriptRoot $docsConfig.TrimStart('./')
                            $outputDir = Join-Path $ScriptRoot $docsOutput.TrimStart('./')
                            
                            & $mkdocsPath build -f $configFile -d $outputDir 2>&1 | Out-Null
                            Write-Host "  [✓] Built to $docsOutput" -ForegroundColor Green
                        }
                        catch {
                            Write-Host "  [✗] Build failed: $_" -ForegroundColor Red
                        }
                    }
                    else {
                        Write-Host "  [✗] mkdocs not found" -ForegroundColor Red
                    }
                }
            }
            
            Write-Host ""
            Write-Host "  Initialization complete." -ForegroundColor Cyan
            Write-Host ""
        }
        
        'logs' {
            # Find log files
            $logFiles = Get-ChildItem -Path $logDir -Filter "autops_*.log" -ErrorAction SilentlyContinue | Sort-Object Name -Descending
            
            if (-not $logFiles) {
                Write-Host "No log files found in $logDir" -ForegroundColor Yellow
                return
            }
            
            # Parse log pattern: [YYYY-MM-DD HH:mm:ss] [Level] Message
            $logPattern = '^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] \[(\w+)\] (.*)$'
            $results = @()
            
            foreach ($file in $logFiles) {
                $lines = Get-Content $file.FullName
                foreach ($line in $lines) {
                    if ($line -match $logPattern) {
                        $timestamp = [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd HH:mm:ss', $null)
                        $logLevel = $Matches[2]
                        $message = $Matches[3]
                        
                        # Apply filters
                        if ($Level -ne 'All' -and $logLevel -ne $Level) { continue }
                        if ($After -and $timestamp -lt $After) { continue }
                        if ($Before -and $timestamp -gt $Before) { continue }
                        if ($Keyword -and $message -notmatch [regex]::Escape($Keyword)) { continue }
                        
                        $results += [PSCustomObject]@{
                            Timestamp = $timestamp
                            Level     = $logLevel
                            Message   = $message
                            File      = $file.Name
                        }
                    }
                }
            }
            
            # Sort and limit
            $results = $results | Sort-Object Timestamp -Descending | Select-Object -First $Top
            
            if ($results.Count -gt 0) {
                Write-Host "`n=== Logs ($($results.Count)) ===" -ForegroundColor Cyan
                foreach ($log in $results) {
                    $color = switch ($log.Level) {
                        'Error' { 'Red' }
                        'Warn'  { 'Yellow' }
                        'Debug' { 'DarkGray' }
                        default { 'White' }
                    }
                    $ts = $log.Timestamp.ToString('yyyy-MM-dd HH:mm:ss')
                    Write-Host "[$ts] " -NoNewline -ForegroundColor Gray
                    Write-Host "[$($log.Level)]" -NoNewline -ForegroundColor $color
                    Write-Host " $($log.Message)"
                }
                Write-Host ""
            }
            else {
                Write-Host "No logs found matching criteria." -ForegroundColor Yellow
            }
        }
    }
    
    Write-AutoPSLog -Message "Command '$Command' completed" -Level 'Info' -NoConsole
}
catch {
    Write-AutoPSLog -Message "Fatal error: $_" -Level 'Error'
    exit 1
}
