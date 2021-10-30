Param(
    [Parameter(Mandatory = $true)]
    [string] $configurationFilePath,

    [Parameter(Mandatory = $true)]
    [string] $scriptToStart

)

$scriptPath = Split-Path -Path $configurationFilePath -Parent

# Get the ID and security principal of the current user account
$myWindowsID = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$myWindowsPrincipal = new-object System.Security.Principal.WindowsPrincipal($myWindowsID)
 
# Get the security principal for the Administrator role
$adminRole = [System.Security.Principal.WindowsBuiltInRole]::Administrator
 
# Check to see if we are currently running "as Administrator"
$IsInAdminMode = $myWindowsPrincipal.IsInRole($adminRole)

if (!$IsInAdminMode) {
    Write-Host "Starting Script in Admin Mode..."
    $ArgumentList = "-noprofile -file '${scriptToStart}' -configurationFilePath ${configurationFilePath}"
    Start-Process powershell -Verb runas -WorkingDirectory $scriptPath -ArgumentList $ArgumentList -WindowStyle Normal -Wait
}
else {        
    $BCContainerHelperInstallPath = Join-Path $env:TEMP 'Install-BCContainerHelper.ps1'
    if (-not (Test-Path -Path $BCContainerHelperInstallPath)) {
        Set-Content -Path $BCContainerHelperInstallPath -Value (Invoke-WebRequest -Uri "https://raw.githubusercontent.com/gunnargestsson/bcbuildtemplate/master/scripts/Install-BCContainerHelper.ps1").Content -Encoding UTF8        
    }
    . $BCContainerHelperInstallPath -buildEnv 'Local'
    $configurationFilePath = Join-Path $scriptPath 'build-settings.json'
    $settings = (Get-Content -Path $configurationFilePath -Encoding UTF8 | Out-String | ConvertFrom-Json)
    $userProfile = $settings.userProfiles | Where-Object -Property profile -EQ "$env:computername\$env:username"
    if (!$userProfile) { 
        $userProfile = New-Object -TypeName psobject
        $userProfile | Add-Member -MemberType NoteProperty -Name 'profile' -Value "$env:computername\$env:username"
        $credential = Get-Credential -Message 'New Container Credentials'
        if (-not $credential) { Throw 'Unable to create a container' }
        $userProfile | Add-Member -MemberType NoteProperty -Name 'Username' -Value $credential.UserName
        $userProfile | Add-Member -MemberType NoteProperty -Name "Password" -Value (ConvertFrom-SecureString $credential.Password)
        $licenseFilePath = Read-Host -Prompt "Enter License File Path" -AsSecureString
        $userProfile | Add-Member -MemberType NoteProperty -Name 'licenseFilePath' -Value (ConvertFrom-SecureString $licenseFilePath)
        $containerParameters = new-object -TypeName PSobject
        $containerParameters | Add-Member -MemberType NoteProperty -Name 'updateHosts' -Value $true
        $userProfile | Add-Member -MemberType NoteProperty -Name 'containerParameters' -Value $containerParameters
        $settings.userProfiles += $userProfile
        Set-Content -Path $configurationFilePath -Encoding UTF8 -Value ($settings | ConvertTo-Json)
    }
    $containername = $settings.name.ToLower()
    $auth = 'UserPassword'
    $artifact = $settings.versions[0].artifact
    $segments = "$artifact/////".Split('/')
    $artifactUrl = Get-BCArtifactUrl -storageAccount $segments[0] -type $segments[1] -version $segments[2] -country $segments[3] -select $segments[4] | Select-Object -First 1   
    $username = $userProfile.Username
    $password = ConvertTo-SecureString -String $userProfile.Password
    $credential = New-Object System.Management.Automation.PSCredential ($username, $password)
    $licenseFile = ([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($(ConvertTo-SecureString -String $userProfile.licenseFilePath))))

    $parameters = @{
        "Accept_Eula"     = $true
        "Accept_Outdated" = $true
        "shortcuts"       = "None"
    }

    
    if ($settings.containerParameters) {
        Foreach ($parameter in ($settings.containerParameters.PSObject.Properties | Where-Object -Property MemberType -eq NoteProperty)) {
            try { $value = (Invoke-Expression $parameter.Value) } catch { $value = $parameter.Value }
            if (!([String]::IsNullOrEmpty($value))) { $parameters += @{ $parameter.Name = $value } }
        }
    }


    if ($settings.dotnetAddIns) {
        $parameters += @{ 
            "myscripts" = @( "$configurationFilePath"
                @{ "SetupAddins.ps1" = (Invoke-WebRequest -Uri "https://raw.githubusercontent.com/gunnargestsson/bcbuildtemplate/master/scripts/Copy-AddIns.ps1").Content })
        }    
    }

    if ($userProfile.containerParameters) {
        Foreach ($parameter in ($userProfile.containerParameters.PSObject.Properties | Where-Object -Property MemberType -eq NoteProperty)) {
            try { $value = (Invoke-Expression $parameter.Value) } catch { $value = $parameter.Value }
            if (!([String]::IsNullOrEmpty($value))) { 
                try { $parameters += @{ $parameter.Name = $value } } catch { $parameters."$($parameter.Name)" = $value }
            }
        }
    }        

    New-BCContainer @parameters `
        -containerName $containername `
        -artifactUrl $artifactUrl `
        -Credential $credential `
        -auth $auth `
        -timeout 5000 `
        -licenseFile $licenseFile

    $settings.dependencies | ForEach-Object {
        Write-Host "Publishing $_"
        Publish-BCContainerApp -containerName $containerName -appFile $_ -skipVerification -sync -install
    }

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

    # Update Launch Json for all apps
    $apps = Get-ChildItem -Path (Split-Path -Path $scriptPath -Parent) -Filter "app.json" -Recurse
    foreach ($appFolder in $apps.DirectoryName) {
        $vscodeFolder = Join-Path $appFolder ".vscode"
        New-Item -Path $vscodeFolder -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
        $launchJsonFile = Join-Path $vscodeFolder "launch.json"
        if (Test-Path $launchJsonFile) {
            Write-Host "Modifying $launchJsonFile"
            $launchJson = Get-Content $LaunchJsonFile | ConvertFrom-Json
        }
        else {
            Write-Host "Creating $launchJsonFile"
            $dir = [System.IO.Path]::GetDirectoryName($launchJsonFile)
            if (!(Test-Path $dir)) {
                New-Item -Path $dir -ItemType Directory | Out-Null
            }
            $launchJson = @{ "version" = "0.2.0"; "configurations" = @() } | ConvertTo-Json | ConvertFrom-Json
        }

        $config = Get-BcContainerServerConfiguration -ContainerName $containerName
        if ($config.DeveloperServicesSSLEnabled -eq "true") {
            $devserverUrl = "https://$containerName"
        }
        else {
            $devserverUrl = "http://$containerName"
        }
        if ($config.ClientServicesCredentialType -eq "Windows") {
            $authentication = "Windows"
        }
        else {
            $authentication = "UserPassword"
        }

        $launchSettings = [ordered]@{
            "type"           = 'al'
            "request"        = 'launch'
            "name"           = $containerName
            "server"         = $devserverUrl
            "serverInstance" = $config.ServerInstance
            "port"           = [int]($config.DeveloperServicesPort)
            "tenant"         = 'default'
            "authentication" = $authentication
            "breakOnError"   = $true
            "launchBrowser"  = $true
        }      
        
        $launchSettings | ConvertTo-Json | Out-Host
        $oldSettings = $launchJson.configurations | Where-Object { $_.name -eq $launchsettings.name }
        if ($oldSettings) {
            $oldSettings.PSObject.Properties | % {
                $prop = $_.Name
                if (!($launchSettings.Keys | Where-Object { $_ -eq $prop } )) {
                    $launchSettings += @{ "$prop" = $oldSettings."$prop" }
                }
            }
        }
        $launchJson.configurations = @($launchJson.configurations | Where-Object { $_.name -ne $launchsettings.name })
        $launchJson.configurations += $launchSettings
        $launchJson | ConvertTo-Json -Depth 10 | Set-Content $launchJsonFile

    }
}