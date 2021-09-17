Param(
    [ValidateSet('AzureDevOps', 'Local', 'AzureVM')]
    [Parameter(Mandatory = $false)]
    [string] $buildEnv = "AzureDevOps",

    [Parameter(Mandatory = $false)]
    [string] $buildArtifactFolder = $ENV:BUILD_ARTIFACTSTAGINGDIRECTORY,

    [Parameter(Mandatory = $true)]
    [string] $appFolders
)


$LatestPath = Join-Path $buildArtifactFolder 'latest';
New-Item -Path $LatestPath -ItemType Directory;
foreach ($folder in ($appFolders.Split(','))) {
    $App = @(Get-ChildItem (Join-Path $buildArtifactFolder $folder) -Filter '*.app') | Select-Object -First 1
    $AppJson = @(Get-ChildItem (Join-Path $buildArtifactFolder $folder) -Filter 'app.json') | Select-Object -First 1
    $AppConfig = Get-Content -Path $AppJson | ConvertFrom-Json
    New-Item -Path (Join-Path $LatestPath $AppConfig.publisher) -ItemType Directory -ErrorAction SilentlyContinue
    $AppFileName = "$(Join-Path (Join-Path $LatestPath $AppConfig.publisher) $AppConfig.Name).app"            
    Copy-Item -Path $App -Destination $AppFileName -Verbose
}
