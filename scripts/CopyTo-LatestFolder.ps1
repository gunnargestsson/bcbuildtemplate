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
foreach ($folder in ($appFolders.Split(','))) {
    $AppFolder = Join-Path $buildArtifactFolder $folder
    $App = @(Get-ChildItem $AppFolder -Filter '*.app') | Select-Object -First 1
    $AppJson = @(Get-ChildItem $AppFolder -Filter 'app.json') | Select-Object -First 1
    $AppConfig = Get-Content -Path $AppJson | ConvertFrom-Json
    New-Item -Path (Join-Path $DestinationPath $AppConfig.publisher) -ItemType Directory -ErrorAction SilentlyContinue
    $AppFileName = "$(Join-Path (Join-Path $DestinationPath $AppConfig.publisher) $AppConfig.Name).app"            
    Copy-Item -Path $App -Destination $AppFileName -Verbose
}
