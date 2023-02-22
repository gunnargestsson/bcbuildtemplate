Param(
    [Parameter(Mandatory = $true)]
    [string] $artifactsFolder,

    [Parameter(Mandatory = $false)]
    [string] $appFolders = ""
    
)

foreach ($folder in ($(appFolders).Split(','))) {
    Remove-Item (Join-Path $artifactsFolder $folder) -Recurse -Force
  }