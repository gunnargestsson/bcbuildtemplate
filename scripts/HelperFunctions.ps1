Function Get-BlobFromPrivateAzureStorageOauth2 {
    param(
        [Parameter(ValueFromPipelineByPropertyName, Mandatory = $true)]
        [String]$blobUri
    )

    Write-Host "Getting new Auth Context"

    $context = New-BcAuthContext -tenantID $ENV:AZSTORAGETENANTID -clientID $ENV:AZSTORAGECLIENTID -clientSecret $ENV:AZSTORAGECLIENTSECRET -scopes "https://storage.azure.com/.default"
    
    if (!$context) {
        throw "Error retrieving Access token"
    } else {
        Write-Host "Access token retieved"
    }

    $date = Get-Date
    $formattedDateTime = $date.ToUniversalTime().ToString("R")

    $headers = @{ 
        "Authorization" = "Bearer $($context.accessToken)"
        "x-ms-version"  = "2017-11-09"
        "x-ms-date" = "$formattedDateTime"        
        "Content-Type" = "application/json"
    }

    $TempFile = New-TemporaryFile

    Download-File -sourceUrl $blobUri -destinationFile $TempFile -headers $headers

    return($TempFile)
}