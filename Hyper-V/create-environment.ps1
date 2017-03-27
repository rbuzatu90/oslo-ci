Param(
    [string]$branchName='master',
    [string]$buildFor=''
)

$ErrorActionPreference = "Stop"

$projectName = $buildFor.split('/')[-1]

$scriptLocation = [System.IO.Path]::GetDirectoryName($myInvocation.MyCommand.Definition)
. "$scriptLocation\config.ps1"
. "$scriptLocation\utils.ps1"

$hasProject = Test-Path $buildDir\$projectName
$hasopenstackLogs = Test-Path $openstackLogs

if ($hasOpenstackLogs -eq $false){
   mkdir $openstackLogs
} else {
    Remove-Item -Recurse -Force "$openstackLogs\*"
}

Add-Type -AssemblyName System.IO.Compression.FileSystem

$pip_conf_content = @"
[global]
index-url = http://10.20.1.8:8080/cloudbase/CI/+simple/
[install]
trusted-host = 10.20.1.8
"@

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
Write-Output "Ensure Python folder is up to date"
Write-Output "Extracting archive.."
[System.IO.Compression.ZipFile]::ExtractToDirectory("C:\$pythonArchive", "C:\")

popd

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
& pip install os.testr

& pip install oslotest


$ErrorActionPreference = "Stop"

ExecRetry {
    GitClonePull "$buildDir\requirements" "https://git.openstack.org/openstack/requirements.git" $branchName
}

ExecRetry {
    GitClonePull "$buildDir\subunit" "https://github.com/testing-cabal/subunit" master
}

ExecRetry {
    GitClonePull "$buildDir\stestr" "https://github.com/mtreinish/stestr.git" master
}

ExecRetry {
    pushd "$buildDir\requirements"
    Write-Output "Installing OpenStack/Requirements..."
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

ExecRetry {
    pushd $buildDir\stestr
    & pip install -r $buildDir\stestr\requirements.txt .
    if ($LastExitCode) { Throw "Failed to install stestr from repo" }
    popd
}

if (Test-Path "$buildDir\$projectName\test-requirements.txt")
{
    $ErrorActionPreference = "Continue"
    & pip install -r $buildDir\$projectName\test-requirements.txt
    $ErrorActionPreference = "Stop"
}

$currDate = (Get-Date).ToString()
Write-Output "$currDate Done building env"

pushd "$baseDir"
./run_tests.ps1 -buildFor 'openstack/oslo.utils' > "$openstackLogs\run_tests.log"

