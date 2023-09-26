Param(
    [ValidateSet('AzureDevOps', 'Local', 'AzureVM')]
    [Parameter(Mandatory = $false)]
    [string] $buildEnv = "AzureDevOps",

    [Parameter(Mandatory = $false)]
    [string] $containerName = $ENV:CONTAINERNAME,

    [Parameter(Mandatory = $false)]
    [string] $buildProjectFolder = $ENV:BUILD_REPOSITORY_LOCALPATH,

    [Parameter(Mandatory = $false)]
    [string] $buildArtifactFolder = $ENV:BUILD_ARTIFACTSTAGINGDIRECTORY,

    [Parameter(Mandatory = $true)]
    [string] $appFolders,

    [switch] $skipVerification,

    [Parameter(Mandatory = $false)]
    [string] $SyncAppMode = "Add"
)

if (-not ($credential)) {
    $securePassword = try { $ENV:PASSWORD | ConvertTo-SecureString } catch { ConvertTo-SecureString -String $ENV:PASSWORD -AsPlainText -Force }
    $credential = New-Object PSCredential -ArgumentList $ENV:USERNAME, $SecurePassword
}

Sort-AppFoldersByDependencies -appFolders $appFolders.Split(',') -baseFolder $buildProjectFolder -WarningAction SilentlyContinue | ForEach-Object {
    Write-Host "Publishing $_"
    Get-ChildItem -Path (Join-Path $buildArtifactFolder $_) -Filter "*.app" | ForEach-Object {
        if ($SyncAppMode -eq "ForceSync") {
            Publish-BCContainerApp -containerName $containerName -appFile $_.FullName -skipVerification:$skipVerification -scope Tenant -sync -install -upgrade -useDevEndpoint -credential $credential -syncMode ForceSync
        } else {
            Publish-BCContainerApp -containerName $containerName -appFile $_.FullName -skipVerification:$skipVerification -scope Tenant -sync -install -upgrade -useDevEndpoint -credential $credential
        }
    }
}
