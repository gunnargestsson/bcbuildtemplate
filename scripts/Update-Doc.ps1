Param(
    [Parameter(Mandatory = $true)]
    [string] $configurationFilePath,

    [Parameter(Mandatory = $true)]
    [string] $artifactsFolder,

    [Parameter(Mandatory = $true)]
    [string] $branchName,

    [Parameter(Mandatory = $false)]
    [string] $buildProjectFolder = $ENV:BUILD_REPOSITORY_LOCALPATH
)

$settings = (Get-Content -Path $configurationFilePath -Encoding UTF8 | Out-String | ConvertFrom-Json)
$appFolders = $settings.appFolders
$alDoc = $settings.PSObject.Properties.Match('alDoc')
if ($alDoc.Value) {
    if ($alDoc.branch -match $branchName -or $branchName -match $aldoc.branch) {
        Sort-AppFoldersByDependencies -appFolders $appFolders.Split(',') -baseFolder $buildProjectFolder -WarningAction SilentlyContinue | ForEach-Object {
            Write-Host "Publishing $_"
            Get-ChildItem -Path (Join-Path $buildArtifactFolder $_) -Filter "*.app" | ForEach-Object {
                Write-Host "Writing Document References for $($_.Name) based on ${buildProjectFolder} to $($alDoc.alDocRoot)"
                Start-Process -FilePath $alDoc.alDocPath -ArgumentList "build -o $($alDoc.alDocRoot) -c ${buildProjectFolder} -s $($_.FullName)"
                Start-Process -FilePath $aldoc.docFxPath -ArgumentList "build '$(Join-Path $alDoc.alDocRoot docfx.json)' -n $($alDoc.alDocHostName) -p $($alDoc.alDocPort)"
            }
        }
    }
}