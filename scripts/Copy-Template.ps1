Param(
    [Parameter(Mandatory = $true)]
    [string] $AgentToolsDirectory
)

$tempFolder = Join-Path $AgentToolsDirectory 'bcbuildtemplate'
Write-Host "Set templateFolder = $tempFolder"
Write-Host "##vso[task.setvariable variable=templateFolder]$tempFolder"

Copy-Item -Path (Join-Path $PSScriptRoot "*.ps1") -Destination $tempFolder -Recurse -Force