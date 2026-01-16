#Requires -Version 5.1
# Task: greet
# Displays a greeting message

param(
    [string]$name
)

# Set default if empty
if (-not $name) {
    $name = $env:USERNAME ?? $env:USER ?? "World"
}

# Execute task
Write-Host "Hello, $name!"

# Return output object
return @{
    greeting  = "Hello"
    target    = $name
    timestamp = (Get-Date).ToString('o')
}
