function InvokeScriptInSession {
    Param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Runspaces.PSSession] $session,
        [Parameter(Mandatory = $true)]
        [string] $filename,
        [Parameter(Mandatory = $false)]
        [object[]] $argumentList
    )

    Invoke-Command -Session $session -ScriptBlock ([ScriptBlock]::Create([System.IO.File]::ReadAllText($filename))) -ArgumentList $argumentList
}

function CopyFileToSession {
    Param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Runspaces.PSSession] $session,
        $localfile,
        [switch] $returnSecureString
    )

    if ($localfile) {
        if ($localFile -is [securestring]) {
            $localFile = ([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($localFile)))
        }
        if ($localfile -notlike "https://*" -and $localfile -notlike "http://*") {
            $tempFilename = Join-Path (GetTempPathFromSession -session $session) "$([Guid]::NewGuid().ToString())"
            Copy-Item -ToSession $session -Path $localFile -Destination $tempFilename
            $localfile = $tempFilename
        }
        if ($returnSecureString) {
            ConvertTo-SecureString -String $localfile -AsPlainText -Force
        }
        else {
            $localfile
        }
    }
    else {
        if ($returnSecureString) {
            $null
        }
        else {
            ""
        }
    }
}

function GetTempPathFromSession {
    Param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Runspaces.PSSession] $session
    )

    Invoke-Command -Session $session -ScriptBlock {
        $env:TEMP
    }
}


function RemoveFileFromSession {
    Param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Runspaces.PSSession] $session,
        $filename
    )
    
    if ($filename) {
        if ($filename -is [securestring]) {
            $filename = ([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($filename)))
        }
        if ($filename -notlike "https://*" -and $filename -notlike "http://*") {
            Invoke-Command -Session $session -ScriptBlock { Param($filename)
                Remove-Item $filename -Force
            } -ArgumentList $filename
        }
    }
}

function CopyFoldersToSession {
    Param(
        [Parameter(Mandatory = $false)]
        [System.Management.Automation.Runspaces.PSSession] $session,
        [Parameter(Mandatory = $true)]
        [string] $baseFolder,
        [Parameter(Mandatory = $true)]
        [string[]] $subFolders,
        [Parameter(Mandatory = $false)]
        [string[]] $exclude = @("*.app")
    )

    $tempFolder = Join-Path $env:TEMP ([Guid]::NewGuid().ToString())
    $subFolders | ForEach-Object {
        Copy-Item -Path (Join-Path $baseFolder $_) -Destination (Join-Path $tempFolder "$_\") -Recurse -Exclude $exclude
    }

    $file = Join-Path $env:TEMP ([Guid]::NewGuid().ToString())
    Add-Type -Assembly System.IO.Compression
    Add-Type -Assembly System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($tempfolder, $file)
    $sessionFile = CopyFileToSession -session $session -localfile $file
    Remove-Item $file -Force

    Invoke-Command -Session $session -ScriptBlock { Param($filename)
        Add-Type -Assembly System.IO.Compression
        Add-Type -Assembly System.IO.Compression.FileSystem
        $tempFoldername = "c:\artifacts\$([Guid]::NewGuid().ToString())"
        [System.IO.Compression.ZipFile]::ExtractToDirectory($filename, $tempfoldername)
        Remove-Item $filename -Force
        $tempfoldername
    } -ArgumentList $sessionFile
}

function RemoveFolderFromSession {
    Param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Runspaces.PSSession] $session,
        [Parameter(Mandatory = $true)]
        [string] $foldername
    )
    
    Invoke-Command -Session $session -ScriptBlock { Param($foldername)
        Remove-Item $foldername -Force -Recurse
    } -ArgumentList $foldername
}

