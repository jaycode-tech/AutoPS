#Requires -Version 5.1
# Task: state_test
# Tests custom state updates

param()

Write-Host "Starting State Test..."
Write-Host "STATE: Initialization"
Start-Sleep -Seconds 2

Write-Host "STATE: Processing 50%"
Start-Sleep -Seconds 2

Write-Host "STATE: Finalizing"
Start-Sleep -Seconds 1

return @{
    status = "success"
    state  = "Finalized" # Overrides final state
}
