$settings = (Get-Content ((Get-ChildItem -Path 'C:\Run\My' -Filter "build-settings.json" -Recurse).FullName) -Encoding UTF8 | Out-String | ConvertFrom-Json)

if ($settings.serverConfiguration) {
    Write-Host "Updating the service instance configuration"

    $ServerInstance = (Get-NAVServerInstance | Where-Object -Property Default -EQ True).ServerInstance
    Foreach ($parameter in ($settings.containerParameters.PSObject.Properties | Where-Object -Property MemberType -eq NoteProperty)) {
        try { $value = (Invoke-Expression $parameter.Value) } catch { $value = $parameter.Value }
        if (!([String]::IsNullOrEmpty($value))) { Set-NAVServerInstance -ServerInstance $ServerInstance -KeyName $parameter.Name -KeyValue -Verbose}
    }
}
