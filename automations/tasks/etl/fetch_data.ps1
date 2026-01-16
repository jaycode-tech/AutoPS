#Requires -Version 5.1
# Task: fetch-data
# Simulates fetching data from an API

param(
    [string]$url = "https://api.example.com/data"
)

# Execute task
Write-Host "Fetching data from: $url"
Start-Sleep -Seconds 1  # Simulate API call

# Return output object
return @{
    records   = 1000
    source    = $url
    fetchedAt = (Get-Date).ToString('o')
}
