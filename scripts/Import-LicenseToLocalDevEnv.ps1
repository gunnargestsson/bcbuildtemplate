Param(
    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyname = $true)]
    [string] $configurationFilePath,

    [Parameter(Mandatory = $false, ValueFromPipelineByPropertyname = $true)]
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
    $ArgumentList = "-noprofile -file ${scriptToStart}"
    Write-Host "Starting '${scriptToStart}' in Admin Mode..."
    Start-Process powershell -Verb runas -WorkingDirectory $scriptPath -ArgumentList @($ArgumentList, $configurationFilePath, $scriptToStart) -WindowStyle Normal -Wait 
}
else {
    Invoke-Expression -Command "Function Install-BCContainerHelper { $((Invoke-WebRequest -Uri "https://raw.githubusercontent.com/gunnargestsson/bcbuildtemplate/master/scripts/Install-BCContainerHelper.ps1").Content.Substring(1)) }"
    Install-BCContainerHelper
    $settings = (Get-Content -Path $configurationFilePath -Encoding UTF8 | Out-String | ConvertFrom-Json)
    $userProfile = $settings.userProfiles | Where-Object -Property profile -EQ "$env:computername\$env:username"
    if (!$userProfile) { 
        $credential = Get-Credential -Message 'New Container Credentials'
        if (-not $credential) { Throw 'Unable to create a container' }
        $licenseFilePath = Read-Host -Prompt "Enter License File Path" -AsSecureString
        $userProfile = New-Object -TypeName psobject
        $userProfile | Add-Member -NotePropertyName 'profile' -NotePropertyValue "$env:computername\$env:username"
        $userProfile | Add-Member -NotePropertyName 'Username' -NotePropertyValue $credential.UserName
        $userProfile | Add-Member -NotePropertyName "Password" -NotePropertyValue (ConvertFrom-SecureString $credential.Password)       
        $userProfile | Add-Member -NotePropertyName 'licenseFilePath' -NotePropertyValue (ConvertFrom-SecureString $licenseFilePath)
        $containerParameters = new-object -TypeName PSobject
        $containerParameters | Add-Member -NotePropertyName 'updateHosts' -NotePropertyValue $true
        $userProfile | Add-Member -MemberType NoteProperty -Name 'containerParameters' -Value $containerParameters       
        $settings.userProfiles += $userProfile
        Set-Content -Path $configurationFilePath -Encoding UTF8 -Value ($settings | ConvertTo-Json -Depth 10)
    }
    $containername = $settings.name.ToLower()
    $licenseFile = ([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($(ConvertTo-SecureString -String $userProfile.licenseFilePath))))
    Import-NavContainerLicense -containerName $containername -licenseFile $licenseFile
}