$scriptLocation = [System.IO.Path]::GetDirectoryName($myInvocation.MyCommand.Definition)
. "$scriptLocation\config.ps1"

$ErrorActionPreference = "SilentlyContinue"

Remove-Item -Recurse -Force "$pythonDir"
Remove-Item -Recurse -Force "$buildDir\*"
Remove-Item -Recurse -Force "$openstackLogs\*"
