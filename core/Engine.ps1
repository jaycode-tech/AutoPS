#Requires -Version 5.1
<#
.SYNOPSIS
    AutoPS Beta 0.5 - Engine.ps1
    Process-based execution engine with isolated task runtimes

.DESCRIPTION
    This module contains the core execution logic for AutoPS:
    
    Task Execution (Invoke-AutoPSTask):
    - Runs tasks in isolated processes via TaskWrapper.ps1
    - Supports multi-language runtimes (pwsh, python, node, etc.)
    - Handles retry logic with configurable attempts and delays
    - Tracks execution state and updates database records
    - Captures stdout/stderr and return values
    
    Workflow Execution (Invoke-AutoPSWorkflow):
    - Orchestrates multiple tasks with dependency resolution
    - Updates task state to show "Waiting for: TaskA, TaskB"
    - Passes context between tasks (output of one = input to next)
    
    Job Execution (Invoke-AutoPSJob):
    - Top-level execution unit combining tasks, workflows, child jobs
    - Generates shared ExecutionId for entire execution tree
    - Records trigger type (Manual, Scheduled, Invoked by X)
    
    Query Functions:
    - Get-AutoPSExecutions: List executions with filters
    - Get-AutoPSExecution: Get single execution with full tree
    
    Node Management:
    - Register-AutoPSNode: Register this machine as execution node

.NOTES
    All executions share a single ExecutionId GUID for traceability.
    Tasks run in separate processes for isolation and multi-language support.
    The TaskWrapper.ps1 handles JSON I/O between Engine and task scripts.

.EXAMPLE
    # Run a job
    Invoke-AutoPSJob -JobName "data_pipeline" -Client $client
    
    # Query executions
    Get-AutoPSExecutions -Client $client -Status "Failed" -Top 5
#>

# ============================================================================
# TASK EXECUTION (IN SEPARATE PROCESS)
# Runs individual tasks with process isolation and retry logic
# ============================================================================

