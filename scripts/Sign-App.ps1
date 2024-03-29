﻿Param(
    [ValidateSet('AzureDevOps','Local','AzureVM')]
    [Parameter(Mandatory=$false)]
    [string] $buildEnv = "AzureDevOps",

    [Parameter(Mandatory=$false)]
    [string] $containerName = $ENV:CONTAINERNAME,

    [Parameter(Mandatory=$false)]
    [string] $buildArtifactFolder = $ENV:BUILD_ARTIFACTSTAGINGDIRECTORY,

    [Parameter(Mandatory=$true)]
    [string] $appFolders,

    [Parameter(Mandatory=$false)]
    [securestring] $codeSignPfxFile = $null,

    [Parameter(Mandatory=$false)]
    [securestring] $codeSignPfxPassword = $null
)

. (Join-Path $PSScriptRoot "HelperFunctions.ps1")

if (-not ($CodeSignPfxFile)) {
    $CodeSignPfxFile = try { $ENV:CODESIGNPFXFILE | ConvertTo-SecureString } catch { ConvertTo-SecureString -String $ENV:CODESIGNPFXFILE -AsPlainText -Force }
}

if (-not ($CodeSignPfxPassword)) {
    $CodeSignPfxPassword = try { $ENV:CODESIGNPFXPASSWORD | ConvertTo-SecureString } catch { ConvertTo-SecureString -String $ENV:CODESIGNPFXPASSWORD -AsPlainText -Force }
}

$unsecurepfxFile = ([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($codeSignPfxFile)))

# If azure storage App Registration information is provided and Url contains blob.core.windows.net, download certificate using Oauth2 authentication
if ($ENV:DOWNLOADFROMPRIVATEAZURESTORAGE -and $unsecurepfxFile.Contains("blob.core.windows.net")) {
    $unsecurepfxFile = Get-BlobFromPrivateAzureStorageOauth2 -blobUri $unsecurepfxFile
}

$appFolders.Split(',') | ForEach-Object {
    Write-Host "Signing $_"
    Get-ChildItem -Path (Join-Path $buildArtifactFolder $_) -Filter "*.app" | ForEach-Object {
        Sign-BCContainerApp -containerName $containerName -appFile $_.FullName -pfxFile $unsecurePfxFile -pfxPassword $codeSignPfxPassword
    }
}