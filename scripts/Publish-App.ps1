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

    [Parameter(Mandatory = $false)]
    $licenseFile = $null,

    [switch] $skipVerification
)

if (-not ($licenseFile)) {
    $licenseFile = try { $ENV:LICENSEFILE | ConvertTo-SecureString } catch { ConvertTo-SecureString -String $ENV:LICENSEFILE -AsPlainText -Force }
}

if ($licenseFile) {    
    $unsecureLicenseFile = try { ([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($licenseFile))) } catch { $licenseFile }
    Import-BcContainerLicense -containerName $containerName -licenseFile $unsecureLicenseFile 
}

Sort-AppFoldersByDependencies -appFolders $appFolders.Split(',') -baseFolder $buildProjectFolder -WarningAction SilentlyContinue | ForEach-Object {
    Write-Host "Publishing $_"
    Get-ChildItem -Path (Join-Path $buildArtifactFolder $_) -Filter "*.app" | ForEach-Object {
        Publish-BCContainerApp -containerName $containerName -appFile $_.FullName -skipVerification:$skipVerification -sync -install
    }
}
