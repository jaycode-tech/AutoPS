#Requires -Version 5.1
# Task: transform-data
# Transforms fetched data

param(
    [PSCustomObject]$Extract
)

$records = if ($Extract -and $Extract.records) { $Extract.records } else { 0 }

# Execute task
Write-Host "Transforming $records records..."
Start-Sleep -Seconds 1  # Simulate processing

# Return output object
return @{
    transformed   = $records
    format        = "JSON"
    transformedAt = (Get-Date).ToString('o')
}
