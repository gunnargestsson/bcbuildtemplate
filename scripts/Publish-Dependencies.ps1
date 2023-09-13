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

$settings = (Get-Content -Path $configurationFilePath -Encoding UTF8 | Out-String | ConvertFrom-Json)
$settings.dependencies | ForEach-Object {
    Write-Host "Publishing $_"
        
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
        $appFile = Get-ChildItem -Path $appFolder -Recurse -Include *.app -File | Select-Object -First 1
    } else {
        Write-Host "Downloading app file $($_) to $($appFile)"        
        $appFile = Join-Path $env:TEMP "$($guid.Guid).app"   
        
        # If azure storage App Registration information is provided and Url contains blob.core.windows.net, download dependency app using Oauth2 authentication
        if ($ENV:DOWNLOADFROMPRIVATEAZURESTORAGE -and $_.Contains("blob.core.windows.net")) {
            $appFile = Get-BlobFromPrivateAzureStorageOauth2 -blobUri $_
        }
        else {
            Download-File -sourceUrl $_ -destinationFile $appFile
        }
    }

    Write-Host "Container deployment to ${containerName}"
    Publish-BCContainerApp -containerName $containerName -appFile $appFile -skipVerification -scope Global
    $containerPath = Join-Path "C:\Run\My" (Split-Path -Path $appFile -Leaf)
    Copy-FileToBcContainer -containerName $containerName -localPath $appFile -containerPath $containerPath 
    
    $appName = Invoke-ScriptInBcContainer -containerName $containerName -scriptblock {
        param($appFile)
        return (Get-NAVAppInfo -Path $appFile).Name
    } -argumentList $containerPath

    Invoke-ScriptInBcContainer -containerName $containerName -scriptblock {
        Param($appName)
        $ServerInstance = (Get-NAVServerInstance | Where-Object -Property Default -EQ True).ServerInstance
        Write-Host "Updating app '${appName}' on server instance '${ServerInstance}'..."

        foreach ($Tenant in (Get-NAVTenant -ServerInstance $ServerInstance).Id) {                                      
            $apps = Get-NAVAppInfo -ServerInstance $ServerInstance -Tenant $Tenant -TenantSpecificProperties -Name $appName
            foreach ($app in $apps | Sort-Object -Property Version) {
                Write-Host "Investigating app $($app.Name) v$($app.version) installed=$($app.isInstalled)"
                $NewApp = $apps | Where-Object -Property Name -EQ $app.Name | Where-Object -Property Version -GT $app.version                            
                if ($NewApp) {
                    if (Get-NAVAppInfo -ServerInstance $ServerInstance -Tenant $Tenant -TenantSpecificProperties | Where-Object -Property Name -EQ $Newapp.Name | Where-Object -Property Version -LT $Newapp.Version | Where-Object -Property IsInstalled -EQ $true) {
                        Write-Host "upgrading app $($app.Name) v$($app.Version) to v$($NewApp.Version) in tenant $($Tenant)"
                        Sync-NAVApp -ServerInstance $ServerInstance -Tenant $Tenant -Name $NewApp.Name -Version $NewApp.Version -Force
                        Start-NAVAppDataUpgrade -ServerInstance $ServerInstance -Tenant $Tenant -Name $NewApp.Name -Version $NewApp.Version -Force
                    }
                    else {
                        Write-Host "Newer App is available"
                    }
                }
                elseif (Get-NAVAppInfo -ServerInstance $ServerInstance -Tenant $Tenant -TenantSpecificProperties | Where-Object -Property Name -EQ $app.Name | Where-Object -Property Version -EQ $app.Version | Where-Object -Property IsInstalled -EQ $false) {
                    Write-Host "installing app $($app.Name) v$($app.Version) in tenant $($Tenant)"
                    Sync-NAVApp -ServerInstance $ServerInstance -Tenant $Tenant -Name $app.Name -Version $app.Version -Force
                    Install-NAVApp -ServerInstance $ServerInstance -Tenant $Tenant -Name $app.Name -Version $app.Version -Force
                }                   
            }
        }
    } -argumentList $appName

    Remove-Item -Path $appFile -Force -ErrorAction SilentlyContinue
    if ($appFolder) { Remove-Item -Path $appFolder -Force -Recurse -ErrorAction SilentlyContinue }
}