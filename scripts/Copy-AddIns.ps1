Add-Type -AssemblyName System.Net.Http

$serviceTierFolder = (Get-Item "C:\Program Files\Microsoft Dynamics NAV\*\Service").FullName
$serviceTierAddInsFolder = Join-Path $serviceTierFolder "Add-ins"
$settings = (Get-Content ((Get-ChildItem -Path 'C:\Build' -Filter "build-settings.json" -Recurse).FullName) -Encoding UTF8 | Out-String | ConvertFrom-Json)

Write-Host "Copying Add-ins to the service tier add-ins folder"

$settings.dotnetAddIns | ForEach-Object {
    $appFile = $_
    if ($appFile.ToLower().StartsWith("http://") -or $appFile.ToLower().StartsWith("https://")) {
        $appUrl = $appFile
        $name = [System.Uri]::UnescapeDataString([System.IO.Path]::GetFileName($appUrl).split("?")[0])
        $appFile = Join-Path $serviceTierAddInsFolder $name
        Download-File -sourceUrl $appUrl -destinationFile $appFile
    }
}

