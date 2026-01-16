# Filesystem Integration
# Core integration - checks local filesystem access

New-AutoPSIntegration -Name "LocalFilesystem" -Type "Core" -TestScript {
    Test-Path "."
} -Config @{
    Description = "Validates local filesystem is accessible"
}
