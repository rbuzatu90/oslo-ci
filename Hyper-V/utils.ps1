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

function GitClonePull($path, $url, $branch="master")
{
    Write-Output "Calling GitClonePull with path=$path, url=$url, branch=$branch"
    if (!(Test-Path -path $path))
    {
        ExecRetry {
            git clone $url $path
            if ($LastExitCode) { throw "git clone failed - GitClonePull - Path does not exist!" }
        }
        pushd $path
        git checkout $branch
        git pull
        popd
        if ($LastExitCode) { throw "git checkout failed - GitCLonePull - Path does not exist!" }
    }else{
        pushd $path
        try
        {
            ExecRetry {
                Remove-Item -Force -Recurse -ErrorAction SilentlyContinue "$path\*"
                git clone $url $path
                if ($LastExitCode) { throw "git clone failed - GitClonePull - After removing existing Path.." }
            }
            ExecRetry {
                (git checkout $branch) -Or (git checkout master)
                if ($LastExitCode) { throw "git checkout failed - GitClonePull - After removing existing Path.." }
            }

            Get-ChildItem . -Include *.pyc -Recurse | foreach ($_) {Remove-Item $_.fullname}

            git reset --hard
            if ($LastExitCode) { throw "git reset failed!" }

            git clean -f -d
            if ($LastExitCode) { throw "git clean failed!" }

            ExecRetry {
                git pull
                if ($LastExitCode) { throw "git pull failed!" }
            }
        }
        finally
        {
            popd
        }
    }
}

function log_message($message){
    Write-Output "[$(Get-Date)] $message"
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