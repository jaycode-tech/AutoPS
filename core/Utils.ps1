#Requires -Version 5.1
<#
.SYNOPSIS
    AutoPS Beta 0.5 - Utils.ps1
    Utility functions for logging, TUI helpers, configuration, and health checks.

.DESCRIPTION
    This module provides core utility functions used throughout AutoPS:
    - Logging: Initialize-AutoPSLogger, Write-AutoPSLog
    - TUI Helpers: Prompts, progress bars, tables, status display
    - Configuration: Load config.json and runtime.json
    - Runtime Resolution: Get-RuntimePath for multi-language support
    - Health Checks: Integration testing framework
#>

# ============================================================================
# LOGGING
# File-based logging with console output support
# ============================================================================

# Script-level variable to store the current log file path
$script:LogPath = $null

function Initialize-AutoPSLogger {
    <#
    .SYNOPSIS
        Initializes the logging system with a date-stamped log file.
    .PARAMETER LogDir
        Directory where log files will be created (e.g., ./logs)
    #>
    param([string]$LogDir)
    
    # Create log filename with today's date (one file per day)
    $script:LogPath = Join-Path $LogDir "autops_$(Get-Date -Format 'yyyyMMdd').log"
    
    # Ensure log directory exists
    if (-not (Test-Path $LogDir)) { 
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null 
    }
}

function Write-AutoPSLog {
    <#
    .SYNOPSIS
        Writes a log entry to the log file and optionally to console.
    .PARAMETER Message
        The message to log
    .PARAMETER Level
        Severity level: Debug, Info, Warn, Error
    .PARAMETER NoConsole
        If set, suppress console output (only write to file)
    #>
    param(
        [string]$Message,
        [ValidateSet('Debug', 'Info', 'Warn', 'Error')]
        [string]$Level = 'Info',
        [switch]$NoConsole
    )
    
    # Format: [2026-01-16 12:30:45] [Info] Message text
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "[$timestamp] [$Level] $Message"
    
    # Write to log file if initialized
    if ($script:LogPath) {
        Add-Content -Path $script:LogPath -Value $entry
    }
    
    # Write to console with color coding (unless suppressed)
    if (-not $NoConsole) {
        switch ($Level) {
            'Debug' { Write-Verbose $entry }
            'Info' { Write-Host $entry -ForegroundColor Cyan }
            'Warn' { Write-Host $entry -ForegroundColor Yellow }
            'Error' { Write-Host $entry -ForegroundColor Red }
        }
    }
}

# ============================================================================
# TUI HELPERS
# Terminal User Interface helper functions for interactive prompts and display
# ============================================================================

function Read-AutoPSPrompt {
    <#
    .SYNOPSIS
        Displays an interactive prompt with a default value.
    .PARAMETER Message
        The prompt message to display
    .PARAMETER Default
        Default value if user presses Enter without input
    #>
    param(
        [string]$Message,
        [string]$Default = 'Y'
    )
    $prompt = "$Message [$Default]: "
    Write-Host $prompt -NoNewline -ForegroundColor Yellow
    $response = Read-Host
    
    # Use default if response is empty
    if ([string]::IsNullOrWhiteSpace($response)) { $response = $Default }
    return $response
}

function Show-AutoPSProgress {
    <#
    .SYNOPSIS
        Wrapper for Write-Progress to show task progress.
    #>
    param(
        [string]$Activity,      # Main activity description
        [string]$Status,        # Current status text
        [int]$PercentComplete   # Progress percentage (0-100)
    )
    Write-Progress -Activity $Activity -Status $Status -PercentComplete $PercentComplete
}

function Show-AutoPSTable {
    <#
    .SYNOPSIS
        Displays data as a formatted table with optional title.
    #>
    param(
        [array]$Data,    # Array of objects to display
        [string]$Title   # Optional title header
    )
    if ($Title) { Write-Host "`n=== $Title ===" -ForegroundColor Cyan }
    $Data | Format-Table -AutoSize | Out-String | Write-Host
}

function Show-AutoPSStatus {
    <#
    .SYNOPSIS
        Displays a status line with [OK] or [FAIL] icon.
    .PARAMETER Component
        Name of the component being checked
    .PARAMETER Success
        Boolean indicating success/failure
    .PARAMETER Message
        Optional additional message
    #>
    param(
        [string]$Component,
        [bool]$Success,
        [string]$Message = ''
    )
    $icon = if ($Success) { "[OK]" } else { "[FAIL]" }
    $color = if ($Success) { "Green" } else { "Red" }
    $line = "$icon $Component"
    if ($Message) { $line += " - $Message" }
    Write-Host $line -ForegroundColor $color
}

# ============================================================================
# CONFIGURATION
# Load and parse JSON configuration files
# ============================================================================

