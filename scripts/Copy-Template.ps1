
$tempFolder = Join-Path $env:TEMP (New-Guid)
Write-Host "Set templateFolder = $tempFolder"
Write-Host "##vso[task.setvariable variable=templateFolder]$tempFolder"

Copy-Item -Path $PSScriptRoot -Destination $tempFolder -Recurse