function Invoke-AutoPSTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TaskName,
        
        [hashtable]$InputParams = @{},
        [hashtable]$InputContext = @{},
        
        $Client,
        [string]$JobName,
        [string]$ExecutionId, # Replaces JobExecutionId
        [string]$WorkflowName,
        [string]$StepName,
        [string]$TriggerType,
        [int]$MaxRetries = 0,
        [int]$RetryDelaySeconds = 5
    )
    
    # Use shared ID if provided, else create new (should always be provided by Job/Workflow now)
    $execId = if ($ExecutionId) { $ExecutionId } else { [Guid]::NewGuid().ToString() }
    $startTime = Get-Date
    
    # Get task definition from manifest
    $taskDef = Get-AutoPSTask -Name $TaskName
    
    $displayName = if ($StepName) { $StepName } else { $TaskName }
    Write-AutoPSLog -Message "Starting Task: $displayName (using $TaskName)" -Level 'Info'
    
    # Merge params into context
    $inputData = $InputContext.Clone()
    foreach ($key in $InputParams.Keys) {
        $inputData[$key] = $InputParams[$key]
    }
    
    # Create temp files for I/O
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "autops"
    if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir -Force | Out-Null }
    
    $inputFile = Join-Path $tempDir "$execId-$StepName-in.json"
    $outputFile = Join-Path $tempDir "$execId-$StepName-out.json"
    
    # Write input
    $inputData | ConvertTo-Json -Depth 10 | Set-Content $inputFile
    
    if ($Client) {
        $checkParams = @{ ExecutionId = $execId; TaskId = if ($StepName) { $StepName } else { $TaskName } }
        $exists = $Client.ExecuteQuery("SELECT 1 FROM TaskExecutions WHERE ExecutionId = @ExecutionId AND TaskId = @TaskId", $checkParams)
        
        if ($exists.Rows.Count -gt 0) {
            # Update existing Waiting record
            $Client.ExecuteNonQuery(
                "UPDATE TaskExecutions SET Status = 'Running', State = 'Running', StartedAt = @StartedAt, InputData = @InputData, Attempt = 1, MaxRetries = @MaxRetries WHERE ExecutionId = @ExecutionId AND TaskId = @TaskId",
                @{
                    ExecutionId = $execId
                    TaskId      = if ($StepName) { $StepName } else { $TaskName }
                    StartedAt   = $startTime.ToString('o')
                    InputData   = ($inputData | ConvertTo-Json -Depth 4 -Compress)
                    MaxRetries  = $MaxRetries
                }
            )
        }
        else {
            # Insert new record (Standalone execution)
            $Client.ExecuteNonQuery(
                "INSERT INTO TaskExecutions (ExecutionId, TaskId, JobName, WorkflowName, TriggerType, InputData, Status, State, StartedAt, Attempt, MaxRetries) VALUES (@ExecutionId, @TaskId, @JobName, @WorkflowName, @TriggerType, @InputData, 'Running', 'Running', @StartedAt, 1, @MaxRetries)",
                @{
                    ExecutionId  = $execId
                    TaskId       = if ($StepName) { $StepName } else { $TaskName }
                    JobName      = $JobName
                    WorkflowName = $WorkflowName
                    TriggerType  = $TriggerType
                    InputData    = ($inputData | ConvertTo-Json -Depth 4 -Compress)
                    StartedAt    = $startTime.ToString('o')
                    MaxRetries   = $MaxRetries
                }
            )
        }
    }
    
    
    try {
        $attempt = 0
        $success = $false
    
        do {
            $attempt++
            try {
                # Get runtime path
                $runtimePath = Get-RuntimePath -Runtime $taskDef.Runtime -Env $taskDef.RuntimeEnv
            
                # Execute in separate process
                $stdoutFile = Join-Path $tempDir "$execId-stdout.txt"
                $stderrFile = Join-Path $tempDir "$execId-stderr.txt"
            
                if ($taskDef.Runtime -in 'pwsh', 'powershell') {
                    # Use Wrapper for native parameter binding
                    $wrapperPath = Join-Path $PSScriptRoot "TaskWrapper.ps1"
                    & $runtimePath -File $wrapperPath -ScriptPath $taskDef.File -InputFile $inputFile -OutputFile $outputFile > $stdoutFile 2> $stderrFile
                }
                else {
                    # Standard file-based invocation for other runtimes
                    & $runtimePath -File $taskDef.File -InputFile $inputFile -OutputFile $outputFile > $stdoutFile 2> $stderrFile
                }
                $exitCode = $LASTEXITCODE
            
                $stdout = ""
                $stderr = ""
                if (Test-Path $stdoutFile) { $stdout = Get-Content $stdoutFile -Raw -ErrorAction SilentlyContinue }
                if (Test-Path $stderrFile) { $stderr = Get-Content $stderrFile -Raw -ErrorAction SilentlyContinue }
            
                # Cleanup stdout/stderr temp files
                Remove-Item $stdoutFile -Force -ErrorAction SilentlyContinue
                Remove-Item $stderrFile -Force -ErrorAction SilentlyContinue
            
                # Display stdout
                if ($stdout) {
                    $stdout.Split("`n") | ForEach-Object { 
                        $line = $_.Trim()
                        if ($line) { 
                            Write-Host $line 
                        
                            # Live State Update
                            if ($Client -and $line -match '^STATE:\s*(.+)$') {
                                $newState = $matches[1].Trim()
                                try {
                                    $Client.ExecuteNonQuery(
                                        "UPDATE TaskExecutions SET State = @State WHERE ExecutionId = @ExecutionId AND TaskId = @TaskId",
                                        @{ ExecutionId = $execId; TaskId = if ($StepName) { $StepName } else { $TaskName }; State = $newState }
                                    )
                                }
                                catch {} # Best effort
                            }
                        } 
                    }
                }
            
                if ($exitCode -eq 0) {
                    $success = $true
                }
                else {
                    Write-AutoPSLog -Message "Task attempted $attempt failed with ExitCode $exitCode" -Level 'Warn'
                    if ($attempt -le $MaxRetries) {
                        Write-Host "Task failed. Retrying in $RetryDelaySeconds seconds (Attempt $($attempt+1)/$($MaxRetries + 1))..." -ForegroundColor Yellow
                    
                        if ($Client) {
                            $Client.ExecuteNonQuery(
                                "UPDATE TaskExecutions SET State = @State, Attempt = @Attempt WHERE ExecutionId = @ExecutionId AND TaskId = @TaskId",
                                @{ 
                                    ExecutionId = $execId
                                    TaskId      = if ($StepName) { $StepName } else { $TaskName }
                                    State       = "Retrying ($($attempt+1)/$($MaxRetries + 1))"
                                    Attempt     = $attempt + 1
                                }
                            )
                        }
                    
                        Start-Sleep -Seconds $RetryDelaySeconds
                    }
                }
            }
            catch {
                Write-AutoPSLog -Message "Task execution critical error: $_" -Level 'Error'
            }
        } while (-not $success -and $attempt -le $MaxRetries)
    
        $endTime = Get-Date
        $runtimeMs = ($endTime - $startTime).TotalMilliseconds

        # Read output
        $outputData = @{}
        if (Test-Path $outputFile) {
            $outputContent = Get-Content $outputFile -Raw
            if ($outputContent) {
                $outputData = $outputContent | ConvertFrom-Json -AsHashtable
            }
        }
        
        if ($exitCode -ne 0) {
            throw "Task exited with code $exitCode. Error: $stderr"
        }
        
        Write-AutoPSLog -Message "Task $displayName completed in ${runtimeMs}ms" -Level 'Info'
        
        # Update DB
        if ($Client) {
            # Update status (Success)
            $Client.ExecuteNonQuery(
                "UPDATE TaskExecutions SET Status = 'Completed', State = @State, ExitCode = @ExitCode, EndedAt = @EndedAt, RuntimeMs = @RuntimeMs, ExecutionLog = @Log, OutputData = @Output WHERE ExecutionId = @ExecutionId AND TaskId = @TaskId",
                @{
                    ExecutionId = $execId
                    TaskId      = if ($StepName) { $StepName } else { $TaskName }
                    State       = if ($outputData.state) { $outputData.state } else { 'Completed' }
                    ExitCode    = $exitCode
                    EndedAt     = $endTime.ToString('o')
                    RuntimeMs   = [math]::Round($runtimeMs)
                    Log         = $stdout
                    Output      = ($outputData | ConvertTo-Json -Depth 4 -Compress)
                }
            )
        }    # Cleanup temp files
        Remove-Item $inputFile -Force -ErrorAction SilentlyContinue
        Remove-Item $outputFile -Force -ErrorAction SilentlyContinue
        
        return $outputData
    }
    catch {
        $errorMsg = $_.Exception.Message
        Write-AutoPSLog -Message "Task $displayName failed: $errorMsg" -Level 'Error'
        
        if ($Client) {
            $Client.ExecuteNonQuery(
                "UPDATE TaskExecutions SET Status = 'Failed', ErrorLog = @ErrorLog, EndedAt = @EndedAt WHERE ExecutionId = @ExecutionId",
                @{
                    ExecutionId = $executionId
                    ErrorLog    = $errorMsg
                    EndedAt     = (Get-Date).ToString('o')
                }
            )
        }
        
        throw
    }
}

