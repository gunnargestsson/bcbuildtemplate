cd $PSScriptRoot

. ".\Initialize.ps1"

$containerName = "$($settings.name)-bld"

$buildenv = "Local"
$bccontainerhelperPath = $userProfile.bccontainerhelperPath

$buildArtifactFolder = Join-Path $ProjectRoot ".output"
if (Test-Path $buildArtifactFolder) { Remove-Item $buildArtifactFolder -Force -Recurse }
New-Item -Path $buildArtifactFolder -ItemType Directory -Force | Out-Null

$alPackagesFolder = Join-Path $ProjectRoot ".alPackages"
if (Test-Path $alPackagesFolder) { Remove-Item $alPackagesFolder -Force -Recurse }
New-Item -Path $alPackagesFolder -ItemType Directory -Force | Out-Null

. ".\Install-bccontainerhelper.ps1" `
    -buildenv $buildenv `
    -bccontainerhelperPath $bccontainerhelperPath

. ".\Create-Container.ps1" `
    -buildenv $buildenv `
    -ContainerName $containerName `
    -artifact $imageVersion.artifact `
    -imageName $imageVersion.imageName `
    -Credential $credential `
    -licenseFile $licenseFile

. ".\Publish-Dependencies.ps1" `
    -buildenv $buildenv `
    -ContainerName $containerName `
    -buildProjectFolder $ProjectRoot  `
    -skipVerification:$true

. ".\Compile-App.ps1" `
    -buildenv $buildenv `
    -ContainerName $containerName `
    -Credential $credential `
    -buildArtifactFolder $buildArtifactFolder `
    -buildProjectFolder $ProjectRoot `
    -buildSymbolsFolder $alPackagesFolder `
    -appFolders $settings.appFolders

. ".\Compile-App.ps1" `
    -buildenv $buildenv `
    -ContainerName $containerName `
    -Credential $credential `
    -buildArtifactFolder $buildArtifactFolder `
    -buildProjectFolder $ProjectRoot `
    -buildSymbolsFolder $alPackagesFolder `
    -appFolders $settings.testFolders

if ($CodeSignPfxFile) {
    . ".\Sign-App.ps1" `
        -buildenv $buildenv `
        -ContainerName $containerName `
        -buildArtifactFolder $buildArtifactFolder `
        -appFolders $settings.appFolders `
        -codeSignPfxFile $CodeSignPfxFile `
        -codeSignPfxPassword $CodeSignPfxPassword
}

. ".\Publish-App.ps1" `
    -buildenv $buildenv `
    -ContainerName $containerName `
    -buildArtifactFolder $buildArtifactFolder `
    -buildProjectFolder $ProjectRoot `
    -appFolders $settings.appFolders `
    -skipVerification:(!($CodeSignPfxFile))

. ".\Publish-App.ps1" `
    -buildenv $buildenv `
    -ContainerName $containerName `
    -buildArtifactFolder $buildArtifactFolder `
    -buildProjectFolder $ProjectRoot `
    -appFolders $settings.testFolders `
    -skipVerification

if ($testSecret) {
    . ".\Set-TestSecret.ps1" `
        -buildenv $buildenv `
        -ContainerName $containerName `
        -companyName $settings.testMethod.companyName `
        -codeunitId $settings.testMethod.codeunitId `
        -methodName $settings.testMethod.methodName `
        -argument $testSecret
}

. ".\Run-Tests.ps1" `
    -buildenv $buildenv `
    -ContainerName $containerName `
    -Credential $credential `
    -testResultsFile (Join-Path $buildArtifactFolder "TestResults.xml") `
    -buildProjectFolder $ProjectRoot `
    -appFolders $settings.testFolders

. ".\Remove-Container.ps1" `
    -buildenv $buildenv `
    -ContainerName $containerName