function Get-AutoPSConfig {
    <#
    .SYNOPSIS
        Loads the main application configuration from config.json.
    .PARAMETER ConfigPath
        Path to config.json (defaults to ../config.json relative to this script)
    .OUTPUTS
        PSCustomObject containing database, service, integrations, logging config
    #>
    param([string]$ConfigPath)
    
    # Default to config.json in project root
    if (-not $ConfigPath) {
        $ConfigPath = Join-Path $PSScriptRoot "../config.json"
    }
    
    if (Test-Path $ConfigPath) {
        $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        return $config
    }
    
    # Return defaults if config file doesn't exist
    return [PSCustomObject]@{
        Database     = $null
        Service      = @{ PollIntervalSeconds = 5 }
        Integrations = @()
    }
}

function Get-AutoPSRuntimeConfig {
    <#
    .SYNOPSIS
        Loads runtime configuration from runtime.json.
    .DESCRIPTION
        Runtime.json maps language runtimes to executable paths,
        supporting multiple environments per runtime (e.g., python/ml-jobs).
    .PARAMETER RuntimePath
        Path to runtime.json (defaults to ../runtime.json)
    .OUTPUTS
        PSCustomObject with runtime paths: { python: { default: "python3", ml-jobs: "./runtimes/..." } }
    #>
    param([string]$RuntimePath)
    
    if (-not $RuntimePath) {
        $RuntimePath = Join-Path $PSScriptRoot "../runtime.json"
    }
    
    if (Test-Path $RuntimePath) {
        return Get-Content $RuntimePath -Raw | ConvertFrom-Json
    }
    
    # Return defaults if runtime config doesn't exist
    return [PSCustomObject]@{
        pwsh   = @{ default = "pwsh" }
        python = @{ default = "python" }
        node   = @{ default = "node" }
    }
}

function Get-RuntimePath {
    <#
    .SYNOPSIS
        Resolves the executable path for a given runtime and environment.
    .PARAMETER Runtime
        The runtime type (e.g., "python", "node", "pwsh")
    .PARAMETER Env
        The environment name (e.g., "default", "ml-jobs", "mkdocs_3.13")
    .OUTPUTS
        Executable path (e.g., "./runtimes/python/mkdocs_3.13/bin/python")
    .EXAMPLE
        Get-RuntimePath -Runtime "python" -Env "mkdocs_3.13"
        # Returns: ./runtimes/python/mkdocs_3.13/bin/python
    #>
    param(
        [string]$Runtime,
        [string]$Env = 'default'
    )
    
    $config = Get-AutoPSRuntimeConfig
    
    # Try specific environment first
    if ($config.$Runtime -and $config.$Runtime.$Env) {
        return $config.$Runtime.$Env
    }
    # Fall back to default for this runtime
    elseif ($config.$Runtime -and $config.$Runtime.default) {
        return $config.$Runtime.default
    }
    
    # Fallback to system command (assume it's in PATH)
    return $Runtime
}

# ============================================================================
# HEALTH CHECKS
# Integration testing framework for verifying system components
# ============================================================================

function Test-AutoPSIntegration {
    <#
    .SYNOPSIS
        Tests a single integration by running its test script.
    .PARAMETER Name
        Integration name for reporting
    .PARAMETER Type
        'Core' (required) or 'NonCore' (optional)
    .PARAMETER TestScript
        ScriptBlock that returns true/false or throws on failure
    #>
    param(
        [string]$Name,
        [string]$Type,  # 'Core' or 'NonCore'
        [scriptblock]$TestScript
    )
    
    try {
        # Execute the test script
        $result = & $TestScript
        return [PSCustomObject]@{
            Name   = $Name
            Type   = $Type
            Status = 'Healthy'
            Error  = $null
        }
    }
    catch {
        return [PSCustomObject]@{
            Name   = $Name
            Type   = $Type
            Status = 'Unhealthy'
            Error  = $_.Exception.Message
        }
    }
}

function Test-AutoPSIntegrations {
    <#
    .SYNOPSIS
        Tests all configured integrations and reports results.
    .PARAMETER Integrations
        Array of integration objects with Name, Type, TestScript properties
    .PARAMETER Silent
        If set, suppress console output
    .OUTPUTS
        Object with Results array and CoreFailure boolean
    #>
    param(
        [array]$Integrations,
        [switch]$Silent
    )
    
    $results = @()
    $coreFailure = $false
    
    foreach ($integration in $Integrations) {
        # Convert TestScript string to scriptblock
        $testScript = [scriptblock]::Create($integration.TestScript)
        $result = Test-AutoPSIntegration -Name $integration.Name -Type $integration.Type -TestScript $testScript
        $results += $result
        
        # Show status unless silent mode
        if (-not $Silent) {
            Show-AutoPSStatus -Component $integration.Name -Success ($result.Status -eq 'Healthy') -Message $result.Error
        }
        
        # Track if any core integration failed
        if ($result.Type -eq 'Core' -and $result.Status -eq 'Unhealthy') {
            $coreFailure = $true
        }
    }
    
    return [PSCustomObject]@{
        Results     = $results
        CoreFailure = $coreFailure
    }
}
