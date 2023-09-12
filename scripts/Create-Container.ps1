Param(
    [Parameter(Mandatory = $true)]
    [string] $configurationFilePath,

    [ValidateSet('AzureDevOps', 'Local', 'AzureVM')]
    [Parameter(Mandatory = $false)]
    [string] $buildenv = "AzureDevOps",

    [Parameter(Mandatory = $false)]
    [string] $containerName = $ENV:CONTAINERNAME,

    [Parameter(Mandatory = $false)]
    [string] $imageName = $ENV:IMAGENAME,

    [Parameter(Mandatory = $false)]
    [string] $buildProjectFolder = $ENV:BUILD_REPOSITORY_LOCALPATH,

    [Parameter(Mandatory = $false)]
    [string] $artifact = $null,

    [Parameter(Mandatory = $false)]
    [pscredential] $credential = $null,

    [Parameter(Mandatory = $false)]
    [securestring] $licenseFile = $null,

    [bool] $reuseContainer = ($ENV:REUSECONTAINER -eq "True")
)

. (Join-Path $PSScriptRoot "HelperFunctions.ps1")

if (-not ($artifact)) {
    if ($ENV:ARTIFACTURL) {
        Write-Host "Using Artifact Url variable"
        $artifact = $ENV:ARTIFACTURL
    }
    else {
        Write-Host "Using Artifact variable"
        $artifact = $ENV:ARTIFACT
    }
}
if ($env:InsiderSasToken -eq "`$(InsiderSasToken)") {
    $env:InsiderSasToken = $null
}
else {
    Write-Host "Using Insider SAS Token"
}

if ($artifact -like 'https://*') {
    $artifactUrl = $artifact
    if ($env:InsiderSasToken) {
        $artifactUrl += $env:InsiderSasToken
    }
}
else {
    Write-Host "Finding Url for $artifact"
    $segments = "$artifact/////".Split('/')
    $artifactUrl = Get-BCArtifactUrl -storageAccount $segments[0] -type $segments[1] -version $segments[2] -country $segments[3] -select $segments[4] -sasToken $env:InsiderSasToken | Select-Object -First 1
    if (-not ($artifactUrl)) {
        throw "Unable to locate artifactUrl from $artifact"
    }
}

if (-not ($credential)) {
    $securePassword = try { $ENV:PASSWORD | ConvertTo-SecureString } catch { ConvertTo-SecureString -String $ENV:PASSWORD -AsPlainText -Force }
    $credential = New-Object PSCredential -ArgumentList $ENV:USERNAME, $SecurePassword
}

Write-Host "Create $containerName from $($artifactUrl.split('?')[0])"

$parameters = @{
    "Accept_Eula"     = $true
    "Accept_Outdated" = $true
}


$settings = (Get-Content -Path $configurationFilePath -Encoding UTF8 | Out-String | ConvertFrom-Json)

$userProfile = $settings.userProfiles | Where-Object -Property profile -EQ "$($ENV:AGENT_NAME)"
if ($userProfile) { 
    if ($userProfile.containerParameters) {
        Foreach ($parameter in ($userProfile.containerParameters.PSObject.Properties | Where-Object -Property MemberType -eq NoteProperty)) {
            try { $value = (Invoke-Expression $parameter.Value) } catch { $value = $parameter.Value }
            if (!([String]::IsNullOrEmpty($value))) { 
                try { $parameters += @{ $parameter.Name = $value } } catch { $parameters."$($parameter.Name)" = $value }
            }
        }
    }
}  
       
if ($settings.containerParameters) {
    Foreach ($parameter in ($settings.containerParameters.PSObject.Properties | Where-Object -Property MemberType -eq NoteProperty)) {
        try { $value = (Invoke-Expression $parameter.Value) } catch { $value = $parameter.Value }
        if (!([String]::IsNullOrEmpty($value))) { $parameters += @{ $parameter.Name = $value } }
    }
}

if ($licenseFile) {
    $unsecureLicenseFile = ([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($licenseFile)))
    $parameters += @{
        "licenseFile" = $unsecureLicenseFile
    }
} elseif ($ENV:LICENSEFILE -ne "`$(LicenseFile)" -and $ENV:LICENSEFILE -ne "") {
    $parameters += @{
        "licenseFile" = $ENV:LICENSEFILE
    }
}

# If azure storage App Registration information is provided and Url contains blob.core.windows.net, download licensefile using Oauth2 authentication
if ($parameters.licenseFile -ne "" -and $ENV:DOWNLOADFROMPRIVATEAZURESTORAGE -and $parameters.licenseFile.Contains("blob.core.windows.net")) {
    $parameters.licenseFile = Get-BlobFromPrivateAzureStorageOauth2 -blobUri $parameters.licenseFile
}

