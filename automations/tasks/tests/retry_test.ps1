#Requires -Version 5.1
# Task: retry_test
# Fails first 2 times, succeeds on 3rd

param()

$tempFile = Join-Path ([System.IO.Path]::GetTempPath()) "autops_retry_counter.txt"

if (-not (Test-Path $tempFile)) {
    # Attempt 1
    Set-Content -Path $tempFile -Value "1"
    Write-Host "Simulating Failure (Attempt 1)..."
    exit 1
}

$count = [int](Get-Content -Path $tempFile)

if ($count -lt 3) {
    # Fail
    $count++
    Set-Content -Path $tempFile -Value "$count"
    Write-Host "Simulating Failure (Attempt $count)..."
    exit 1
}
else {
    # Success
    Write-Host "Success on Attempt $count (or more)!"
    Remove-Item $tempFile -Force
    return @{ status = "success"; message = "Finally succeeded!" }
}
