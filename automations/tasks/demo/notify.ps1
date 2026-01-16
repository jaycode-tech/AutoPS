#Requires -Version 5.1
# Task: notify
# Sends notification

param(
    [string]$message = "Pipeline completed"
)

# Execute task
Write-Host "NOTIFICATION: $message"

# Return output object
return @{
    notified   = $true
    message    = $message
    notifiedAt = (Get-Date).ToString('o')
}