Function New-DeploymentRemoteSession {
    param(
        [Parameter(Mandatory = $True, ValueFromPipelineByPropertyname = $true)]
        [String]$HostName,
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyname = $true)]
        [System.Management.Automation.PSCredential]$Credential
    )

    if ($Credential) {
        try {
            $sessionOption = New-PSSessionOption -SkipCACheck -SkipCNCheck 
            $vmSession = New-PSSession -ComputerName $HostName -Credential $Credential -SessionOption $sessionOption -UseSSL
            return $vmSession
        }
        catch {}
        try {
            $sessionOption = New-PSSessionOption -SkipCACheck -SkipCNCheck -IncludePortInSPN
            $vmSession = New-PSSession -ComputerName $HostName -Credential $Credential -SessionOption $sessionOption -UseSSL
            return $vmSession
        }
        catch {}
        try {
            $sessionOption = New-PSSessionOption -SkipCACheck -SkipCNCheck
            $vmSession = New-PSSession -ComputerName $HostName -Credential $Credential -SessionOption $sessionOption
            return $vmSession
        }
        catch {}
        try {
            $sessionOption = New-PSSessionOption -SkipCACheck -SkipCNCheck -IncludePortInSPN
            $vmSession = New-PSSession -ComputerName $HostName -Credential $Credential -SessionOption $sessionOption
            return $vmSession
        }
        catch {}
        try {
            if ((Test-NetConnection -ComputerName $HostName -Port 5986).TcpTestSucceeded) {
                $WinRmUri = New-Object Uri("https://$($HostName):5986")
                $WinRmOption = New-PSSessionOption –SkipCACheck –SkipCNCheck –SkipRevocationCheck
                $vmSession = New-PSSession -ConnectionUri $WinRMUri -Credential $Credential -SessionOption $WinRmOption 
                return $vmSession
            }
        }
        catch {}        
        try {
            if ((Test-NetConnection -ComputerName $HostName -Port 5985).TcpTestSucceeded) {
                $WinRmUri = New-Object Uri("http://$($HostName):5985")
                $WinRmOption = New-PSSessionOption –SkipCACheck –SkipCNCheck –SkipRevocationCheck
                $vmSession = New-PSSession -ConnectionUri $WinRMUri -Credential $Credential -SessionOption $WinRmOption 
                return $vmSession
            }
        }
        catch {}
    }    
    try {
        $sessionOption = New-PSSessionOption -SkipCACheck -SkipCNCheck -IncludePortInSPN
        $vmSession = New-PSSession -ComputerName $VM -SessionOption $sessionOption
        return $vmSession
    }
    catch {}
    try {
        $sessionOption = New-PSSessionOption -SkipCACheck -SkipCNCheck
        $vmSession = New-PSSession -ComputerName $VM -SessionOption $sessionOption
        return $vmSession        
    }    
    catch {}
    try {
        $sessionOption = New-PSSessionOption -SkipCACheck -SkipCNCheck -IncludePortInSPN
        $vmSession = New-PSSession -ComputerName $VM -SessionOption $sessionOption -UseSSL
        return $vmSession
    }
    catch {}
    try {
        $sessionOption = New-PSSessionOption -SkipCACheck -SkipCNCheck
        $vmSession = New-PSSession -ComputerName $VM -SessionOption $sessionOption -UseSSL
        return $vmSession        
    }   
    catch {}    
    try {
        if ((Test-NetConnection -ComputerName $HostName -Port 5986).TcpTestSucceeded) {
            $WinRmUri = New-Object Uri("https://$($HostName):5986")
            $WinRmOption = New-PSSessionOption –SkipCACheck –SkipCNCheck –SkipRevocationCheck
            $vmSession = New-PSSession -ConnectionUri $WinRMUri -SessionOption $WinRmOption 
            return $vmSession
        }
    }
    catch {}
    try {
        if ((Test-NetConnection -ComputerName $HostName -Port 5985).TcpTestSucceeded) {
            $WinRmUri = New-Object Uri("http://$($HostName):5985")
            $WinRmOption = New-PSSessionOption –SkipCACheck –SkipCNCheck –SkipRevocationCheck
            $vmSession = New-PSSession -ConnectionUri $WinRMUri -SessionOption $WinRmOption 
            return $vmSession
        }
    }
    catch {}
    Write-Host "Unable to create a PS Remote Session to host: ${HostName} !"
    throw
}