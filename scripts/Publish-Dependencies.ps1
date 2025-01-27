Param(
    [Parameter(Mandatory = $true)]
    [string] $configurationFilePath,
    
    [ValidateSet('AzureDevOps', 'Local', 'AzureVM')]
    [Parameter(Mandatory = $false)]
    [string] $buildEnv = "AzureDevOps",

    [Parameter(Mandatory = $false)]
    [string] $containerName = $ENV:CONTAINERNAME,

    [Parameter(Mandatory = $false)]
    [string] $buildProjectFolder = $ENV:BUILD_REPOSITORY_LOCALPATH,

    [switch] $skipVerification
)

. (Join-Path $PSScriptRoot "HelperFunctions.ps1")

if (-not ($credential)) {
    $securePassword = try { $ENV:PASSWORD | ConvertTo-SecureString } catch { ConvertTo-SecureString -String $ENV:PASSWORD -AsPlainText -Force }
    $credential = New-Object PSCredential -ArgumentList $ENV:USERNAME, $SecurePassword
}

$settings = (Get-Content -Path $configurationFilePath -Encoding UTF8 | Out-String | ConvertFrom-Json)
$settings.dependencies | ForEach-Object {
    Write-Host "Publishing $_ to ${containerName}"
        
    $guid = New-Guid
    if ($_.EndsWith(".zip", "OrdinalIgnoreCase") -or $_.Contains(".zip?")) {        
        $appFolder = Join-Path $env:TEMP $guid.Guid
        $appFile = Join-Path $env:TEMP "$($guid.Guid).zip"
        Write-Host "Downloading app file $($_) to $($appFile)"  
        
        # If azure storage App Registration information is provided and Url contains blob.core.windows.net, download dependency zip using Oauth2 authentication        
        if ($ENV:DOWNLOADFROMPRIVATEAZURESTORAGE -and $_.Contains("blob.core.windows.net")) {
            $appFile = Get-BlobFromPrivateAzureStorageOauth2 -blobUri $_
        }
        else {
            Download-File -sourceUrl $_ -destinationFile $appFile
        }
        New-Item -ItemType Directory -Path $appFolder -Force | Out-Null
        Write-Host "Extracting .zip file "
        Expand-Archive -Path $appFile -DestinationPath $appFolder
        Remove-Item -Path $appFile -Force
        foreach ($appFile in Get-ChildItem -Path $appFolder -Recurse -Include *.app -File) {
            Publish-BCContainerApp -containerName $containerName -appFile $appFile.FullName -skipVerification -scope Tenant -sync -install -upgrade -useDevEndpoint -credential $credential
        }
        if ($appFolder) { Remove-Item -Path $appFolder -Force -Recurse -ErrorAction SilentlyContinue }
    } else {
        Write-Host "Downloading app file $($_) to $($appFile)"        
        $appFile = Join-Path $env:TEMP "$($guid.Guid).app"   
         # If azure storage App Registration information is provided and Url contains blob.core.windows.net, download dependency zip using Oauth2 authentication        
         if ($ENV:DOWNLOADFROMPRIVATEAZURESTORAGE -and $_.Contains("blob.core.windows.net")) {
            $appFile = Get-BlobFromPrivateAzureStorageOauth2 -blobUri $_
        }
        else {
            Download-File -sourceUrl $_ -destinationFile $appFile
        }
        Publish-BCContainerApp -containerName $containerName -appFile $appFile -skipVerification -scope Tenant -sync -install -upgrade -useDevEndpoint -credential $credential
        Remove-Item -Path $appFile -Force -ErrorAction SilentlyContinue
    }
}