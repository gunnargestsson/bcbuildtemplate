Param(
    [ValidateSet('AzureDevOps','Local','AzureVM')]
    [Parameter(Mandatory=$false)]
    [string] $buildEnv = "AzureDevOps",

    [Parameter(Mandatory=$false)]
    [string] $containerName = $ENV:CONTAINERNAME,

    [Parameter(Mandatory=$false)]
    [string] $companyName = $ENV:TESTCOMPANYNAME,

    [Parameter(Mandatory=$false)]
    [string] $codeunitId = $ENV:TESTCODEUNITID,

    [Parameter(Mandatory=$false)]
    [string] $methodName = $ENV:TESTMETHODNAME,

    [Parameter(Mandatory=$false)]
    [securestring] $argument = $null
)

if (-not ($argument)) {
    $argument = try { $ENV:TESTSECRET | ConvertTo-SecureString } catch { ConvertTo-SecureString -String $ENV:TESTSECRET -AsPlainText -Force }
}

if ($argument) {
    $unsecureArgument = ([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($argument)))
}

if ($unsecureArgument) {
    $Companies = Invoke-ScriptInBcContainer -containerName $containerName -scriptblock { @(Get-NAVCompany -ServerInstance BC).CompanyName }
    if (!$Companies.Contains($companyName)) {
        Write-Host "Creating company ${companyName}"
        Invoke-ScriptInBcContainer -containerName $containerName -scriptblock { param($companyName)New-NAVCompany -ServerInstance BC -CompanyName $companyName} -argumentList $companyName
    }    

    Write-Host "Setting test secret"
    Invoke-NavContainerCodeunit -containerName $containerName -CompanyName $companyName -Codeunitid $codeunitId -MethodName $methodName -Argument $unsecureArgument
}
