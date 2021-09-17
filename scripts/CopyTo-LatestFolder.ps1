Param(
    [ValidateSet('AzureDevOps', 'Local', 'AzureVM')]
    [Parameter(Mandatory = $false)]
    [string] $buildEnv = "AzureDevOps",

    [Parameter(Mandatory = $false)]
    [string] $buildArtifactFolder = $ENV:BUILD_ARTIFACTSTAGINGDIRECTORY,

    [Parameter(Mandatory = $true)]
    [string] $releaseFolder,

    [Parameter(Mandatory = $true)]
    [string] $appFolders
)


$DestinationPath = Join-Path $buildArtifactFolder $releaseFolder;
New-Item -Path $DestinationPath -ItemType Directory;
$appFolders.Split(',') | ForEach-Object {
    $AppFolder = Join-Path $buildArtifactFolder $_
    Write-Host "Reading App information in ${AppFolder}"
    $App = (Get-Item -Path (Join-Path $AppFolder '*.app')).FullName
    $AppJson = (Get-Item -Path (Join-Path $AppFolder 'app.json')).FullName
    $AppConfig = Get-Content -Path $AppJson | ConvertFrom-Json
    New-Item -Path (Join-Path $DestinationPath $AppConfig.publisher) -ItemType Directory -ErrorAction SilentlyContinue
    $AppFileName = "$(Join-Path (Join-Path $DestinationPath $AppConfig.publisher) $AppConfig.Name).app"            
    Copy-Item -Path $App -Destination $AppFileName -Verbose
}
