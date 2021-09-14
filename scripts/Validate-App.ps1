Param(
    [Parameter(Mandatory = $true)]
    [string] $artifactsFolder,
    
    [Parameter(Mandatory = $true)]
    [string] $branchName,

    [Parameter(Mandatory = $false)]
    [string] $buildProjectFolder = $ENV:BUILD_REPOSITORY_LOCALPATH,

    [Parameter(Mandatory = $false)]
    [securestring] $licenseFile = $null,

    [Parameter(Mandatory = $false)]
    [string] $imageName = $ENV:IMAGENAME,

    [Parameter(Mandatory = $false)]
    [string] $version = "current"
    
)

Write-Host "Validating apps for branch ${branchName}..."
$settings = (Get-Content ((Get-ChildItem -Path $buildProjectFolder -Filter "build-settings.json" -Recurse).FullName) -Encoding UTF8 | Out-String | ConvertFrom-Json)
$appFolders = $settings.appFolders
$validation = $settings.validation | Where-Object { $_.branch -eq $branchName }
if ($validation) {

    if (-not ($licenseFile)) {
        $licenseFile = try { $ENV:LICENSEFILE | ConvertTo-SecureString } catch { ConvertTo-SecureString -String $ENV:LICENSEFILE -AsPlainText -Force }
    }   

    if ($env:InsiderSasToken -eq "`$(InsiderSasToken)") {
        $env:InsiderSasToken = $null
    }
    else {
        Write-Host "Using Insider SAS Token"
    }

    Write-Host "Running AL Validation..."

    $parameters = @{}
    
    if ($licenseFile) {
        $unsecureLicenseFile = ([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($licenseFile)))
        $parameters += @{
            "licenseFile" = $unsecureLicenseFile
        }
    }

    $apps = @()
    if (($validation.previousApps).count -gt 0) {
        $parameters += @{
            previousApps = $validation.previousApps
        }
    }

    if ($env:InsiderSasToken) {
        $parameters += @{
            sasToken = $env:InsiderSasToken
        }
    }

    if ($imageName) {
        $parameters += @{ 
            imageName = $imageName 
        }
    }
    Sort-AppFoldersByDependencies -appFolders $appFolders.Split(',') -baseFolder $buildProjectFolder -WarningAction SilentlyContinue | ForEach-Object {
        $appFolder = $_
        $appFile = (Get-Item (Join-Path $artifactsFolder "$appFolder\*.app")).FullName

        Write-Host "App File: ${appFile}"
        $apps += $appFile        
    }

    Run-AlValidation @parameters `
        -apps $apps `
        -affixes $validation.affixes `
        -countries $validation.countries `
        -supportedCountries $validation.supportedCountries `
        -validateCurrent:($version -eq "current") `
        -validateNextMinor:($version -eq "nextminor") `
        -validateNextMajor:($version -eq "nextmajor") `
        -failOnError        
}