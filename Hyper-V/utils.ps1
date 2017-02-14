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

function Invoke-FastWebRequest {
   Param(
        [Parameter(Mandatory=$True,ValueFromPipeline=$true,Position=0)]
        [System.Uri]$Uri,
        [Parameter(Position=1)]
        [string]$OutFile
    )
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
}