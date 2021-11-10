Param(
    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyname=$true)]
    [string] $configurationFilePath,

    [Parameter(Mandatory = $false, ValueFromPipelineByPropertyname=$true)]
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
    Start-Process powershell -Verb runas -WorkingDirectory $scriptPath -ArgumentList @($ArgumentList,$configurationFilePath,$scriptToStart) -WindowStyle Normal -Wait 
}
else {
    Invoke-Expression -Command "Function Install-BCContainerHelper { $((Invoke-WebRequest -Uri "https://raw.githubusercontent.com/gunnargestsson/bcbuildtemplate/master/scripts/Install-BCContainerHelper.ps1").Content.Substring(1)) }"
    Install-BCContainerHelper
    $settings = (Get-Content -Path $configurationFilePath -Encoding UTF8 | Out-String | ConvertFrom-Json)
    $containername = $settings.name.ToLower()
    Remove-BcContainer -containerName $containername
}