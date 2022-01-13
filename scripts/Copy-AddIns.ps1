Add-Type -AssemblyName System.Net.Http

$serviceTierFolder = (Get-Item "C:\Program Files\Microsoft Dynamics NAV\*\Service").FullName
$serviceTierAddInsFolder = Join-Path $serviceTierFolder "Add-ins"
$settings = (Get-Content ((Get-ChildItem -Path 'C:\Run\My' -Filter "build-settings.json" -Recurse).FullName) -Encoding UTF8 | Out-String | ConvertFrom-Json)

if ($settings.dotnetAddIns) {
    Write-Host "Copying Add-ins to the service tier add-ins folder"

    $settings.dotnetAddIns | ForEach-Object {
        $addinFile = $_
        if ($addinFile.ToLower().StartsWith("http://") -or $addinFile.ToLower().StartsWith("https://")) {
            $addinUrl = $addinFile
            $name = [System.Uri]::UnescapeDataString([System.IO.Path]::GetFileName($addinUrl).split("?")[0])
            $addinFile = Join-Path $serviceTierAddInsFolder $name
            Download-File -sourceUrl $addinUrl -destinationFile $addinFile
            if ($addinFile.EndsWith(".zip", "OrdinalIgnoreCase")) {
                Write-Host "Extracting .zip file "
                Expand-Archive -Path $addinFile -DestinationPath $serviceTierAddInsFolder
                Remove-Item -Path $addinFile -Force
            }        
        }
    }
}

