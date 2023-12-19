Param(
    [Parameter(Mandatory = $true)]
    [string] $configurationFilePath,

    [Parameter(Mandatory = $true)]
    [string] $artifactsFolder,

    [Parameter(Mandatory=$true)]
    [string] $appFolders,

    [Parameter(Mandatory = $true)]
    [string] $branchName,

    [Parameter(Mandatory = $false)]
    [string] $buildProjectFolder = $ENV:BUILD_REPOSITORY_LOCALPATH
)

$settings = (Get-Content -Path $configurationFilePath -Encoding UTF8 | Out-String | ConvertFrom-Json)
$alDoc = $settings.PSObject.Properties.Match('alDoc')
if ($alDoc.Value) {
    $alDoc = $settings.alDoc
    $buildProjectFolder = Join-Path $buildProjectFolder '.alPackages'
    if ($alDoc.branch -match $branchName -or $branchName -match $aldoc.branch) {
        $appFolders.Split(',') | ForEach-Object {
            Write-Host "Update alDoc for $(Join-Path $artifactsFolder $_) based on ${buildProjectFolder} to $($alDoc.alDocRoot)"
            Get-ChildItem -Path (Join-Path $artifactsFolder $_) -Filter "*.app" | ForEach-Object {
                Write-Host "Writing Document References for $($_.Name)"               
                Start-Process -FilePath $alDoc.alDocPath -ArgumentList "build","--output `"$($alDoc.alDocRoot)`"","--packagecache `"${buildProjectFolder}`"","--source `"$($_.FullName)`"" -Wait
                Start-Process -FilePath $aldoc.docFxPath -ArgumentList "build","`"$(Join-Path $alDoc.alDocRoot docfx.json)`"","--hostname $($alDoc.alDocHostName)","--port $($alDoc.alDocPort)" -Wait
            }
        }
    }
}