# ============================================================================
# WORKFLOW EXECUTION
# ============================================================================

function Invoke-AutoPSWorkflow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkflowName,
        
        [hashtable]$InputParams = @{},
        $Client,
        [string]$JobName,
        [string]$ExecutionId, # Replaces JobExecutionId
        [string]$TriggerType
    )
    
    Write-AutoPSLog -Message "Starting Workflow: $WorkflowName" -Level 'Info'
    
    # Single ID - use provided or create new (though workflows usually called by Job with ID)
    $workflowId = if ($ExecutionId) { $ExecutionId } else { [Guid]::NewGuid().ToString() }
    $startTime = Get-Date
    
    # Load workflow definition
    $wfDef = Get-AutoPSWorkflowDef -Name $WorkflowName
    
    # Log workflow start
    if ($Client) {
        $Client.ExecuteNonQuery(
            "INSERT INTO Workflows (WorkflowId, JobName, Name, Status, StartedAt, TriggerType) VALUES (@WorkflowId, @JobName, @Name, 'Running', @StartedAt, @TriggerType)",
            @{
                WorkflowId  = $workflowId
                JobName     = $JobName
                Name        = $WorkflowName
                StartedAt   = $startTime.ToString('o')
                TriggerType = $TriggerType
            }
        )
    }
    
    try {
        $context = $InputParams.Clone()
        $completed = @()
        
        # Collect all steps (tasks and child workflows)
        $steps = [System.Collections.ArrayList]::new()
        if ($wfDef.tasks) {
            foreach ($t in $wfDef.tasks) {
                $steps.Add(@{ type = 'task'; def = $t }) | Out-Null
            }
        }
        if ($wfDef.workflows) {
            foreach ($w in $wfDef.workflows) {
                $steps.Add(@{ type = 'workflow'; def = $w }) | Out-Null
            }
        }
        
        $failed = $false
        $maxIterations = 100
        if ($Client -and $steps.Count -gt 0) {
            if ($TriggerType -match '^Invoked by') {
                $childTrigger = $TriggerType
            }
            else {
                $childTrigger = "Invoked by $WorkflowName"
            }
            
            foreach ($step in $steps) {
                if ($step.type -eq 'task') {
                    $chk = $Client.ExecuteQuery("SELECT 1 FROM TaskExecutions WHERE ExecutionId = @Eid AND TaskId = @Tid", @{ Eid = $workflowId; Tid = $step.def.name })
                    if ($chk.Rows.Count -eq 0) {
                        $Client.ExecuteNonQuery(
                            "INSERT INTO TaskExecutions (ExecutionId, TaskId, JobName, JobExecutionId, WorkflowName, TriggerType, Status, State) VALUES (@ExecutionId, @TaskId, @JobName, @JobExecutionId, @WorkflowName, @TriggerType, 'Waiting', 'Waiting')",
                            @{
                                ExecutionId    = $workflowId
                                TaskId         = $step.def.name # ID IS THE NAME
                                JobName        = $JobName
                                JobExecutionId = $workflowId
                                WorkflowName   = $WorkflowName
                                TriggerType    = $childTrigger
                            }
                        )
                    }
                }
            }
        }
        
        $failed = $false
        $maxIterations = 100
        $iteration = 0
        
        while ($steps.Count -gt 0 -and -not $failed) {
            $iteration++
            if ($iteration -gt $maxIterations) {
                throw "Possible circular dependency in workflow $WorkflowName"
            }
            
            # Find runnable steps and update blocked tasks' State
            $runnable = @()
            foreach ($step in $steps) {
                $canRun = $true
                $blockedBy = @()
                if ($step.def.dependsOn) {
                    foreach ($dep in $step.def.dependsOn) {
                        if ($dep -notin $completed) {
                            $canRun = $false
                            $blockedBy += $dep
                        }
                    }
                }
                if ($canRun) {
                    $runnable += $step
                }
                elseif ($Client -and $step.type -eq 'task') {
                    # Update State to show what it's waiting for
                    $waitingFor = "Waiting for: $($blockedBy -join ', ')"
                    Write-AutoPSLog -Message "Task $($step.def.name) is $waitingFor" -Level 'Debug'
                    $Client.ExecuteNonQuery(
                        "UPDATE TaskExecutions SET State = @State WHERE ExecutionId = @ExecutionId AND TaskId = @TaskId AND Status = 'Waiting'",
                        @{
                            ExecutionId = $workflowId
                            TaskId      = $step.def.name
                            State       = $waitingFor
                        }
                    )
                }
            }
            
            if ($runnable.Count -eq 0 -and $steps.Count -gt 0) {
                throw "Stuck waiting for dependencies. Remaining: $(($steps | ForEach-Object { $_.def.name }) -join ', ')"
            }
            
            # Execute runnable steps
            foreach ($step in $runnable) {
                try {
                    $params = @{}
                    if ($step.def.params) {
                        foreach ($prop in $step.def.params.PSObject.Properties) {
                            $params[$prop.Name] = $prop.Value
                        }
                    }
                    if ($TriggerType -match '^Invoked by') {
                        $childTrigger = $TriggerType
                    }
                    else {
                        $childTrigger = "Invoked by $WorkflowName"
                    }
                    
                    if ($step.type -eq 'task') {
                        # Pass ExecutionId (Single shared ID)
                        $maxRetries = if ($step.def.retries) { $step.def.retries } else { 0 }
                        $retryDelay = if ($step.def.retry_delay) { $step.def.retry_delay } else { 5 }
                        
                        $result = Invoke-AutoPSTask -TaskName $step.def.task -InputParams $params -InputContext $context -Client $Client -JobName $JobName -ExecutionId $workflowId -WorkflowName $WorkflowName -StepName $step.def.name -TriggerType $childTrigger -MaxRetries $maxRetries -RetryDelaySeconds $retryDelay
                        
                        if ($result) {
                            $context[$step.def.name] = $result
                        }
                    }
                    elseif ($step.type -eq 'workflow') {
                        # Execute child workflow - Pass same ID
                        $childContext = Invoke-AutoPSWorkflow -WorkflowName $step.def.workflow -InputParams $context -Client $Client -JobName $JobName -ExecutionId $workflowId -TriggerType $childTrigger
                        
                        # Merge child workflow context
                        foreach ($key in $childContext.Keys) {
                            $context[$key] = $childContext[$key]
                        }
                    }
                    
                    $completed += $step.def.name
                    $steps.Remove($step) | Out-Null
                }
                catch {
                    $failed = $true
                    break
                }
            }
        }
        
        # Update workflow status
        if ($Client) {
            $status = if ($failed) { 'Failed' } else { 'Completed' }
            $endTime = Get-Date
            $duration = [math]::Round(($endTime - $startTime).TotalMilliseconds)
            $Client.ExecuteNonQuery(
                "UPDATE Workflows SET Status = @Status, EndedAt = @EndedAt, RuntimeMs = @RuntimeMs WHERE WorkflowId = @WorkflowId",
                @{
                    WorkflowId = $workflowId
                    Status     = $status
                    EndedAt    = $endTime.ToString('o')
                    RuntimeMs  = $duration
                }
            )
        }
        
        Write-AutoPSLog -Message "Workflow $WorkflowName completed" -Level 'Info'
        return $context
    }
    catch {
        Write-AutoPSLog -Message "Workflow $WorkflowName failed: $_" -Level 'Error'
        
        if ($Client) {
            $endTime = Get-Date
            $duration = [math]::Round(($endTime - $startTime).TotalMilliseconds)
            $Client.ExecuteNonQuery(
                "UPDATE Workflows SET Status = 'Failed', EndedAt = @EndedAt, RuntimeMs = @RuntimeMs WHERE WorkflowId = @WorkflowId",
                @{ WorkflowId = $workflowId; EndedAt = $endTime.ToString('o'); RuntimeMs = $duration }
            )
        }
        
        throw
    }
}

