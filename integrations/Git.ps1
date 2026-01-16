# Git Integration
# NonCore integration - checks Git availability

New-AutoPSIntegration -Name "Git" -Type "NonCore" -TestScript {
    $null = git --version 2>$null
    $LASTEXITCODE -eq 0
} -Config @{
    Description = "Validates Git CLI is available"
}
