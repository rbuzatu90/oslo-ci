Param(
    [string]$branchName='master',
    [string]$buildFor='',
    [string]$isDebug='no',
    [string]$zuulChange=''
)

$ErrorActionPreference = "Stop"

if ($isDebug -eq  'yes') {
    Write-Host "Debug info:"
    Write-Host "branchName: $branchName"
    Write-Host "buildFor: $buildFor"
}

$projectName = $buildFor.split('/')[-1]

$scriptLocation = [System.IO.Path]::GetDirectoryName($myInvocation.MyCommand.Definition)
. "$scriptLocation\config.ps1"
. "$scriptLocation\utils.ps1"

$hasProject = Test-Path $buildDir\$projectName
$hasopenstackLogs = Test-Path $openstackLogs

Add-Type -AssemblyName System.IO.Compression.FileSystem

$pip_conf_content = @"
[global]
index-url = http://10.20.1.8:8080/cloudbase/CI/+simple/
[install]
trusted-host = 10.20.1.8
"@

if ($hasOpenstackLogs -eq $false){
   mkdir $openstackLogs
} else {
    Remove-Item -Recurse -Force "$openstackLogs\*"
}

if ($hasProject -eq $false){
    Get-ChildItem $buildDir
    Get-ChildItem ( Get-Item $buildDir ).Parent.FullName
    Throw "$projectName repository was not found. Please run gerrit-git-prep.sh for this project first"
}

git config --global user.email "hyper-v_ci@microsoft.com"
git config --global user.name "Hyper-V CI"

pushd C:\
if (Test-Path $pythonArchive) {
    Remove-Item -Force $pythonArchive
}

Invoke-FastWebRequest -Uri http://10.20.1.14:8080/python.zip -OutFile "C:\$pythonArchive"
if (Test-Path $pythonDir)
{
    Cmd /C "rmdir /S /Q $pythonDir"
    #Remove-Item -Recurse -Force $pythonDir
}
Write-Host "Ensure Python folder is up to date"
Write-Host "Extracting archive.."
[System.IO.Compression.ZipFile]::ExtractToDirectory("C:\$pythonArchive", "C:\")

$hasPipConf = Test-Path "$env:APPDATA\pip"
if ($hasPipConf -eq $false){
    mkdir "$env:APPDATA\pip"
}
else 
{
    Remove-Item -Recurse -Force "$env:APPDATA\pip\*"
}
Add-Content "$env:APPDATA\pip\pip.ini" $pip_conf_content

$ErrorActionPreference = "Continue"

& easy_install pip
& pip install setuptools
& pip install pymi
& pip install tox
& pip install nose

& pip install pymongo
& pip install python-memcached
& pip install fixtures
& pip install mock
& pip install testresources
& pip install testscenarios

& pip install oslotest


$ErrorActionPreference = "Stop"

popd

$hasPipConf = Test-Path "$env:APPDATA\pip"
if ($hasPipConf -eq $false) {
    mkdir "$env:APPDATA\pip"
} else {
    Remove-Item -Force -Recurse "$env:APPDATA\pip\*"
}

Add-Content "$env:APPDATA\pip\pip.ini" $pip_conf_content

ExecRetry {
    GitClonePull "$buildDir\requirements" "https://git.openstack.org/openstack/requirements.git" $branchName
}

ExecRetry {
    pushd "$buildDir\requirements"
    Write-Host "Installing OpenStack/Requirements..."
    & pip install -c upper-constraints.txt -U pbr virtualenv httplib2 prettytable>=0.7 setuptools
    & pip install -c upper-constraints.txt -U .
    if ($LastExitCode) { Throw "Failed to install openstack/requirements from repo" }
    popd
}


ExecRetry {
    pushd $buildDir\$projectName
    & update-requirements.exe --source $buildDir\requirements .
    & pip install -r $buildDir\$projectName\requirements.txt
    if ($LastExitCode) { Throw "Failed to install $projectNameInstall requirements" }
    & pip install -e $buildDir\$projectName
    if ($LastExitCode) { Throw "Failed to install $projectNameInstall from repo" }
    popd
}

if (Test-Path "$buildDir\$projectName\test-requirements.txt")
{
    $ErrorActionPreference = "Continue"
    & pip install -r $buildDir\$projectName\test-requirements.txt
    $ErrorActionPreference = "Stop"
}

$currDate = (Get-Date).ToString()
Write-Host "$currDate Running unit tests."

$std_out = New-TemporaryFile
$std_err = New-TemporaryFile

Try {
    pushd $buildDir\$projectName
    $proc = Start-Process -PassThru -RedirectStandardError "$std_err" -RedirectStandardOutput "$std_out" -FilePath "$pythonDir\python.exe" -ArgumentList "-m unittest discover"
} Catch {
    Get-Content $std_out | Add-Content $openstackLogs\unittests_output.txt
    Get-Content $std_err | Add-Content $openstackLogs\unittests_output.txt
    Throw "Could not start the unit tests process."
}


$count = 0;

While (! $proc.HasExited)
{
    Start-Sleep 5;
    $count++
    if ($count -gt 60) {
        Stop-Process -Id $proc.Id -Force
        Get-Content $std_out | Add-Content $openstackLogs\unittests_output.txt
        Get-Content $std_err | Add-Content $openstackLogs\unittests_output.txt
        Throw "Unit tests exceeded time linit of 300 seconds."
    }
}

Get-Content $std_out | Add-Content $openstackLogs\unittests_output.txt
Get-Content $std_err | Add-Content $openstackLogs\unittests_output.txt

$currDate = (Get-Date).ToString()
Write-Host "$currDate Finished running unit tests."
Write-Host "Unit tests finished with exit code $proc.ExitCode"