# ============================================================================
# JOB EXECUTION
# ============================================================================

function Invoke-AutoPSJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$JobName,
        
        $Client,
        
        [hashtable]$InputParams = @{},
        
        [string]$TriggerType = 'Manual',
        
        [string]$ExecutionId, # New param for shared ID
        
        [switch]$IsChildJob
    )
    
    $jobId = if ($ExecutionId) { $ExecutionId } else { [Guid]::NewGuid().ToString() }
    $startTime = Get-Date
    
    # Load job definition
    $jobDef = Get-AutoPSJobDef -Name $JobName
    
    $prefix = if ($IsChildJob) { "Child Job" } else { "Job" }
    Write-AutoPSLog -Message "Starting ${prefix}: $JobName (ExecutionId: $jobId)" -Level 'Info'
    
    # Log job start - TriggerType from param overrides definition
    if ($Client) {
        $Client.ExecuteNonQuery(
            "INSERT INTO Jobs (JobId, Name, TriggerType, Cron, Status, CreatedAt, StartedAt, CreatedBy, InputParams) VALUES (@JobId, @Name, @TriggerType, @Cron, 'Running', @CreatedAt, @StartedAt, @CreatedBy, @InputParams)",
            @{
                JobId       = $jobId
                Name        = $JobName
                TriggerType = $TriggerType
                Cron        = $jobDef.cron
                CreatedAt   = $startTime.ToString('o')
                StartedAt   = $startTime.ToString('o')
                CreatedBy   = $env:COMPUTERNAME
                InputParams = (ConvertTo-Json -InputObject $InputParams -Compress -Depth 2)
            }
        )
    }
    
    

    
    if ($TriggerType -match '^Invoked by') {
        $childTrigger = $TriggerType
    }
    else {
        $childTrigger = "Invoked by $JobName"
    }
    
    try {
        # Initialize context with CLI input params
        $context = @{}
        foreach ($key in $InputParams.Keys) {
            $context[$key] = $InputParams[$key]
        }
        $completed = @()
        
        # Pre-register tasks as Waiting
        if ($Client -and $jobDef.tasks) {
            foreach ($taskStep in $jobDef.tasks) {
                # Insert if not exists (rudimentary check or ignore assumption)
                # Since this is start of job, we assume fresh constraints mostly.
                # Use INSERT OR IGNORE logic if possible, or just INSERT and catch error?
                # Best: Check first.
                $chk = $Client.ExecuteQuery("SELECT 1 FROM TaskExecutions WHERE ExecutionId = @Eid AND TaskId = @Tid", @{ Eid = $jobId; Tid = $taskStep.name })
                if ($chk.Rows.Count -eq 0) {
                    $Client.ExecuteNonQuery(
                        "INSERT INTO TaskExecutions (ExecutionId, TaskId, JobName, WorkflowName, TriggerType, Status, State) VALUES (@ExecutionId, @TaskId, @JobName, @WorkflowName, @TriggerType, 'Waiting', 'Waiting')",
                        @{
                            ExecutionId  = $jobId
                            TaskId       = $taskStep.name
                            JobName      = $JobName
                            WorkflowName = $null
                            TriggerType  = $childTrigger
                        }
                    )
                }
            }
        }
        
        # Execute pre-tasks
        if ($jobDef.tasks) {
            foreach ($taskStep in $jobDef.tasks) {
                Write-Host "DEBUG: Processing task step $($taskStep.name)"
                $params = @{}
                if ($taskStep.params) {
                    foreach ($prop in $taskStep.params.PSObject.Properties) {
                        $params[$prop.Name] = $prop.Value
                    }
                }
                
                # ID = StepName logic: for TaskId, we use the StepName ($taskStep.name).
                # But Invoke-AutoPSTask expects TaskName to be the definition name (e.g. fetch-data).
                # We need to change Invoke-AutoPSTask to accept TaskId separately? 
                # Or just pass ExecutionId.
                # Per plan: Invoke-AutoPSTask -ExecutionId $jobId -TaskName $taskStep.task -StepName $taskStep.name
                
                # ID = StepName logic: for TaskId, we use the StepName ($taskStep.name).
                
                $maxRetries = if ($taskStep.retries) { $taskStep.retries } else { 0 }
                $retryDelay = if ($taskStep.retry_delay) { $taskStep.retry_delay } else { 5 }
                
                $result = Invoke-AutoPSTask -TaskName $taskStep.task -InputParams $params -InputContext $context -Client $Client -JobName $JobName -ExecutionId $jobId -StepName $taskStep.name -TriggerType $childTrigger -MaxRetries $maxRetries -RetryDelaySeconds $retryDelay
                if ($result) { $context[$taskStep.name] = $result }
                $completed += $taskStep.name
            }
        }
        
        # Execute workflows
        if ($jobDef.workflows) {
            foreach ($wfStep in $jobDef.workflows) {
                # Check dependencies
                if ($wfStep.dependsOn) {
                    foreach ($dep in $wfStep.dependsOn) {
                        if ($dep -notin $completed) {
                            throw "Workflow '$($wfStep.name)' dependency '$dep' not satisfied"
                        }
                    }
                }
                
                $wfContext = Invoke-AutoPSWorkflow -WorkflowName $wfStep.workflow -InputParams $context -Client $Client -JobName $JobName -ExecutionId $jobId -TriggerType $childTrigger
                
                # Merge workflow context
                foreach ($key in $wfContext.Keys) {
                    $context[$key] = $wfContext[$key]
                }
                $completed += $wfStep.name
            }
        }
        
        # Execute child jobs (triggerType ignored when called as child)
        if ($jobDef.jobs) {
            foreach ($jobStep in $jobDef.jobs) {
                # Check dependencies
                if ($jobStep.dependsOn) {
                    foreach ($dep in $jobStep.dependsOn) {
                        if ($dep -notin $completed) {
                            throw "Job '$($jobStep.name)' dependency '$dep' not satisfied"
                        }
                    }
                }
                
                Write-AutoPSLog -Message "Running child job: $($jobStep.job)" -Level 'Info'
                Invoke-AutoPSJob -JobName $jobStep.job -Client $Client -InputParams $context -IsChildJob -ExecutionId $jobId -TriggerType $childTrigger
                $completed += $jobStep.name
            }
        }
        
        # Update job status
        if ($Client) {
            $endTime = Get-Date
            $duration = [math]::Round(($endTime - $startTime).TotalMilliseconds)
            $Client.ExecuteNonQuery(
                "UPDATE Jobs SET Status = 'Completed', EndedAt = @EndedAt, RuntimeMs = @RuntimeMs WHERE JobId = @JobId AND Name = @Name",
                @{ JobId = $jobId; Name = $JobName; EndedAt = $endTime.ToString('o'); RuntimeMs = $duration }
            )
        }
        
        Write-AutoPSLog -Message "Job $JobName completed successfully" -Level 'Info'
    }
    catch {
        Write-AutoPSLog -Message "Job $JobName failed: $_" -Level 'Error'
        
        if ($Client) {
            $endTime = Get-Date
            $duration = [math]::Round(($endTime - $startTime).TotalMilliseconds)
            $Client.ExecuteNonQuery(
                "UPDATE Jobs SET Status = 'Failed', EndedAt = @EndedAt, RuntimeMs = @RuntimeMs WHERE JobId = @JobId AND Name = @Name",
                @{ JobId = $jobId; Name = $JobName; EndedAt = $endTime.ToString('o'); RuntimeMs = $duration }
            )
        }
        
        throw
    }
}

