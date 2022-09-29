Param(
    [Parameter(Mandatory = $true)]
    [string] $configurationFilePath,

    [ValidateSet('AzureDevOps', 'Local', 'AzureVM')]
    [Parameter(Mandatory = $false)]
    [string] $buildEnv = "AzureDevOps",

    [Parameter(Mandatory = $false)]
    [string] $containerName = $ENV:CONTAINERNAME,

    [Parameter(Mandatory = $false)]
    [string] $testSuite = "DEFAULT",

    [Parameter(Mandatory = $false)]
    [string] $buildProjectFolder = $ENV:BUILD_REPOSITORY_LOCALPATH,

    [Parameter(Mandatory = $false)]
    [string] $appFolders = "",

    [Parameter(Mandatory = $false)]
    [pscredential] $credential = $null,

    [Parameter(Mandatory = $false)]
    [string] $testResultsFile = (Join-Path $ENV:BUILD_REPOSITORY_LOCALPATH "TestResults.xml"),

    [switch] $reRunFailedTests
)

Start-Sleep -seconds 30

$settings = (Get-Content -Path $configurationFilePath -Encoding UTF8 | Out-String | ConvertFrom-Json)
$testCompanyName = $settings.testCompanyName
$testSuiteDisabled = $settings.testSuiteDisabled

if ([String]::IsNullOrEmpty($testCompanyName)) {
    $testCompanyName = Invoke-ScriptInBcContainer -containerName $containerName -scriptblock {
        $ServerInstance = (Get-NAVServerInstance | Where-Object -Property Default -EQ True).ServerInstance
        @(Get-NAVCompany -ServerInstance $ServerInstance -Tenant default).CompanyName
    } | Select-Object -First 1
}

Write-Host "Executing tests on company '${testCompanyName}' and saving results in '${testResultsFile}'"

if (-not ($credential)) {
    $securePassword = try { $ENV:PASSWORD | ConvertTo-SecureString } catch { ConvertTo-SecureString -String $ENV:PASSWORD -AsPlainText -Force }
    $credential = New-Object PSCredential -ArgumentList $ENV:USERNAME, $SecurePassword
}

$TempTestResultFile = "C:\ProgramData\bccontainerhelper\Extensions\$containerName\Test Results.xml"
$globalDisabledTests = @()
$disabledTestsFile = Join-Path $buildProjectFolder "disabledTests.json"
if (Test-Path $disabledTestsFile) {
    $globalDisabledTests = Get-Content $disabledTestsFile | ConvertTo-Json
}

$rerunTests = @()
$failedTests = @()
$first = $true

$azureDevOpsParam = @{}
if ($buildEnv -eq "AzureDevOps") {
    $azureDevOpsParam = @{ "AzureDevOps" = "Warning" }
}

$NavVersion = Get-BcContainerNavVersion -containerOrImageName $containerName
Write-Host "Running tests for container version ${NavVersion}"
if ($NavVersion -ge "15.0.0.0") {
    Sort-AppFoldersByDependencies -appFolders $appFolders.Split(',') -baseFolder $buildProjectFolder -WarningAction SilentlyContinue | ForEach-Object {

        $appFolder = $_
        $disabledTests = $globalDisabledTests
        $getTestsParam = @{}
        if ($appFolder) {
            $appProjectFolder = Join-Path $buildProjectFolder $appFolder
            $appJson = Get-Content -Path (Join-Path $appProjectFolder "app.json") | ConvertFrom-Json
            $getTestsParam += @{ "ExtensionId" = "$($appJson.Id)" }
            $disabledTestsFile = Join-Path $appProjectFolder "disabledTests.json"
            if (Test-Path $disabledTestsFile) {
                $disabledTests += Get-Content $disabledTestsFile | ConvertFrom-Json
            }
        
            if ($testSuiteDisabled) {
                Run-TestsInBcContainer @AzureDevOpsParam `
                    -extensionId $appJson.Id `
                    -containerName $containerName `
                    -companyName $testCompanyName `
                    -credential $credential `
                    -XUnitResultFileName $TempTestResultFile `
                    -detailed
            }
            else {
        
                if ($disabledTests) {
                    $getTestsParam += @{ "DisabledTests" = $disabledTests }
                }

                $tests = Get-TestsFromBCContainer @getTestsParam `
                    -containerName $containerName `
                    -credential $credential `
                    -ignoreGroups `
                    -testSuite $testSuite -debugMode
        
                $tests | ForEach-Object {
                    if (-not (Run-TestsInBcContainer @AzureDevOpsParam `
                                -containerName $containerName `
                                -companyName $testCompanyName `
                                -credential $credential `
                                -XUnitResultFileName $TempTestResultFile `
                                -AppendToXUnitResultFile:(!$first) `
                                -testSuite $testSuite `
                                -testCodeunit $_.Id `
                                -returnTrueIfAllPassed `
                                -restartContainerAndRetry)) { $rerunTests += $_ }
                    $first = $false
                }
                if ($rerunTests.Count -gt 0 -and $reRunFailedTests) {
                    Restart-BCContainer -containerName $containername
                    $rerunTests | % {
                        if (-not (Run-TestsInBcContainer @AzureDevOpsParam `
                                    -containerName $containerName `
                                    -companyName $testCompanyName `
                                    -credential $credential `
                                    -XUnitResultFileName $TempTestResultFile `
                                    -AppendToXUnitResultFile:(!$first) `
                                    -testSuite $testSuite `
                                    -testCodeunit $_.Id `
                                    -returnTrueIfAllPassed `
                                    -restartContainerAndRetry)) { $failedTests += $_ }
                        $first = $false
                    }
                }
            }
        }
    }
}
else {
    Run-TestsInBcContainer @AzureDevOpsParam `
        -containerName $containerName `
        -companyName $testCompanyName `
        -credential $credential `
        -XUnitResultFileName $TempTestResultFile 
}

Copy-Item -Path $TempTestResultFile -Destination $testResultsFile -Force
