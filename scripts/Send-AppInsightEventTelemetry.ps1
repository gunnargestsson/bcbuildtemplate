# Copied from https://github.com/keithbabinec/AzurePowerShellUtilityFunctions/blob/master/Functions/Public/Send-AppInsightsEventTelemetry.ps1

[CmdletBinding()]
Param
(
    [Parameter(
        Mandatory=$true,
        HelpMessage='Specify the instrumentation key of your Azure Application Insights instance. This determines where the data ends up.')]
    [System.Guid]
    [ValidateScript({$_ -ne [System.Guid]::Empty})]
    $InstrumentationKey,

    [Parameter(
        Mandatory=$true,
        HelpMessage='Specify the name of your custom event.')]
    [System.String]
    [ValidateNotNullOrEmpty()]
    $EventName,

    [Parameter(Mandatory=$false)]
    [Hashtable]
    $CustomProperties
)
Process
{
    # app insights has a single endpoint where all incoming telemetry is processed.
    # documented here: https://github.com/microsoft/ApplicationInsights-Home/blob/master/EndpointSpecs/ENDPOINT-PROTOCOL.md
    
    $AppInsightsIngestionEndpoint = 'https://dc.services.visualstudio.com/v2/track'
    
    # prepare custom properties
    # convert the hashtable to a custom object, if properties were supplied.
    
    if ($PSBoundParameters.ContainsKey('CustomProperties') -and $CustomProperties.Count -gt 0)
    {
        $customPropertiesObj = [PSCustomObject]$CustomProperties;
    }
    else
    {
        $customPropertiesObj = [PSCustomObject]@{};
    }

    # prepare the REST request body schema.
    # NOTE: this schema represents how events are sent as of the app insights .net client library v2.9.1.
    # newer versions of the library may change the schema over time and this may require an update to match schemas found in newer libraries.
    
    $bodyObject = [PSCustomObject]@{
        'name' = "Microsoft.ApplicationInsights.$InstrumentationKey.Event"
        'time' = ([System.dateTime]::UtcNow.ToString('o'))
        'iKey' = $InstrumentationKey
        'tags' = [PSCustomObject]@{
            'ai.cloud.roleInstance' = $ENV:COMPUTERNAME
            'ai.internal.sdkVersion' = 'AzurePowerShellUtilityFunctions'
        }
        'data' = [PSCustomObject]@{
            'baseType' = 'EventData'
            'baseData' = [PSCustomObject]@{
                'ver' = '2'
                'name' = $EventName
                'properties' = $customPropertiesObj
            }
        }
    };

    # convert the body object into a json blob.
    $bodyAsCompressedJson = $bodyObject | ConvertTo-JSON -Depth 10 -Compress;

    # prepare the headers
    $headers = @{
        'Content-Type' = 'application/x-json-stream';
    };

    # send the request
    $NoOfItemsAccepted = (Invoke-RestMethod -Uri $AppInsightsIngestionEndpoint -Method Post -Headers $headers -Body $bodyAsCompressedJson).itemsAccepted;
    if ($NoOfItemsAccepted -ge 1) {
        Write-Host "Successfully sent to telemetry"
    }
}
