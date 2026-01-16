# HTTP/REST API Integration Template
# NonCore integration - checks external API connectivity

New-AutoPSIntegration -Name "ExternalAPI" -Type "NonCore" -TestScript {
    # Example: Test connectivity to an API endpoint
    # Replace with actual endpoint
    $response = Invoke-WebRequest -Uri "https://httpbin.org/get" -Method Head -TimeoutSec 5 -UseBasicParsing
    $response.StatusCode -eq 200
} -Config @{
    Description = "Validates external API connectivity"
    BaseUrl     = "https://httpbin.org"
    Timeout     = 5
}
