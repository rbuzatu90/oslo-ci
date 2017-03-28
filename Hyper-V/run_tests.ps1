Param(
    [string]$buildFor=''
)

$ErrorActionPreference = "Stop"

$projectName = $buildFor.split('/')[-1]

$scriptLocation = [System.IO.Path]::GetDirectoryName($myInvocation.MyCommand.Definition)
. "$scriptLocation\config.ps1"
. "$scriptLocation\utils.ps1"

$currDate = (Get-Date).ToString()
Write-Output "$currDate Started running tests"

Try {
   $proc = Start-Job -Name "UnitTests" -Init ([ScriptBlock]::Create("Set-Location $buildDir\$projectName")) -ScriptBlock { pwd; stestr init; Write-Output "Exit code: $LASTEXITCODE" }
} Catch {
    Throw "Could not start the unit tests job."
}

Try {
   $proc = Start-Job -Name "UnitTests" -Init ([ScriptBlock]::Create("Set-Location $buildDir\$projectName")) -ScriptBlock { pwd; stestr --test-path . run; Write-Output "Exit code: $LASTEXITCODE" }
} Catch {
    Throw "Could not start the unit tests job."
}

Wait-Job -Timeout $unitTestTimeout -Id $proc.Id

if ($proc.State -eq "Running")
{
   Stop-Job -PassThru -Id $proc.Id | Remove-job
   Throw "Unit tests exceeded time linit of 300 seconds."
}

$result = Receive-Job -Id $proc.Id -ErrorAction Continue
Remove-Job -Id $proc.Id

ExecRetry {
    pushd $buildDir\subunit
    & pip install .
    if ($LastExitCode) { Throw "Failed to install subunit from repo" }
    popd
}

pushd $buildDir\$projectName\.stestr
Move-Item 0 $openstackLogs\subunit.out
subunit2html.exe $openstackLogs\subunit.out $openstackLogs\results.html

Add-Content $openstackLogs\unittest_output.txt $result
pip freeze > $openstackLogs\pip_freeze.log

$exitcode = $result[-1][-1]

$currDate = (Get-Date).ToString()
Write-Output "$currDate Unit tests result exit code: $exitcode"
