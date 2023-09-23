$configurationFilePath = Join-Path $PSScriptRoot 'build-settings.json'
if (Test-Path $configurationFilePath) {
    $containerName = (Get-BCContainers) | Select-Object -First 1
    $settings = (Get-Content -Path $configurationFilePath -Encoding UTF8 | Out-String | ConvertFrom-Json)
    $settings.dependencies | ForEach-Object {
        Write-Host "Publishing $_"
        Publish-BcContainerApp -containerName $containerName -appFile $_ -skipVerification -sync -install 
    }
}
else {
    Throw "Configuration file 'build-settings.json' not found in current path"
}
