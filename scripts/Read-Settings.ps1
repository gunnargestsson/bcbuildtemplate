Param(
    [Parameter(Mandatory = $true)]
    [string] $configurationFilePath,

    [ValidateSet('AzureDevOps', 'Local', 'AzureVM')]
    [Parameter(Mandatory = $false)]
    [string] $buildEnv = "AzureDevOps",

    [Parameter(Mandatory = $false)]
    [string] $version = $ENV:VERSION,

    [Parameter(Mandatory = $false)]
    [string] $buildProjectFolder = $ENV:BUILD_REPOSITORY_LOCALPATH,

    [Parameter(Mandatory = $false)]
    [string] $appVersion = "",

    [Parameter(Mandatory = $true)]
    [string] $branchName
)

if ($ENV:PASSWORD -eq "`$(Password)" -or $ENV:PASSWORD -eq "") { 
    add-type -AssemblyName System.Web
    $Password = [System.Web.Security.Membership]::GeneratePassword(10, 2)
    Write-Host "Set Password = $Password"
    Write-Host "##vso[task.setvariable variable=Password]$Password" 
}

Write-Host "Set SyncAppMode = $ENV:SyncAppMode"
Write-Host "##vso[task.setvariable variable=SyncAppMode]$ENV:SyncAppMode" 


if ($appVersion) {
    Write-Host "Updating build number to $appVersion"
    write-host "##vso[build.updatebuildnumber]$appVersion"
}

$settings = (Get-Content -Path $configurationFilePath -Encoding UTF8 | Out-String | ConvertFrom-Json)
if ("$version" -eq "") {
    $version = $settings.versions[0].version
    Write-Host "Version not defined, using $version"
}

$imageName = "build"
$property = $settings.PSObject.Properties.Match('imageName')
if ($property.Value) {
    $imageName = $property.Value
}

$property = $settings.PSObject.Properties.Match('bccontainerhelperVersion')
if ($property.Value) {
    $bccontainerhelperVersion = $property.Value
}
else {
    $bccontainerhelperVersion = "latest"
}
Write-Host "Set bccontainerhelperVersion = $bccontainerhelperVersion"
Write-Host "##vso[task.setvariable variable=bccontainerhelperVersion]$bccontainerhelperVersion"

$appFolders = $settings.appFolders
Write-Host "Set appFolders = $appFolders"
Write-Host "##vso[task.setvariable variable=appFolders]$appFolders"

$testFolders = $settings.testFolders
Write-Host "Set testFolders = $testFolders"
Write-Host "##vso[task.setvariable variable=testFolders]$testFolders"

$property = $settings.PSObject.Properties.Match('azureBlob')
if ($property.Value) {
    $branches = $settings.azureBlob.PSObject.Properties.Match('BranchNames')
    if ($branches.Value) {
        if ($branches.Value -icontains $branchName -or $branches.Value -icontains ($branchName.split('/') | Select-Object -Last 1)) {
            Write-Host "Set azureStorageAccount = $($settings.azureBlob.azureStorageAccount)"
            Write-Host "##vso[task.setvariable variable=azureStorageAccount]$($settings.azureBlob.azureStorageAccount)"
            Write-Host "Set azureContainerName = $($settings.azureBlob.azureContainerName)"
            Write-Host "##vso[task.setvariable variable=azureContainerName]$($settings.azureBlob.azureContainerName)"            
        }
        else {
            Write-Host "Set azureStorageAccount = ''"
            Write-Host "##vso[task.setvariable variable=azureStorageAccount]"        
        }
    }
    else {
        Write-Host "Set azureStorageAccount = $($settings.azureBlob.azureStorageAccount)"
        Write-Host "##vso[task.setvariable variable=azureStorageAccount]$($settings.azureBlob.azureStorageAccount)"
        Write-Host "Set azureContainerName = $($settings.azureBlob.azureContainerName)"
        Write-Host "##vso[task.setvariable variable=azureContainerName]$($settings.azureBlob.azureContainerName)"            
    }
}
else {
    Write-Host "Set azureStorageAccount = ''"
    Write-Host "##vso[task.setvariable variable=azureStorageAccount]"
}

