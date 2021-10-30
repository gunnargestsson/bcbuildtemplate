Param
(
    [Parameter(Mandatory = $true)]
    [string] $appFolders,
    [Parameter(Mandatory = $true)]
    [string] $BaseFolder,
    [Parameter(Mandatory = $true)]
    [int] $PageObjectId = 0
)

foreach ($appFolder in $appFolders) {
    $vscodeFolder = Join-Path $BaseFolder (Join-Path $appFolder ".vscode")
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
        "startupObjectType" = "Page"
        "startupObjectId"= $PageObjectId
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