# ============================================================================
# SERVICE HOST
# ============================================================================

function Register-AutoPSNode {
    param(
        $Client,
        [string]$NodeName = $env:COMPUTERNAME
    )
    
    $nodeId = [Guid]::NewGuid().ToString()
    $os = if ($IsWindows) { 'Windows' } elseif ($IsMacOS) { 'macOS' } else { 'Linux' }
    
    $manifest = Get-AutoPSManifest
    $capabilities = ($manifest.tasks.PSObject.Properties.Name | ForEach-Object { $manifest.tasks.$_.runtime } | Sort-Object -Unique) -join ','
    
    $Client.ExecuteNonQuery(
        "INSERT INTO Nodes (NodeId, Name, OS, Capabilities, LastHeartbeat, Status) VALUES (@NodeId, @Name, @OS, @Capabilities, @LastHeartbeat, 'Online')",
        @{
            NodeId        = $nodeId
            Name          = $NodeName
            OS            = $os
            Capabilities  = $capabilities
            LastHeartbeat = (Get-Date).ToString('o')
        }
    )
    
    return $nodeId
}

function Start-AutoPSService {
    [CmdletBinding()]
    param(
        $Client,
        [int]$PollIntervalSeconds = 5,
        [string]$NodeName = $env:COMPUTERNAME
    )
    
    Write-AutoPSLog -Message "Starting AutoPS Service on node: $NodeName" -Level 'Info'
    
    $nodeId = Register-AutoPSNode -Client $Client -NodeName $NodeName
    Write-AutoPSLog -Message "Node registered with ID: $nodeId" -Level 'Info'
    
    while ($true) {
        try {
            # Update heartbeat
            $Client.ExecuteNonQuery(
                "UPDATE Nodes SET LastHeartbeat = @LastHeartbeat WHERE NodeId = @NodeId",
                @{ NodeId = $nodeId; LastHeartbeat = (Get-Date).ToString('o') }
            )
            
            # Poll for pending jobs
            $dt = $Client.ExecuteQuery(
                "SELECT JobId, Name FROM Jobs WHERE Status = 'Pending' LIMIT 1",
                @{}
            )
            
            if ($dt.Rows.Count -gt 0) {
                $row = $dt.Rows[0]
                $jobName = $row['Name']
                Write-AutoPSLog -Message "Picked up job: $jobName" -Level 'Info'
                
                Invoke-AutoPSJob -JobName $jobName -Client $Client
            }
        }
        catch {
            Write-AutoPSLog -Message "Service error: $_" -Level 'Error'
        }
        
        Start-Sleep -Seconds $PollIntervalSeconds
    }
}

