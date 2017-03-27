#!/bin/bash

function exec_with_retry2 () {
    local MAX_RETRIES=$1
    local INTERVAL=$2
    local COUNTER=0

    while [ $COUNTER -lt $MAX_RETRIES ]; do
        EXIT=0
        echo `date -u +%H:%M:%S`
        eval '${@:3}' || EXIT=$?
        if [ $EXIT -eq 0 ]; then
            return 0
        fi
        let COUNTER=COUNTER+1

        if [ -n "$INTERVAL" ]; then
            sleep $INTERVAL
        fi
    done
    return $EXIT
}

function exec_with_retry () {
    local CMD=$1
    local MAX_RETRIES=${2-10}
    local INTERVAL=${3-0}

    exec_with_retry2 $MAX_RETRIES $INTERVAL $CMD
}

function run_wsman_cmd () {
    local HOST=$1
    local USERNAME=$2
    local PASSWORD=$3
    local CMD=$4

    exec_with_retry "python /home/jenkins-slave/tools/wsman.py -U https://$HOST:5986/wsman -u $USERNAME -p $PASSWORD $CMD"
}

function run_wsman_ps() {
    local host=$1
    local win_user=$2
    local win_password=$3
    local cmd=$4

    run_wsman_cmd $host $win_user $win_password "powershell -NonInteractive -ExecutionPolicy RemoteSigned -Command $cmd"
}

windows_logs_folder='C:\OpenStack\Logs'
PROJECT_NAME=$(basename $ZUUL_PROJECT)
ZUUL_SITE=`echo "$ZUUL_URL" |sed 's/.\{2\}$//'`
if [ -z "$PROJECT_NAME" ]; then echo "Could not get project name. ZUUL_PROJECT is $ZUUL_PROJECT and PROJECT_NAME is $PROJECT_NAME"; exit 1; fi

run_wsman_ps $hyperv $WIN_USER $WIN_PASS 'Remove-Item -Recurse -Force C:\OpenStack\oslo-ci ; git clone https://github.com/cloudbase/oslo-ci C:\OpenStack\oslo-ci ; cd C:\OpenStack\oslo-ci ; git checkout cambridge-2016 2>&1' | tee create-environment-$ZUUL_UUID.log

set +e
run_wsman_cmd $hyperv $WIN_USER $WIN_PASS '"bash C:\OpenStack\oslo-ci\Hyper-V\gerrit-git-prep.sh --zuul-site '$ZUUL_SITE' --gerrit-site '$ZUUL_SITE' --zuul-ref '$ZUUL_REF' --zuul-change '$ZUUL_CHANGE' --zuul-project '$ZUUL_PROJECT' 2>&1"' | tee -a create-environment-$ZUUL_UUID.log
run_wsman_ps $hyperv $WIN_USER $WIN_PASS '"C:\OpenStack\oslo-ci\Hyper-V\create-environment.ps1 -branchName '$ZUUL_BRANCH' -buildFor '$ZUUL_PROJECT' 2>&1"' | tee -a create-environment-$ZUUL_UUID.log
run_wsman_ps $hyperv $WIN_USER $WIN_PASS '"C:\OpenStack\oslo-ci\Hyper-V\run_tests.ps1 -buildFor '$ZUUL_PROJECT' 2>&1"' | tee -a create-environment-$ZUUL_UUID.log
result_run=$?

run_wsman_ps $hyperv $WIN_USER $WIN_PASS "Get-Content $windows_logs_folder\unittest_output.txt" | tee unittest_output-$ZUUL_UUID.log
run_wsman_ps $hyperv $WIN_USER $WIN_PASS "Get-Content $windows_logs_folder\subunit.out" | tee subunit-$ZUUL_UUID.log
run_wsman_ps $hyperv $WIN_USER $WIN_PASS "Get-Content $windows_logs_folder\pip_freeze.log" | tee pip_freeze-$ZUUL_UUID.log
run_wsman_ps $hyperv $WIN_USER $WIN_PASS "Get-Content $windows_logs_folder\results.html" | tee results-$ZUUL_UUID.html

if [[ -z $IS_DEBUG_JOB ]] || [[ $IS_DEBUG_JOB == "no" ]]; then
    run_wsman_ps $hyperv $WIN_USER $WIN_PASS "C:\OpenStack\oslo-ci\Hyper-V\cleanup.ps1" | tee -a create-environment-$ZUUL_UUID.log
fi

gzip -9 unittest_output-$ZUUL_UUID.log
gzip -9 create-environment-$ZUUL_UUID.log
gzip -9 pip_freeze-$ZUUL_UUID.log
gzip -9 subunit-$ZUUL_UUID.log
gzip -9 results-$ZUUL_UUID.html

ssh -o "UserKnownHostsFile /dev/null" -o "StrictHostKeyChecking no" -i $LOGS_SSH_KEY logs@logs.openstack.tld "if [ -z '$ZUUL_CHANGE' ] || [ -z '$ZUUL_PATCHSET' ]; then echo 'Missing parameters!'; exit 1; elif [ ! -d /srv/logs/$PROJECT_NAME/$ZUUL_CHANGE/$ZUUL_PATCHSET ]; then mkdir -p /srv/logs/$PROJECT_NAME/$ZUUL_CHANGE/$ZUUL_PATCHSET; else rm -rf /srv/logs/$PROJECT_NAME/$ZUUL_CHANGE/$ZUUL_PATCHSET/*; fi"
scp -o "UserKnownHostsFile /dev/null" -o "StrictHostKeyChecking no" -i $LOGS_SSH_KEY "unittest_output-$ZUUL_UUID.log.gz" logs@logs.openstack.tld:/srv/logs/$PROJECT_NAME/$ZUUL_CHANGE/$ZUUL_PATCHSET/unittest_output.log.gz
scp -o "UserKnownHostsFile /dev/null" -o "StrictHostKeyChecking no" -i $LOGS_SSH_KEY "subunit-$ZUUL_UUID.log.gz" logs@logs.openstack.tld:/srv/logs/$PROJECT_NAME/$ZUUL_CHANGE/$ZUUL_PATCHSET/subunit.log.gz
scp -o "UserKnownHostsFile /dev/null" -o "StrictHostKeyChecking no" -i $LOGS_SSH_KEY "pip_freeze-$ZUUL_UUID.log.gz" logs@logs.openstack.tld:/srv/logs/$PROJECT_NAME/$ZUUL_CHANGE/$ZUUL_PATCHSET/pip_freeze.log.gz
scp -o "UserKnownHostsFile /dev/null" -o "StrictHostKeyChecking no" -i $LOGS_SSH_KEY "results-$ZUUL_UUID.html.gz" logs@logs.openstack.tld:/srv/logs/$PROJECT_NAME/$ZUUL_CHANGE/$ZUUL_PATCHSET/results.html.gz
scp -o "UserKnownHostsFile /dev/null" -o "StrictHostKeyChecking no" -i $LOGS_SSH_KEY "create-environment-$ZUUL_UUID.log.gz" logs@logs.openstack.tld:/srv/logs/$PROJECT_NAME/$ZUUL_CHANGE/$ZUUL_PATCHSET/create-environment.log.gz

set -e

exit $result_run

