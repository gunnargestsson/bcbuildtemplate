Param(
    [Parameter(Mandatory = $true)]
    [string] $configurationFilePath,

    [Parameter(Mandatory = $true)]
    [string] $artifactsFolder,

    [Parameter(Mandatory = $true)]
    [string] $branchName,

    [Parameter(Mandatory = $false)]
    [string] $buildProjectFolder = $ENV:BUILD_REPOSITORY_LOCALPATH,

    [Parameter(Mandatory = $false)]
    $clientId = $ENV:CLIENTID,
    
    [Parameter(Mandatory = $false)]
    $clientSecret = $ENV:CLIENTSECRET,

    [Parameter(Mandatory = $false)]   
    $PowerShellUsername = $ENV:PowerShellUsername,

    [Parameter(Mandatory = $false)]
    $PowerShellPassword = $ENV:PowerShellPassword,

    [Parameter(Mandatory = $false)]
    [string] $SyncAppMode = "Add"
    
)

Write-Host "Deploying apps from ${artifactsFolder} to branch ${branchName} ..."
Write-Host "NAV App Sync mode is set to $SyncAppMode"
$settings = (Get-Content -Path $configurationFilePath -Encoding UTF8 | Out-String | ConvertFrom-Json)
if ($clientId -is [string]) {
    if ($clientSecret -is [String]) { $clientSecret = ConvertTo-SecureString -String $clientSecret -AsPlainText -Force }
    if ($clientSecret -isnot [SecureString]) { throw "ClientSecret needs to be a SecureString or a String" }
}
if ($PowerShellUsername -is [string]) {
    if ($PowerShellPassword -is [String]) { $PowerShellPassword = ConvertTo-SecureString -String $PowerShellPassword -AsPlainText -Force }
    if ($PowerShellPassword -isnot [SecureString]) { throw "PowerShellPassword needs to be a SecureString or a String" }
    $vmCredential = New-Object System.Management.Automation.PSCredential($PowerShellUsername, $PowerShellPassword);
}
$appFolders = $settings.appFolders
$deployments = @()
$deployments += $settings.deployments | Where-Object { $_.branch -eq $branchName }
$deployments += $settings.deployments | Where-Object { $_.branch -eq ($branchName.split('/') | Select-Object -Last 1)}
foreach ($deployment in $deployments) {
    $deploymentType = $deployment.DeploymentType
    if (($deployment.reason).Count -gt 0) {
        if ($ENV:BUILD_REASON -notin $deployment.reason) {
            Write-Host "Skip deployment $($deploymentType), Reason: $($ENV:BUILD_REASON) <> $($deployment.reason) "
            continue
        }
    }

    $artifactsFolder = (Get-Item $artifactsFolder).FullName
    Write-Host "Folder: $artifactsFolder"
    $vmSession = $null

    Sort-AppFoldersByDependencies -appFolders $appFolders.Split(',') -baseFolder $artifactsFolder -WarningAction SilentlyContinue | ForEach-Object {
        
        $appFolder = $_
        Write-Host "Deploying ${appFolder} to ${deploymentType}"
        $appFile = (Get-Item (Join-Path $artifactsFolder "$appFolder\*.app")).FullName
        $appJsonFile = (Get-Item (Join-Path $artifactsFolder "$appFolder\app.json")).FullName
        $appJson = Get-Content $appJsonFile | ConvertFrom-Json

        if ($deploymentType -eq "onlineTenant") {
            $environment = $deployment.DeployToName;
            foreach ($tenantId in $deployment.DeployToTenants) {
                Write-Host "Online Tenant deployment to https://businesscentral.dynamics.com/${tenantId}/${environment}/"
                $authContext = New-BcAuthContext -clientID $clientId -clientSecret $clientSecret -tenantID $tenantId -scopes "https://api.businesscentral.dynamics.com/.default" 
                Publish-PerTenantExtensionApps -bcAuthContext $authContext -environment $environment -appFiles $appFile -Verbose
            }
        }
        elseif ($deploymentType -eq "container" -and ($deployment.DeployToTenants).Count -eq 0) {
            $containerName = $deployment.DeployToName
            Write-Host "Container deployment to ${containerName}"
        
            $ErrorActionPreference = "Stop"
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
                                Sync-NAVApp -ServerInstance $ServerInstance -Tenant $Tenant -Name $NewApp.Name -Version $NewApp.Version -Force -Mode $SyncAppMode
                                Start-NAVAppDataUpgrade -ServerInstance $ServerInstance -Tenant $Tenant -Name $NewApp.Name -Version $NewApp.Version -Force
                            }
                            else {
                                Write-Host "Newer App is available"
                            }
                        }
                        elseif (Get-NAVAppInfo -ServerInstance $ServerInstance -Tenant $Tenant -TenantSpecificProperties | Where-Object -Property Name -EQ $app.Name | Where-Object -Property Version -EQ $app.Version | Where-Object -Property IsInstalled -EQ $false) {
                            Write-Host "installing app $($app.Name) v$($app.Version) in tenant $($Tenant)"
                            Sync-NAVApp -ServerInstance $ServerInstance -Tenant $Tenant -Name $app.Name -Version $app.Version -Force -Mode $SyncAppMode
                            Install-NAVApp -ServerInstance $ServerInstance -Tenant $Tenant -Name $app.Name -Version $app.Version -Force
                        }                   
                    }

                    $allTenantsApps = @()
                    foreach ($Tenant in (Get-NAVTenant -ServerInstance $ServerInstance).Id) {                                    
                        $allTenantsApps += Get-NAVAppInfo -ServerInstance $ServerInstance -Tenant $Tenant -TenantSpecificProperties -Name $appName | Where-Object -Property IsInstalled -EQ $true
                    }
                        
                    $apps = Get-NAVAppInfo -ServerInstance $ServerInstance -Name $appName
                    foreach ($app in $apps | Sort-Object -Property Version) {
                        $NoOfApps = @($apps | Where-Object -Property Name -EQ $app.Name | Where-Object -Property Version -GT $app.Version).Count
                        $NoOfInstalledApps = @($allTenantsApps | Where-Object -Property Version -EQ $app.Version).Count
                        if ($NoOfApps -gt 0 -and $NoOfInstalledApps -eq 0) {
                            Write-Host "Unpublishing old app $($app.Name) $($app.Version)"
                            try {
                                Unpublish-NAVApp -ServerInstance $ServerInstance -Name $app.Name -Publisher $app.Publisher -Version $app.Version
                            }
                            catch {
                                Write-Host "Unable to unpublish $($app.Name) v$($app.Version)"
                            }
                        }
                    }
                } 
            } -argumentList $appName
        }
        elseif ($deploymentType -eq "container") {
            $containerName = $deployment.DeployToName
            $Tenants = $deployment.DeployToTenants
            Write-Host "Container deployment to ${containerName}"
    
            $ErrorActionPreference = "Stop"
            foreach ($containerTenant in $Tenants) {
                try {
                    Write-Host "Deploying to ${containerName}\${containerTenant}"
                    Publish-BCContainerApp -containerName $containerName -tenant $containerTenant -appFile $appFile -skipVerification -sync -scope Tenant
                    $installedApp = Get-BCContainerAppInfo -containerName $containerName -Name $appJson.Name -tenant $containerTenant -tenantSpecificProperties | Where-Object -Property IsInstalled -EQ True
                    if ($installedApp) {
                        Start-BcContainerAppDataUpgrade -containerName $containerName -tenant $containerTenant -appName $appJson.Name -appVersion $appjson.version 
                    }
                    else {
                        Install-BCContainerApp -containerName $containerName -tenant $containerTenant -appName $appJson.Name -appVersion $appjson.version
                    }
                    $apps = Get-BCContainerAppInfo -containerName $containerName -tenant $containerTenant -tenantSpecificProperties | Where-Object -Property Scope -EQ Tenant | Where-Object -Property Name -EQ $appJson.Name
                    foreach ($app in $apps | Sort-Object -Property Version) {
                        Write-Host "Checking installation status for app $($app.Name) $($app.Version)"
                        $NoOfNewerApps = @($apps | Where-Object -Property Version -GT $app.Version).Count
                        $IsInstalled = ($apps | Where-Object -Property Version -EQ $app.Version).IsInstalled
                        Write-Host "No. of newer apps: ${NoOfNewerApps}"
                        Write-Host "Installed: ${IsInstalled}"
                        if ($NoOfNewerApps -gt 0 -and $IsInstalled -eq $false) {
                            Write-Host "Unpublishing old app $($app.Name) $($app.Version)"
                            try {
                                UnPublish-BCContainerApp -containerName $containerName -Name $app.Name -Publisher $app.Publisher -Version $app.Version -tenant $containerTenant
                            }
                            catch {
                                Write-Host "Unable to unpublish $($app.Name) v$($app.Version)"
                            }
                        }
                    }
                }
                catch {
                    throw "Could not publish $($appJson.name) to ${containerName}\${containerTenant}"
                }
                finally { } 
            }
        
        }

        elseif ($deploymentType -eq "host" -and ($deployment.DeployToTenants).Count -eq 0) {
            $VM = $deployment.DeployToName
            if ($deployment.InstallNewApps) {
                $installNewApps = $true
            }
            else {
                $installNewApps = $false
            }
            Write-Host "Host deployment to ${VM}"
            . (Join-Path $PSScriptRoot "SessionFunctions.ps1")
    
            $useSession = $true
            try { 
                $myip = ""; $myip = (Invoke-WebRequest -Uri http://ifconfig.me/ip).Content
                $targetip = (Resolve-DnsName $VM).IP4Address
                if ($myip -eq $targetip) {
                    $useSession = $false
                }
            }
            catch { }
                
            $tempAppFile = ""
            try {
    
                if ($useSession) {
                    if ($vmSession -eq $null) {
                        if ($vmCredential) {
                            $vmSession = New-DeploymentRemoteSession -HostName $VM  -Credential $vmCredential
                        }
                        else {
                            $vmSession = New-DeploymentRemoteSession -HostName $VM
                        }
                    }
                    $tempAppFile = CopyFileToSession -session $vmSession -localFile $appFile
                    $sessionArgument = @{ "Session" = $vmSession }
                }
                else {
                    $tempAppFile = $appFile
                    $sessionArgument = @{ }
                }
    
                Invoke-Command @sessionArgument -ScriptBlock { Param($appFile, $DeployToInstance, $installNewApps, $SyncAppMode)
                    $ErrorActionPreference = "Stop"
    
                    if ([String]::IsNullOrEmpty($DeployToInstance)) {
                        $modulePath = Get-Item 'C:\Program Files\Microsoft Dynamics 365 Business Central\*\Service\NavAdminTool.ps1'
                        Import-Module $modulePath | Out-Null
                        $ServerInstance = (Get-NAVServerInstance | Where-Object -Property Default -EQ True).ServerInstance
                    }
                    else {
                        $ServicePath = (Get-WmiObject win32_service | Where-Object { $_.Name -eq "MicrosoftDynamicsNavServer`$${DeployToInstance}" } | Select-Object Name, DisplayName, @{Name = "Path"; Expression = { $_.PathName.split('"')[1] } }).Path
                        $modulePath = Get-Item (Join-Path (Split-Path -Path $ServicePath -Parent) 'NavAdminTool.ps1')
                        Import-Module $modulePath | Out-Null
                        $ServerInstance = $DeployToInstance
                    }
                    
                    $CurrentApp = Get-NAVAppInfo -Path $appFile

                    Write-Host "Publishing v$($CurrentApp.Version)"    
                    Publish-NAVApp -ServerInstance $ServerInstance -Path $appFile -Scope Global -SkipVerification
                
                    foreach ($Tenant in (Get-NAVTenant -ServerInstance $ServerInstance).Id) {                                      
                        $apps = Get-NAVAppInfo -ServerInstance $ServerInstance -Tenant $Tenant -TenantSpecificProperties | Where-Object -Property Name -EQ $CurrentApp.Name
                        foreach ($app in $apps | Sort-Object -Property Version) {
                            Write-Host "Investigating app $($app.Name) v$($app.version) installed=$($app.isInstalled)"
                            $NewApp = $apps | Where-Object -Property Name -EQ $app.Name | Where-Object -Property Version -GT $app.version                            
                            if ($NewApp) {
                                if (Get-NAVAppInfo -ServerInstance $ServerInstance -Tenant $Tenant -TenantSpecificProperties | Where-Object -Property Name -EQ $Newapp.Name | Where-Object -Property Version -LT $Newapp.Version | Where-Object -Property IsInstalled -EQ $true) {
                                    Write-Host "upgrading app $($app.Name) v$($app.Version) to v$($NewApp.Version) in tenant $($Tenant)"
                                    Sync-NAVApp -ServerInstance $ServerInstance -Tenant $Tenant -Name $NewApp.Name -Version $NewApp.Version -Force -Mode $SyncAppMode
                                    Start-NAVAppDataUpgrade -ServerInstance $ServerInstance -Tenant $Tenant -Name $NewApp.Name -Version $NewApp.Version -Force
                                }
                                else {
                                    Write-Host "Newer App is available"
                                }
                            }
                            elseif ($installNewApps -and (Get-NAVAppInfo -ServerInstance $ServerInstance -Tenant $Tenant -TenantSpecificProperties | Where-Object -Property Name -EQ $app.Name | Where-Object -Property Version -EQ $app.Version | Where-Object -Property IsInstalled -EQ $false)) {
                                Write-Host "installing app $($app.Name) v$($app.Version) in tenant $($Tenant)"
                                Sync-NAVApp -ServerInstance $ServerInstance -Tenant $Tenant -Name $app.Name -Version $app.Version -Force -Mode $SyncAppMode
                                Install-NAVApp -ServerInstance $ServerInstance -Tenant $Tenant -Name $app.Name -Version $app.Version -Force
                            }                   
                        }
                    
                        $allTenantsApps = @()
                        foreach ($Tenant in (Get-NAVTenant -ServerInstance $ServerInstance).Id) {
                            $allTenantsApps += Get-NAVAppInfo -ServerInstance $ServerInstance -Tenant $Tenant -TenantSpecificProperties -Name $CurrentApp.Name | Where-Object -Property IsInstalled -EQ $true
                        }
                        $apps = Get-NAVAppInfo -ServerInstance $ServerInstance -Name $CurrentApp.Name | Where-Object -Property Scope -EQ Global
                        foreach ($app in $apps | Sort-Object -Property Version) {
                            $NoOfApps = @($apps | Where-Object -Property Name -EQ $app.Name | Where-Object -Property Version -GT $app.Version).Count
                            $NoOfInstalledApps = @($allTenantsApps | Where-Object -Property Version -EQ $app.Version).Count
                            if ($NoOfApps -gt 0 -and $NoOfInstalledApps -eq 0) {
                                Write-Host "Unpublishing old app $($app.Name) $($app.Version)"
                                try {
                                    Unpublish-NAVApp -ServerInstance $ServerInstance -Name $app.Name -Publisher $app.Publisher -Version $app.Version
                                }
                                catch {
                                    Write-Host "Unable to unpublish $($app.Name) v$($app.Version)"
                                }
                            }
                        }
                    }
                } -ArgumentList $tempAppFile, $deployment.DeployToInstance, $installNewApps, $SyncAppMode
            }
            catch [System.Management.Automation.Remoting.PSRemotingTransportException] {
                throw "Could not connect to $VM. Maybe port 5985 (WinRM) is not open for your IP address $myip"
            }
            finally {
                if ($vmSession) {
                    if ($tempAppFile) {
                        try { RemoveFileFromSession -session $vmSession -filename $tempAppFile } catch {}
                    }                    
                }                
            }
        }
        elseif ($deploymentType -eq "host") {
            $VM = $deployment.DeployToName
            $Tenants = $deployment.DeployToTenants
            if ($deployment.InstallNewApps) {
                $installNewApps = $true
            }
            else {
                $installNewApps = $false
            }
            Write-Host "Host deployment to ${VM}"
            . (Join-Path $PSScriptRoot "SessionFunctions.ps1")
    
            $useSession = $true
            try { 
                $myip = ""; $myip = (Invoke-WebRequest -Uri http://ifconfig.me/ip).Content
                $targetip = (Resolve-DnsName $VM).IP4Address
                if ($myip -eq $targetip) {
                    $useSession = $false
                }
            }
            catch { }
    
            $tempAppFile = ""
            try {
    
                if ($useSession) {
                    if ($vmSession -eq $null) {
                        if ($vmCredential) {
                            $vmSession = New-DeploymentRemoteSession -HostName $VM  -Credential $vmCredential
                        }
                        else {
                            $vmSession = New-DeploymentRemoteSession -HostName $VM
                        }
                        $tempAppFile = CopyFileToSession -session $vmSession -localFile $appFile
                        $sessionArgument = @{ "Session" = $vmSession }
                    }
                }
                else {
                    $tempAppFile = $appFile
                    $sessionArgument = @{ }
                }
    
                Invoke-Command @sessionArgument -ScriptBlock { Param($Tenants, $appFile, $DeployToInstance, $installNewApps, $SyncAppMode)
                    $ErrorActionPreference = "Stop"
    
                    if ([String]::IsNullOrEmpty($DeployToInstance)) {
                        $modulePath = Get-Item 'C:\Program Files\Microsoft Dynamics 365 Business Central\*\Service\NavAdminTool.ps1'
                        Import-Module $modulePath | Out-Null
                        $ServerInstance = (Get-NAVServerInstance | Where-Object -Property Default -EQ True).ServerInstance
                    }
                    else {
                        $ServicePath = (Get-WmiObject win32_service | Where-Object { $_.Name -eq "MicrosoftDynamicsNavServer`$${DeployToInstance}" } | Select-Object Name, DisplayName, @{Name = "Path"; Expression = { $_.PathName.split('"')[1] } }).Path
                        $modulePath = Get-Item (Join-Path (Split-Path -Path $ServicePath -Parent) 'NavAdminTool.ps1')
                        Import-Module $modulePath | Out-Null
                        $ServerInstance = $DeployToInstance
                    }
                    $CurrentApp = Get-NAVAppInfo -Path $appFile

                    foreach ($Tenant in $Tenants) {
                        Write-Host "Publishing $($CurrentApp.Name) (${appFile}) to ${Tenant}"
                        Get-NAVAppInfo -ServerInstance $ServerInstance -Tenant $Tenant -TenantSpecificProperties | Where-Object -Property Name -EQ $CurrentApp.Name | Where-Object -Property IsInstalled -EQ $false | ForEach-Object {
                            Write-Host "Removing unused app v$($_.Version)"
                            try {
                                Unpublish-NAVApp -ServerInstance $ServerInstance -Name $_.Name -Publisher $_.Publisher -Version $_.Version -Tenant $Tenant
                            }
                            catch {
                                Write-Host "Unable to unpublish $($_.Name) v$($_.Version) : $($PSItem.Exception.Message)"
                            }
                        }
                        Write-Host "Publishing v$($CurrentApp.Version)"    
                        Publish-NAVApp -ServerInstance $ServerInstance -Path $appFile -Tenant $Tenant -Scope Tenant -SkipVerification
            
                        $apps = Get-NAVAppInfo -ServerInstance $ServerInstance -Tenant $Tenant -TenantSpecificProperties | Where-Object -Property Name -EQ $CurrentApp.Name
                        foreach ($app in $apps | Sort-Object -Property Version) {
                            Write-Host "Investigating app $($app.Name) v$($app.version) installed=$($app.isInstalled)"
                            $NewApp = $apps | Where-Object -Property Name -EQ $app.Name | Where-Object -Property Version -GT $app.version                            
                            if ($NewApp) {
                                if (Get-NAVAppInfo -ServerInstance $ServerInstance -Tenant $Tenant -TenantSpecificProperties | Where-Object -Property Name -EQ $Newapp.Name | Where-Object -Property Version -LT $Newapp.Version | Where-Object -Property IsInstalled -EQ $true) {
                                    Write-Host "upgrading app $($app.Name) v$($app.Version) to v$($NewApp.Version) in tenant $($Tenant)"

                                    Write-Host "Sync-NAVApp -ServerInstance $($ServerInstance) -Tenant $($Tenant) -Name $($NewApp.Name) -Version $($NewApp.Version) -Mode $($SyncAppMode) -Force"
                                    Sync-NAVApp -ServerInstance $ServerInstance -Tenant $Tenant -Name $NewApp.Name -Version $NewApp.Version -Mode $SyncAppMode -Force
                                    Start-NAVAppDataUpgrade -ServerInstance $ServerInstance -Tenant $Tenant -Name $NewApp.Name -Version $NewApp.Version -Force
                                }
                                else {
                                    Write-Host "Newer App is available"
                                }
                            }
                            elseif ($installNewApps -and (Get-NAVAppInfo -ServerInstance $ServerInstance -Tenant $Tenant -TenantSpecificProperties | Where-Object -Property Name -EQ $app.Name | Where-Object -Property Version -EQ $app.Version | Where-Object -Property IsInstalled -EQ $false)) {
                                Write-Host "installing app $($app.Name) v$($app.Version) in tenant $($Tenant)"
                                Sync-NAVApp -ServerInstance $ServerInstance -Tenant $Tenant -Name $app.Name -Version $app.Version -Force -Mode $SyncAppMode
                                Install-NAVApp -ServerInstance $ServerInstance -Tenant $Tenant -Name $app.Name -Version $app.Version -Force
                            }                   
                        }
                        $apps = Get-NAVAppInfo -ServerInstance $ServerInstance -Tenant $Tenant -TenantSpecificProperties | Where-Object -Property Name -EQ $CurrentApp.Name
                        foreach ($app in $apps | Sort-Object -Property Version) {
                            Write-Host "Checking installation status for app $($app.Name) $($app.Version)"
                            $NoOfNewerApps = @($apps | Where-Object -Property Version -GT $app.Version).Count
                            $IsInstalled = ($apps | Where-Object -Property Version -EQ $app.Version).IsInstalled
                            Write-Host "No. of newer apps: ${NoOfNewerApps}"
                            Write-Host "Installed: ${IsInstalled}"    
                            if ($NoOfNewerApps -gt 0 -and $IsInstalled -eq $false) {
                                Write-Host "Unpublishing old app $($app.Name) $($app.Version)"
                                try {
                                    Unpublish-NAVApp -ServerInstance $ServerInstance -Name $app.Name -Publisher $app.Publisher -Version $app.Version -Tenant $Tenant
                                }
                                catch {
                                    Write-Host "Unable to unpublish $($app.Name) v$($app.Version) : $($PSItem.Exception.Message)"
                                }
                            }
                        }         
                    }
                } -ArgumentList $Tenants, $tempAppFile, $deployment.DeployToInstance, $installNewApps, $SyncAppMode
            }
            catch [System.Management.Automation.Remoting.PSRemotingTransportException] {
                throw "Could not connect to $VM. Maybe port 5985 (WinRM) is not open for your IP address $myip"
            }
            finally {
                if ($vmSession) {
                    if ($tempAppFile) {
                        try { RemoveFileFromSession -session $vmSession -filename $tempAppFile } catch {}
                    }                    
                }
            }
        
        }        
    }
    if ($vmSession) {
        Remove-PSSession -Session $vmSession    
}

}