# ============================================================================
# QUERY FUNCTIONS
# ============================================================================

function Get-AutoPSExecutions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Client,
        
        [ValidateSet('job', 'workflow', 'task', 'all')]
        [string]$Type = 'all',
        
        [ValidateSet('Running', 'Completed', 'Failed', 'Waiting', 'All')]
        [string]$Status = 'All',
        
        [string]$Name,
        
        [datetime]$StartedAfter,
        [datetime]$StartedBefore,
        [int]$Top = 20,
        [string]$Sort = 'StartedAt',
        [string]$SortOrder = 'Desc'
    )
    
    $results = @()
    
    # Sort order clause logic handled in-memory
    
    # Query Jobs
    if ($Type -eq 'all' -or $Type -eq 'job') {
        $query = "SELECT JobId as ExecutionId, Name, 'job' as Type, Status, StartedAt, EndedAt, InputParams FROM Jobs"
        $conditions = @()
        $params = @{}
        
        if ($Status -ne 'All') {
            $conditions += "Status = @Status"
            $params.Status = $Status
        }
        if ($Name) {
            $conditions += "Name = @Name"
            $params.Name = $Name
        }
        if ($StartedAfter) {
            $conditions += "StartedAt >= @StartedAfter"
            $params.StartedAfter = $StartedAfter.ToString('o')
        }
        if ($StartedBefore) {
            $conditions += "StartedAt <= @StartedBefore"
            $params.StartedBefore = $StartedBefore.ToString('o')
        }
        
        if ($conditions.Count -gt 0) {
            $query += " WHERE " + ($conditions -join " AND ")
        }
        
        # Apply sorting at query level for DBs that support it, but we can also sort efficiently in memory for mixed types
        # For now, let's fetch matching records and sort later.
        
        $dt = $Client.ExecuteQuery($query, $params)
        foreach ($row in $dt.Rows) {
            # JSON DB doesn't support SQL aliases, so read actual column names
            $execId = if ($dt.Columns.Contains('JobId')) { $row['JobId'] } elseif ($dt.Columns.Contains('ExecutionId')) { $row['ExecutionId'] } else { $null }
            $results += [PSCustomObject]@{
                ExecutionId = $execId
                Type        = 'job'
                Name        = $row['Name']
                TriggerType = if ($dt.Columns.Contains('TriggerType')) { $row['TriggerType'] } else { $null }
                Cron        = if ($dt.Columns.Contains('Cron')) { $row['Cron'] } else { $null }
                Status      = $row['Status']
                StartedAt   = $row['StartedAt']
                EndedAt     = if ($dt.Columns.Contains('EndedAt')) { $row['EndedAt'] } else { $null }
                RuntimeMs   = if ($dt.Columns.Contains('RuntimeMs')) { $row['RuntimeMs'] } else { $null }
            }
        }
    }
    
    # Query TaskExecutions
    if ($Type -eq 'all' -or $Type -eq 'task') {
        $query = "SELECT ExecutionId, TaskId, Status, State, StartedAt, EndedAt, RuntimeMs FROM TaskExecutions"
        $conditions = @()
        $params = @{}
        
        if ($Status -ne 'All') {
            $conditions += "Status = @Status"
            $params.Status = $Status
        }
        if ($Name) {
            $conditions += "TaskId = @Name"
            $params.Name = $Name
        }
        if ($StartedAfter) {
            $conditions += "StartedAt >= @StartedAfter"
            $params.StartedAfter = $StartedAfter.ToString('o')
        }
        if ($StartedBefore) {
            $conditions += "StartedAt <= @StartedBefore"
            $params.StartedBefore = $StartedBefore.ToString('o')
        }
        
        if ($conditions.Count -gt 0) {
            $query += " WHERE " + ($conditions -join " AND ")
        }
        
        $dt = $Client.ExecuteQuery($query, $params)
        foreach ($row in $dt.Rows) {
            $results += [PSCustomObject]@{
                ExecutionId = $row['ExecutionId']
                Type        = 'task'
                Name        = $row['TaskId']
                Status      = $row['Status']
                State       = if ($dt.Columns.Contains('State')) { $row['State'] } else { $null }
                StartedAt   = $row['StartedAt']
                EndedAt     = if ($dt.Columns.Contains('EndedAt')) { $row['EndedAt'] } else { $null }
                RuntimeMs   = if ($dt.Columns.Contains('RuntimeMs')) { $row['RuntimeMs'] } else { $null }
            }
        }
    }
    
    # Sort and Limit results in memory (since we merge different types)
    if ($Sort) {
        $descending = ($SortOrder -eq 'Desc')
        $results = $results | Sort-Object -Property $Sort -Descending:$descending
    }
    
    if ($Top -gt 0) {
        $results = $results | Select-Object -First $Top
    }
    
    return $results
}

