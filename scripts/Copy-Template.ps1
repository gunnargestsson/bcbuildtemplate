Param(
    [Parameter(Mandatory = $true)]
    [string] $AgentToolsDirectory
)

$tempFolder = Join-Path $AgentToolsDirectory 'bcbuildtemplate'
if (Test-Path -Path $tempFolder -PathType Leaf) {
    Remove-Item -Path $tempFolder -Force
}
if (!(Test-Path -Path $tempFolder -PathType Container)) {
    New-Item -Path $tempFolder -ItemType Directory 
}
Write-Host "Set templateFolder = $tempFolder"
Write-Host "##vso[task.setvariable variable=templateFolder]$tempFolder"

Copy-Item -Path (Join-Path $PSScriptRoot "*.ps1") -Destination $tempFolder -Recurse -Force
