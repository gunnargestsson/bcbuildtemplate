Param(
    [Parameter(Mandatory = $false)]
    [string] $customBaseAppUrl = '',

    [Parameter(Mandatory = $false)]
    [string] $containerName = $ENV:CONTAINERNAME
)

Write-Host "Publishing $customBaseAppUrl"
Publish-NavContainerApp -containerName $containerName -appFile $customBaseAppUrl -skipVerification -sync -upgrade