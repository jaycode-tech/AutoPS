#Requires -Version 5.1
<#
.SYNOPSIS
    AutoPS Task Wrapper - JSON I/O and Parameter Binding for PowerShell Tasks

.DESCRIPTION
    This wrapper script is invoked by the Engine to execute PowerShell tasks.
    It handles:
    1. Reading input parameters from a JSON file
    2. Converting JSON to PowerShell hashtable for splatting
    3. Invoking the actual task script with parameters
    4. Capturing the return value and writing to output JSON file
    
    This approach provides isolation between tasks and enables cross-language
    execution patterns (same I/O pattern can work with Python, Node, etc.)

.PARAMETER ScriptPath
    Full path to the PowerShell task script (.ps1) to execute

.PARAMETER InputFile
    Path to JSON file containing input parameters (created by Engine)

.PARAMETER OutputFile
    Path where task should write its output as JSON (read by Engine)

.EXAMPLE
    # Invoked by Engine.ps1, not directly by users:
    & TaskWrapper.ps1 -ScriptPath "./tasks/hello.ps1" -InputFile "/tmp/input.json" -OutputFile "/tmp/output.json"

.NOTES
    Exit codes:
    - 0: Success
    - 1: Wrapper error (file not found, JSON parse error)
    - Other: Exit code from the task script itself
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ScriptPath,    # Path to the task .ps1 file
    
    [Parameter(Mandatory = $true)]
    [string]$InputFile,     # JSON file with input parameters
    
    [Parameter(Mandatory = $true)]
    [string]$OutputFile     # JSON file for task output
)

try {
    # ========================================================================
    # STEP 1: Read Input Parameters from JSON
    # ========================================================================
    if (-not (Test-Path $InputFile)) {
        throw "Input file not found: $InputFile"
    }
    
    # Read and parse the input JSON
    $jsonContent = Get-Content $InputFile -Raw
    $inputParams = @{}
    
    if (-not [string]::IsNullOrWhiteSpace($jsonContent)) {
        $jsonObj = $jsonContent | ConvertFrom-Json
        
        # Convert PSCustomObject to Hashtable for PowerShell Splatting (PS 5.1 compatible)
        # Splatting allows passing @inputParams as individual -ParamName Value pairs
        if ($jsonObj) {
            foreach ($prop in $jsonObj.PSObject.Properties) {
                $inputParams[$prop.Name] = $prop.Value
            }
        }
    }
    
    # ========================================================================
    # STEP 2: Invoke the Task Script
    # ========================================================================
    if (-not (Test-Path $ScriptPath)) {
        throw "Task script not found: $ScriptPath"
    }
    
    # Execute the task script with splatted parameters
    # - Return value ($result) is captured from the pipeline
    # - Write-Host output goes to stdout (redirected by Engine to log)
    # - Write-Error output goes to stderr
    $result = & $ScriptPath @inputParams
    
    # If the script set a non-zero exit code, propagate it
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    
    # ========================================================================
    # STEP 3: Write Output to JSON File
    # ========================================================================
    if ($null -ne $result) {
        # Serialize the result object to JSON (max depth 5 for nested objects)
        $result | ConvertTo-Json -Depth 5 -Compress | Set-Content $OutputFile
    }
    else {
        # Write empty JSON object if task returned null
        "{}" | Set-Content $OutputFile
    }
}
catch {
    # Log the error and exit with error code
    Write-Error "Wrapper Error: $_"
    exit 1
}