$imageversion = $settings.versions | Where-Object { $_.version -eq $version }
if ($imageversion) {
    Write-Host "Set artifact = $($imageVersion.artifact)"
    Write-Host "##vso[task.setvariable variable=artifact]$($imageVersion.artifact)"
    
    "reuseContainer" | ForEach-Object {
        $property = $imageVersion.PSObject.Properties.Match($_)
        if ($property.Value) {
            $propertyValue = $property.Value
        }
        else {
            $propertyValue = $false
        }
        Write-Host "Set $_ = $propertyValue"
        Write-Host "##vso[task.setvariable variable=$_]$propertyValue"
    }
    if ($imageVersion.PSObject.Properties.Match("imageName").Value) {
        $imageName = $imageversion.imageName
    }
}
else {
    throw "Unknown version: $version"
}

if ("$($ENV:AGENT_NAME)" -eq "Hosted Agent" -or "$($ENV:AGENT_NAME)" -like "Azure Pipelines*") {
    $containerNamePrefix = "ci"
    Write-Host "Set imageName = ''"
    Write-Host "##vso[task.setvariable variable=imageName]"
}
else {
    if ($imageName -iin ("", "build", "ci")) {
        $containerNamePrefix = $settings.name
    }
    else {
        $containerNamePrefix = $imageName
    }
    
    Write-Host "Set imageName = $imageName"
    Write-Host "##vso[task.setvariable variable=imageName]$imageName"
}

Write-Host "Agent Name:" $($ENV:AGENT_NAME)
Write-Host "Repository: $($ENV:BUILD_REPOSITORY_NAME)"
Write-Host "Build Reason: $($ENV:BUILD_REASON)"
Write-Host "Container Name Prefx: ${containerNamePrefix}"

$buildName = ($ENV:BUILD_REPOSITORY_NAME).Split('/')[1]

if ([string]::IsNullOrEmpty($buildName)) {
    $buildName = ($ENV:BUILD_REPOSITORY_NAME).Split('/')[0]
}

$buildName = $buildName -replace '[^a-zA-Z0-9]', ''

if ($buildName.Length -gt 10) {
    $buildName = $buildName.Substring(0, 10)
}

Write-Host "Build Name: ${buildName}"

$buildNumber = $ENV:BUILD_BUILDNUMBER -replace '[^a-zA-Z0-9]', ''
if ($buildNumber.Length -gt 8) {
    $buildNumber = $buildNumber.Substring(8)
}

Write-Host "Build Number: ${buildNumber}"

$containerName = "${containerNamePrefix}${buildName}".ToUpper()
if ($containerName.Length -gt (15 - $buildNumber.Length)) {
    $containerName = $containerName.Substring(0, (15 - $buildNumber.Length))
}
$containerName = "${containerName}${buildNumber}"

Write-Host "Set containerName = $containerName"
Write-Host "##vso[task.setvariable variable=containerName]$containerName"

$testCompanyName = $settings.TestMethod.companyName
Write-Host "Set testCompanyName = $testCompanyName"
Write-Host "##vso[task.setvariable variable=testCompanyName]$testCompanyName"

$testCodeunitId = $settings.TestMethod.CodeunitId
Write-Host "Set testCodeunitId = $testCodeunitId"
Write-Host "##vso[task.setvariable variable=testCodeunitId]$testCodeunitId"

$testMethodName = $settings.TestMethod.MethodName
Write-Host "Set testMethodName = $testMethodName"
Write-Host "##vso[task.setvariable variable=testMethodName]$testMethodName"

if ($ENV:AZSTORAGETENANTID -ne "`$(AzStorageTenantId)" -and $ENV:AZSTORAGETENANTID -ne "") { $AzStorageTenantIdIsSet = $true } else { $AzStorageTenantIdIsSet = $false }
if ($ENV:AZSTORAGECLIENTID -ne "`$(AzStorageClientId)" -and $ENV:AZSTORAGECLIENTID -ne "") { $AzStorageClientIdIsSet = $true } else { $AzStorageClientIdIsSet = $false }
if ($ENV:AZSTORAGECLIENTSECRET -ne "`$(AzStorageClientSecret)" -and $ENV:AZSTORAGECLIENTSECRET -ne "") { $AzStorageClientSecretIsSet = $true } else { $AzStorageClientSecretIsSet = $false }

if ($AzStorageTenantIdIsSet -and $AzStorageClientIdIsSet -and $AzStorageClientSecretIsSet) {
    Write-Host "Set downloadFromPrivateAzureStorage = $true"
    Write-Host "##vso[task.setvariable variable=downloadFromPrivateAzureStorage]$true"
}