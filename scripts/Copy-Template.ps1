
$tempFolder = Join-Path (Join-Path $ENV:AGENT_TOOLSDIRECTORY 'bcbuildtemplate')
Write-Host "Set templateFolder = $tempFolder"
Write-Host "##vso[task.setvariable variable=templateFolder]$tempFolder"

Copy-Item -Path $PSScriptRoot -Destination $tempFolder -Recurse -Force