function Get-AutoPSExecution {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Client,
        
        [Parameter(Mandatory = $true)]
        [string]$ExecutionId
    )
    
    # Try Jobs first
    $results = @()
    $dt = $Client.ExecuteQuery(
        "SELECT JobId, Name, Status, StartedAt, EndedAt, RuntimeMs, TriggerType FROM Jobs WHERE JobId = @Id",
        @{ Id = $ExecutionId }
    )
    
    if ($dt.Rows.Count -gt 0) {
        foreach ($row in $dt.Rows) {
            $results += [PSCustomObject]@{
                ExecutionId = $row['JobId']
                Type        = 'job'
                Name        = if ($dt.Columns.Contains('Name')) { $row['Name'] } else { "Unknown" }
                Status      = $row['Status']
                StartedAt   = $row['StartedAt']
                EndedAt     = if ($dt.Columns.Contains('EndedAt')) { $row['EndedAt'] } else { $null }
                RuntimeMs   = if ($dt.Columns.Contains('RuntimeMs')) { $row['RuntimeMs'] } else { $null }
                TriggerType = $row['TriggerType']
            }
        }
        
        # If it's a Job, fetch related Workflow and Task executions
        
        # 1. Fetch Workflows
        $wfDt = $Client.ExecuteQuery(
            "SELECT WorkflowId as ExecutionId, Name, Status, StartedAt, EndedAt, RuntimeMs, TriggerType FROM Workflows WHERE WorkflowId = @Id",
            @{ Id = $ExecutionId }
        )
        foreach ($wfRow in $wfDt.Rows) {
            $results += [PSCustomObject]@{
                ExecutionId = if ($wfDt.Columns.Contains('ExecutionId')) { $wfRow['ExecutionId'] } else { $wfRow['WorkflowId'] }
                Type        = 'workflow'
                Name        = $wfRow['Name']
                Status      = $wfRow['Status']
                StartedAt   = $wfRow['StartedAt']
                EndedAt     = if ($wfDt.Columns.Contains('EndedAt')) { $wfRow['EndedAt'] } else { $null }
                RuntimeMs   = if ($wfDt.Columns.Contains('RuntimeMs')) { $wfRow['RuntimeMs'] } else { $null }
                TriggerType = if ($wfDt.Columns.Contains('TriggerType')) { $wfRow['TriggerType'] } else { $null }
            }
        }
        
        # 2. Fetch Tasks
        $taskDt = $Client.ExecuteQuery(
            "SELECT ExecutionId, TaskId, Status, State, StartedAt, EndedAt, RuntimeMs, TriggerType FROM TaskExecutions WHERE ExecutionId = @Id",
            @{ Id = $ExecutionId }
        )
        foreach ($tRow in $taskDt.Rows) {
            $results += [PSCustomObject]@{
                ExecutionId = $tRow['ExecutionId']
                Type        = 'task'
                Name        = $tRow['TaskId']
                Status      = $tRow['Status']
                State       = if ($taskDt.Columns.Contains('State')) { $tRow['State'] } else { $null }
                StartedAt   = $tRow['StartedAt']
                EndedAt     = if ($taskDt.Columns.Contains('EndedAt')) { $tRow['EndedAt'] } else { $null }
                RuntimeMs   = if ($taskDt.Columns.Contains('RuntimeMs')) { $tRow['RuntimeMs'] } else { $null }
                TriggerType = if ($taskDt.Columns.Contains('TriggerType')) { $tRow['TriggerType'] } else { $null }
            }
        }
        
        return $results
    }
    
    # Try TaskExecutions
    $dt = $Client.ExecuteQuery(
        "SELECT ExecutionId, TaskId, Status, StartedAt, EndedAt, RuntimeMs, ExitCode, Log, Output FROM TaskExecutions WHERE ExecutionId = @Id",
        @{ Id = $ExecutionId }
    )
    
    if ($dt.Rows.Count -gt 0) {
        $row = $dt.Rows[0]
        return [PSCustomObject]@{
            ExecutionId = $row['ExecutionId']
            Type        = 'task'
            Name        = $row['TaskId']
            Status      = $row['Status']
            StartedAt   = $row['StartedAt']
            EndedAt     = if ($dt.Columns.Contains('EndedAt')) { $row['EndedAt'] } else { $null }
            RuntimeMs   = if ($dt.Columns.Contains('RuntimeMs')) { $row['RuntimeMs'] } else { $null }
            ExitCode    = if ($dt.Columns.Contains('ExitCode')) { $row['ExitCode'] } else { $null }
            Log         = if ($dt.Columns.Contains('Log')) { $row['Log'] } else { $null }
            Output      = if ($dt.Columns.Contains('Output')) { $row['Output'] } else { $null }
        }
    }
    
    return $null
}
