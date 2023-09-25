Param(
    [ValidateSet('AzureDevOps','Local','AzureVM')]
    [Parameter(Mandatory=$false)]
    [string] $buildenv = "AzureDevOps",

    [Parameter(Mandatory=$false)]
    [string] $containerName = $ENV:CONTAINERNAME,
    
    [Parameter(Mandatory=$false)]
    [pscredential] $credential = $null,
    
    [Parameter(Mandatory=$false)]
    [string] $buildProjectFolder = $ENV:BUILD_REPOSITORY_LOCALPATH,

    [Parameter(Mandatory=$false)]
    [string] $buildSymbolsFolder = (Join-Path $buildProjectFolder ".alPackages"),

    [Parameter(Mandatory=$false)]
    [string] $buildArtifactFolder = $ENV:BUILD_ARTIFACTSTAGINGDIRECTORY,
    
    [Parameter(Mandatory=$true)]
    [string] $appFolders,

    [Parameter(Mandatory=$false)]
    [string] $appVersion = "",
    
    [switch] $updateSymbols,
    [switch] $updateDependencies,
    [switch] $publishApp,
    [switch] $skipVerification,

    [Parameter(Mandatory = $false)]
    [bool] $changesOnly = $false
)

if (-not ($credential)) {
    $securePassword = try { $ENV:PASSWORD | ConvertTo-SecureString } catch { ConvertTo-SecureString -String $ENV:PASSWORD -AsPlainText -Force }
    $credential = New-Object PSCredential -ArgumentList $ENV:USERNAME, $SecurePassword
}

Sort-AppFoldersByDependencies -appFolders $appFolders.Split(',') -baseFolder $buildProjectFolder -WarningAction SilentlyContinue | ForEach-Object {
    
    $appProjectFolder = Join-Path $buildProjectFolder $_

    if ($changesOnly) {
        if ($appVersion) {
            $version = [System.Version]::Parse($appVersion)
            Write-Host "Using Version $version"
            $appJsonFile = Join-Path $appProjectFolder "app.json"
            $appJson = Get-Content $appJsonFile | ConvertFrom-Json
            Write-Host "Building version $($appJson.version) of $($appJson.name)"
            if (!($appJson.version.StartsWith("$($version.Major).$($version.Minor - 1)."))) {
                throw "Major and Minor version of app doesn't match with pipeline"
            }
            $appJson.version = "$version"
            $appJson | ConvertTo-Json -Depth 99 | Set-Content $appJsonFile
        }
    } else {
        if ($appVersion) {
            $version = [System.Version]::Parse($appVersion)
            Write-Host "Using Version $version"
            $appJsonFile = Join-Path $appProjectFolder "app.json"
            $appJson = Get-Content $appJsonFile | ConvertFrom-Json
            Write-Host "Building version $($appJson.version) of $($appJson.name)"
            if (!($appJson.version.StartsWith("$($version.Major).$($version.Minor)."))) {
                throw "Major and Minor version of app doesn't match with pipeline"
            }
            $appJson.version = "$version"
            $appJson | ConvertTo-Json -Depth 99 | Set-Content $appJsonFile
        }
    }

    Write-Host "Compiling $_"
    $appFile = Compile-AppInBCContainer -containerName $containerName -credential $credential -appProjectFolder $appProjectFolder -appSymbolsFolder $buildSymbolsFolder -appOutputFolder (Join-Path $buildArtifactFolder $_) -UpdateSymbols:$updateSymbols -UpdateDependencies:$updateDependencies -AzureDevOps:($buildenv -eq "AzureDevOps")
    if ($appFile -and (Test-Path $appFile)) {
        Copy-Item -Path $appFile -Destination $buildSymbolsFolder -Force
        Copy-Item -Path (Join-Path $buildProjectFolder "$_\app.json") -Destination (Join-Path $buildArtifactFolder "$_\app.json")
        if ($publishApp) {
            if (-not ($credential)) {
                $securePassword = try { $ENV:PASSWORD | ConvertTo-SecureString } catch { ConvertTo-SecureString -String $ENV:PASSWORD -AsPlainText -Force }
                $credential = New-Object PSCredential -ArgumentList $ENV:USERNAME, $SecurePassword
            }
            Write-Host "Publishing $_"
            Publish-BCContainerApp -containerName $containerName -appFile $appFile -skipVerification:$skipVerification -scope Tenant -sync -install -upgrade -useDevEndpoint -credential $credential
        } 
    }
}
