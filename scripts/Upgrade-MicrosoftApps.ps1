Param(
    [Parameter(Mandatory = $false)]
    [string] $containerName = $ENV:CONTAINERNAME,

    [Parameter(Mandatory = $false)]
    [string] $buildProjectFolder = $ENV:BUILD_REPOSITORY_LOCALPATH,

    [Parameter(Mandatory = $true)]
    [string] $branchName

)

Write-Host "Deploying branch ${branchName}..."
$settings = (Get-Content ((Get-ChildItem -Path $buildProjectFolder -Filter "build-settings.json" -Recurse).FullName) -Encoding UTF8 | Out-String | ConvertFrom-Json)
$deployment = $settings.deployments | Where-Object { $_.branch -eq $branchName }
Write-Host "Deployment type: $($deployment.DeploymentType)"
Write-Host "Upgrade Microsoft Apps: $($deployment.upgradeMicrosoftApps)"
if ($deployment -and $deployment.DeploymentType -eq "container" -and $deployment.upgradeMicrosoftApps -eq $true) {
    $DeployTocontainerName = $deployment.DeployToName
    Write-Host "Microsoft Apps upgrade for container ${DeployTocontainerName}"

    $appsInBuildContainer = Invoke-ScriptInBCContainer -containerName $containerName -scriptblock {
        $appsInContainer = Get-ChildItem -Path 'C:\Applications' -Filter *.app -Recurse
        $appInfoInContainer = @()
        foreach ($appInContainer in $appsInContainer) {
            $appInfo = Get-NAVAppInfo -Path $appInContainer.FullName
            $appInfo | Add-Member -MemberType NoteProperty -Name FullName -Value $appInContainer.FullName
            $appInfoInContainer += $appInfo
        }
        $appInfoInContainer
    }

    Write-Host "Found $($appsInBuildContainer.Count) apps in the build container"

    $appFolder = Join-Path $buildProjectFolder 'Temp'
    if (-not (Test-Path -Path $appFolder -PathType Container)) {
        New-Item -Path $appFolder -ItemType Directory -Force | Out-Null
    }

    Get-BCContainerAppInfo -containerName $DeployTocontainerName -sort DependenciesFirst | ForEach-Object {
        $app = $appsInBuildContainer | Where-Object -Property "Name" -EQ  $_.name | Where-Object -Property "Version" -GT $_.version
        if ($app) {
            Write-Host "Updating $($_.name) from version $($_.version) to $($app.version)"
            $appPath = Join-Path $appFolder $app.Name
            Copy-FileFromBCContainer -containerName $containerName -containerPath $app.FullName -localPath $appPath
            foreach ($tenant in (Get-BcContainerTenants -containerName $DeployTocontainerName)) {
                Publish-BCContainerApp -containerName $DeployTocontainerName -appFile $appPath -skipVerification -sync -scope Global -tenant $tenant.Id
                if (Get-BCContainerAppInfo -containerName $DeployTocontainerName -tenantSpecificProperties -tenant $tenant.Id | Where-Object -Property IsInstalled -EQ "True" | Where-Object -Property Name -EQ $_.name) {
                    Start-BCContainerAppDataUpgrade -containerName $DeployTocontainerName -appName $app.name -appVersion $app.version -tenant $tenant.Id -ErrorAction Continue
                    Install-BCContainerApp -containerName $DeployTocontainerName -appName $app.name -appVersion $app.version -tenant $tenant.Id
                }
            }
            UnPublish-BCContainerApp -containerName $DeployTocontainerName -appName $_.name -publisher $_.publisher -version $_.Version -force 
        }
        else {
            Write-Host "Latest version of $($_.name) found $($_.version)"
        }   
    }
}
