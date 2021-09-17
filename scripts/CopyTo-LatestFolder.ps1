Param(
    [ValidateSet('AzureDevOps', 'Local', 'AzureVM')]
    [Parameter(Mandatory = $false)]
    [string] $buildEnv = "AzureDevOps",

    [Parameter(Mandatory = $false)]
    [string] $buildArtifactFolder = $ENV:BUILD_ARTIFACTSTAGINGDIRECTORY,

    [Parameter(Mandatory = $false)]
    [string] $folder = 'current',

    [Parameter(Mandatory = $true)]
    [string] $appFolders
)


$DestinationPath = Join-Path $buildArtifactFolder $folder;
New-Item -Path $DestinationPath -ItemType Directory;
foreach ($folder in ($appFolders.Split(','))) {
    $App = @(Get-ChildItem (Join-Path $buildArtifactFolder $folder) -Filter '*.app') | Select-Object -First 1
    $AppJson = @(Get-ChildItem (Join-Path $buildArtifactFolder $folder) -Filter 'app.json') | Select-Object -First 1
    $AppConfig = Get-Content -Path $AppJson | ConvertFrom-Json
    New-Item -Path (Join-Path $DestinationPath $AppConfig.publisher) -ItemType Directory -ErrorAction SilentlyContinue
    $AppFileName = "$(Join-Path (Join-Path $DestinationPath $AppConfig.publisher) $AppConfig.Name).app"            
    Copy-Item -Path $App -Destination $AppFileName -Verbose
}