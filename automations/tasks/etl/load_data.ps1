#Requires -Version 5.1
# Task: load-data
# Loads transformed data to destination

param(
    [PSCustomObject]$Transform
)

$transformed = if ($Transform -and $Transform.transformed) { $Transform.transformed } else { 0 }

# Execute task
Write-Host "Loading $transformed records to database..."
Start-Sleep -Seconds 1  # Simulate loading

# Return output object
return @{
    loaded      = $transformed
    destination = "Database"
    loadedAt    = (Get-Date).ToString('o')
}
