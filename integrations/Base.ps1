#Requires -Version 5.1
# AutoPS v2 - Integration Base Class
# All integrations should inherit from this pattern

function New-AutoPSIntegration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('Core', 'NonCore')]
        [string]$Type,
        
        [Parameter(Mandatory = $true)]
        [scriptblock]$TestScript,
        
        [hashtable]$Config = @{}
    )
    
    return [PSCustomObject]@{
        PSTypeName = 'AutoPS.Integration'
        Name       = $Name
        Type       = $Type
        TestScript = $TestScript
        Config     = $Config
        Status     = 'Unknown'
        LastCheck  = $null
    }
}

function Test-Integration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Integration
    )
    
    try {
        $result = & $Integration.TestScript
        $Integration.Status = 'Healthy'
        $Integration.LastCheck = Get-Date
        return $true
    }
    catch {
        $Integration.Status = 'Unhealthy'
        $Integration.LastCheck = Get-Date
        Write-Warning "Integration '$($Integration.Name)' failed: $_"
        return $false
    }
}

function Get-AutoPSIntegrations {
    param([string]$IntegrationsDir)
    
    if (-not $IntegrationsDir) {
        $IntegrationsDir = Join-Path $PSScriptRoot "."
    }
    
    $integrations = @()
    
    Get-ChildItem -Path $IntegrationsDir -Filter "*.ps1" -Exclude "Base.ps1" | ForEach-Object {
        try {
            $result = . $_.FullName
            if ($result) {
                $integrations += $result
            }
        }
        catch {
            Write-Warning "Failed to load integration from $($_.Name): $_"
        }
    }
    
    return $integrations
}
