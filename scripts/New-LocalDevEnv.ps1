Param(
    [Parameter(Mandatory = $true)]
    [string] $configurationFilePath,

    [Parameter(Mandatory = $false)]
    [string] $scriptToStart = (Join-path $PSScriptRoot $MyInvocation.MyCommand.Name)

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
    Write-Host "Starting '${scriptToStart}' in Admin Mode..."
    $ArgumentList = "-noprofile -file '${scriptToStart}' -configurationFilePath ${configurationFilePath}"
    Start-Process powershell -Verb runas -WorkingDirectory $scriptPath -ArgumentList $ArgumentList -WindowStyle Normal -Wait
}
else {
    Invoke-Expression -Command "Function Install-BCContainerHelper { $((Invoke-WebRequest -Uri "https://raw.githubusercontent.com/gunnargestsson/bcbuildtemplate/master/scripts/Install-BCContainerHelper.ps1").Content) }"
    Install-BCContainerHelper
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

    Invoke-Expression -Command "Function Update-LaunchJson { $((Invoke-WebRequest -Uri "https://raw.githubusercontent.com/gunnargestsson/bcbuildtemplate/master/scripts/Update-LaunchJson.ps1").Content) }"
    Update-LaunchJson -appFolders $settings.appFolders -BaseFolder (Split-Path -Path $configurationFilePath -Parent) 
    Update-LaunchJson -appFolders $settings.testFolders -BaseFolder (Split-Path -Path $configurationFilePath -Parent) -PageObjectId 130451

}