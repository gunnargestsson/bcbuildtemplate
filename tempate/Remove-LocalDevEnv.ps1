$configurationFilePath = Join-Path $PSScriptRoot 'build-settings.json'
if (Test-Path $configurationFilePath) {
    $RemoveDevContainerPath = Join-Path $env:TEMP 'Remove-LocalDevEnv.ps1'
    Set-Content -Path $RemoveDevContainerPath -Value (Invoke-WebRequest -Uri "https://raw.githubusercontent.com/gunnargestsson/bcbuildtemplate/master/scripts/Remove-LocalDevEnv.ps1").Content -Encoding UTF8 -Force
    . $RemoveDevContainerPath -configurationFilePath $configurationFilePath -scriptToStart $RemoveDevContainerPath
}
else {
    Throw "Configuration file 'build-settings.json' not found in current path"
}
