Param(
    [Parameter(Mandatory=$false)]
    [string] $bccontainerhelperPath = $env:bccontainerhelperPath,

    [Parameter(Mandatory=$false)]
    [string] $bccontainerhelperVersion = $env:bccontainerhelperVersion
)

if (-not $bccontainerhelperVersion) { $bccontainerhelperVersion = "latest" }

Write-Host "Version: $bccontainerhelperVersion"

if ($bccontainerhelperPath -ne "" -and (Test-Path $bccontainerhelperPath)) {

    Write-Host "Using bccontainerhelper from $bccontainerhelperPath"
    . $bccontainerhelperPath

}
else {

    $module = Get-InstalledModule -Name bccontainerhelper -ErrorAction SilentlyContinue
    if ($module) {
        $versionStr = $module.Version.ToString()
        Write-Host "bccontainerhelper $VersionStr is installed"
        if ($bccontainerhelperVersion -eq "latest") {
            Write-Host "Determine latest bccontainerhelper version"
            $latestVersion = (Find-Module -Name bccontainerhelper).Version
            $bccontainerhelperVersion = $latestVersion.ToString()
            Write-Host "bccontainerhelper $bccontainerhelperVersion is the latest version"
        }
        if ($bccontainerhelperVersion -ne $module.Version) {
            Write-Host "Updating bccontainerhelper to $bccontainerhelperVersion"
            Update-Module -Name bccontainerhelper -Force -RequiredVersion $bccontainerhelperVersion
            Write-Host "bccontainerhelper updated"
        }
    }
    else {
        if (!(Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
            Write-Host "Installing NuGet Package Provider"
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.208 -Force -WarningAction SilentlyContinue | Out-Null
        }
        if ($bccontainerhelperVersion -eq "latest") {
            Write-Host "Installing bccontainerhelper"
            Install-Module -Name bccontainerhelper -Force
        }
        else {
            Write-Host "Installing bccontainerhelper version $bccontainerhelperVersion"
            Install-Module -Name bccontainerhelper -Force -RequiredVersion $bccontainerhelperVersion
        }
        $module = Get-InstalledModule -Name bccontainerhelper -ErrorAction SilentlyContinue
        $versionStr = $module.Version.ToString()
        Write-Host "bccontainerhelper $VersionStr installed"
    }
}
