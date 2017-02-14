function ExecRetry($command, $maxRetryCount = 10, $retryInterval=2)
{
    $currErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    $retryCount = 0
    while ($true)
    {
        try 
        {
            & $command
            break
        }
        catch [System.Exception]
        {
            $retryCount++
            if ($retryCount -ge $maxRetryCount)
            {
                $ErrorActionPreference = $currErrorActionPreference
                throw
            }
            else
            {
                Write-Error $_.Exception
                Start-Sleep $retryInterval
            }
        }
    }

    $ErrorActionPreference = $currErrorActionPreference
}

function dumpeventlog($path){

    foreach ($i in (get-winevent -ListLog * |  ? {$_.RecordCount -gt 0 })) {
        $logName = "eventlog_" + $i.LogName + ".evtx"
        $logName = $logName.replace(" ","-").replace("/", "-").replace("\", "-")
        Write-Host "exporting "$i.LogName" as "$logName
        $bkup = Join-Path $path $logName
        wevtutil epl $i.LogName $bkup
    }
}

function exporthtmleventlog($path){
    $css = Get-Content $eventlogcsspath -Raw
    $js = Get-Content $eventlogjspath -Raw
    $HTMLHeader = @"
<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
<script type="text/javascript">$js</script>
<style type="text/css">$css</style>
"@

    foreach ($i in (get-winevent -ListLog * |  ? {$_.RecordCount -gt 0 })) {
        $Report = (get-winevent -LogName $i.LogName)
        $logName = "eventlog_" + $i.LogName + ".html"
        $logName = $logName.replace(" ","-").replace("/", "-").replace("\", "-")
        Write-Host "exporting "$i.LogName" as "$logName
        $Report = $Report | ConvertTo-Html -Title "${i}" -Head $HTMLHeader -As Table
        $Report = $Report | ForEach-Object {$_ -replace "<body>", '<body id="body">'}
        $Report = $Report | ForEach-Object {$_ -replace "<table>", '<table class="sortable" id="table" cellspacing="0">'}
        $bkup = Join-Path $path $logName
        $Report = $Report | Set-Content $bkup
    }
}

function cleareventlog(){
    foreach ($i in (get-winevent -ListLog * |  ? {$_.RecordCount -gt 0 })) {
        wevtutil cl $i.LogName
    }
}

function log_message($message){
    Write-Host "[$(Get-Date)] $message"
}

function Test-FileIntegrity {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=0)]
        [string]$File,
        [Parameter(Mandatory=$true)]
        [string]$ExpectedHash,
        [Parameter(Mandatory=$false)]
        [ValidateSet("SHA1", "SHA256", "SHA384", "SHA512", "MACTripleDES", "MD5", "RIPEMD160")]
        [string]$Algorithm="SHA1"
    )
    PROCESS {
        $hash = (Get-FileHash -Path $File -Algorithm $Algorithm).Hash
        if ($hash -ne $ExpectedHash) {
            throw ("File integrity check failed for {0}. Expected {1}, got {2}" -f @($File, $ExpectedHash, $hash))
        }
        return $true
    }
}

function Invoke-FastWebRequest {
    <#
    .SYNOPSIS
    Invoke-FastWebRequest downloads a file from the web via HTTP. This function will work on all modern windows versions,
    including Windows Server Nano. This function also allows file integrity checks using common hashing algorithms:

    "SHA1", "SHA256", "SHA384", "SHA512", "MACTripleDES", "MD5", "RIPEMD160"

    The hash of the file being downloaded should be specified in the Uri itself. See examples.
    .PARAMETER Uri
    The address from where to fetch the file
    .PARAMETER OutFile
    Destination file
    .PARAMETER SkipIntegrityCheck
    Skip file integrity check even if a valid hash is specified in the Uri.

    .EXAMPLE

    # Download file without file integrity check
    Invoke-FastWebRequest -Uri http://example.com/archive.zip -OutFile (Join-Path $env:TMP archive.zip)

    .EXAMPLE
    # Download file with file integrity check
    Invoke-FastWebRequest -Uri http://example.com/archive.zip#md5=43d89a2f6b8a8918ce3eb76227685276 `
                          -OutFile (Join-Path $env:TMP archive.zip)

    .EXAMPLE
    # Force skip file integrity check
    Invoke-FastWebRequest -Uri http://example.com/archive.zip#md5=43d89a2f6b8a8918ce3eb76227685276 `
                          -OutFile (Join-Path $env:TMP archive.zip) -SkipIntegrityCheck:$true
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$True,ValueFromPipeline=$true,Position=0)]
        [System.Uri]$Uri,
        [Parameter(Position=1)]
        [string]$OutFile,
        [switch]$SkipIntegrityCheck=$false
    )
    PROCESS
    {
        if(!([System.Management.Automation.PSTypeName]'System.Net.Http.HttpClient').Type)
        {
            $assembly = [System.Reflection.Assembly]::LoadWithPartialName("System.Net.Http")
        }

        if(!$OutFile) {
            $OutFile = $Uri.PathAndQuery.Substring($Uri.PathAndQuery.LastIndexOf("/") + 1)
            if(!$OutFile) {
                throw "The ""OutFile"" parameter needs to be specified"
            }
        }

        $fragment = $Uri.Fragment.Trim('#')
        if ($fragment) {
            $details = $fragment.Split("=")
            $algorithm = $details[0]
            $hash = $details[1]
        }

        if (!$SkipIntegrityCheck -and $fragment -and (Test-Path $OutFile)) {
            try {
                return (Test-FileIntegrity -File $OutFile -Algorithm $algorithm -ExpectedHash $hash)
            } catch {
                Remove-Item $OutFile
            }
        }

        $client = new-object System.Net.Http.HttpClient
        $task = $client.GetStreamAsync($Uri)
        $response = $task.Result
        if($task.IsFaulted) {
            $msg = "Request for URL '{0}' is faulted.`nTask status: {1}.`n" -f @($Uri, $task.Status)
            if($task.Exception) {
                $msg += "Exception details: {0}" -f @($task.Exception)
            }
            Throw $msg
        }
        $outStream = New-Object IO.FileStream $OutFile, Create, Write, None

        try {
            $totRead = 0
            $buffer = New-Object Byte[] 1MB
            while (($read = $response.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $totRead += $read
                $outStream.Write($buffer, 0, $read);
            }
        }
        finally {
            $outStream.Close()
        }
        if(!$SkipIntegrityCheck -and $fragment) {
            Test-FileIntegrity -File $OutFile -Algorithm $algorithm -ExpectedHash $hash
        }
    }
}