if ($buildenv -eq "Local") {
    $workspaceFolder = (Get-Item (Join-Path $PSScriptRoot "..")).FullName
    $additionalParameters = @("--volume ""${workspaceFolder}:C:\Source""") 
}
elseif ($buildenv -eq "AzureDevOps") {
    $segments = "$buildProjectFolder".Split('\')
    $rootFolder = "$($segments[0])\$($segments[1])"
    $additionalParameters = @(
        "--volume ""$($rootFolder):C:\Agent"""        
    )
    $parameters += @{ 
        "shortcuts" = "None"
    }
    if ($settings.dotnetAddIns) {
        $NewConfigFilePath = Join-Path $env:Agent_TempDirectory "build-settings.json"
        Copy-Item -Path $configurationFilePath -Destination $NewConfigFilePath -Force
        $parameters += @{ 
            "myscripts" = @( "$NewConfigFilePath",
                @{ "SetupAddIns.ps1" = (Get-Content -Path "${PSScriptRoot}\Copy-AddIns.ps1" -Encoding UTF8 | Out-String) })
        }
    }    
}
else {
    $workspaceFolder = (Get-Item (Join-Path $PSScriptRoot "..")).FullName
    $additionalParameters = @("--volume ""C:\DEMO:C:\DEMO""")
    $parameters += @{ 
        "shortcuts" = "None"
        "myscripts" = @(@{ "AdditionalOutput.ps1" = "copy-item -Path 'C:\Run\*.vsix' -Destination 'C:\ProgramData\bccontainerhelper\Extensions\$containerName' -force" })
    }

}

if ($settings.serverConfiguration) {
    $serverConfiguration = ''
    Foreach ($parameter in ($settings.serverConfiguration.PSObject.Properties | Where-Object -Property MemberType -eq NoteProperty)) {
        $value = $parameter.Value
        if ($serverConfiguration -eq '') {
            $serverConfiguration = "$($parameter.Name)=$($value)"
        }
        else {
            $serverConfiguration += ",$($parameter.Name)=$($value)"
        }
    }
    if ($serverConfiguration -ne '') {
        $additionalParameters += @("--env CustomNavSettings=${serverConfiguration}")
    }
}


$restoreDb = $reuseContainer -and (Test-BCContainer -containerName $containerName)
if ($restoreDb) {
    try {
        Restore-DatabasesInBCContainer -containerName $containerName -bakFolder $containerName
        Invoke-ScriptInBCContainer -containerName $containerName -scriptBlock { Param([pscredential]$credential)
            $user = Get-NAVServerUser -ServerInstance $ServerInstance | Where-Object { $_.Username -eq $credential.UserName }
            if ($user) {
                Write-Host "Setting Password for user: $($credential.UserName)"
                Set-NavServerUser -ServerInstance $ServerInstance -UserName $credential.UserName -Password $credential.Password
            }
            else {
                Write-Host "Creating user: $($credential.UserName)"
                New-NavServerUser -ServerInstance $ServerInstance -UserName $credential.UserName -Password $credential.Password
                New-NavServerUserPermissionSet -ServerInstance $ServerInstance -UserName $credential.UserName -PermissionSetId "SUPER"
            }
        } -argumentList $credential
    }
    catch {
        $restoreDb = $false
    }
}
if ($imageName) {
    $parameters += @{ "imageName" = $imageName }
}

if (!$restoreDb) {
    New-BCContainer @Parameters `
        -doNotCheckHealth `
        -updateHosts `
        -containerName $containerName `
        -artifactUrl $artifactUrl `
        -auth "UserPassword" `
        -Credential $credential `
        -additionalParameters $additionalParameters `
        -doNotUseRuntimePackages `
        -enableTaskScheduler:$false `
        -useTraefik:$false `
        -multitenant:$false 

    & "${PSScriptRoot}\Publish-Dependencies.ps1" -configurationFilePath $configurationFilePath -buildEnv $buildEnv -containerName $containerName -buildProjectFolder $buildProjectFolder -skipVerification
    
    if ($settings.includeTestRunnerOnly) {
        Import-TestToolkitToBcContainer -containerName $containerName -includeTestRunnerOnly 
    }
    if ($settings.includeTestLibrariesOnly) {
        Import-TestToolkitToBcContainer -containerName $containerName -includeTestLibrariesOnly 
    }
    if ($settings.includeTestFrameworkOnly) {
        Import-TestToolkitToBcContainer -containerName $containerName -includeTestFrameworkOnly
    }
    if ($settings.testToolkitCountry) {
        Import-TestToolkitToBcContainer -containerName $containerName -testToolkitCountry $settings.testToolkitCountry
    }
    
    
    if ($reuseContainer) {
        Backup-BCContainerDatabases -containerName $containerName -bakFolder $containerName
    }
}