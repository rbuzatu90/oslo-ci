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

run_wsman_ps $hyperv $WIN_USER $WIN_PASS 'Remove-Item -Recurse -Force C:\OpenStack\oslo-ci ; git clone https://github.com/cloudbase/oslo-ci C:\OpenStack\oslo-ci ; cd C:\OpenStack\oslo-ci ; git checkout cambridge-2016 2>&1' | tee create-environment.log

set +e
run_wsman_cmd $hyperv $WIN_USER $WIN_PASS '"bash C:\OpenStack\oslo-ci\Hyper-V\gerrit-git-prep.sh --zuul-site '$ZUUL_SITE' --gerrit-site '$ZUUL_SITE' --zuul-ref '$ZUUL_REF' --zuul-change '$ZUUL_CHANGE' --zuul-project '$ZUUL_PROJECT' 2>&1"' | tee -a create-environment.log
run_wsman_ps $hyperv $WIN_USER $WIN_PASS '"C:\OpenStack\oslo-ci\Hyper-V\scripts\build_and_run.ps1 -branchName '$ZUUL_BRANCH' -buildFor '$ZUUL_PROJECT' 2>&1"' | tee -a create-environment.log
result_run=$?
run_wsman_ps $hyperv $WIN_USER $WIN_PASS "Get-Content $windows_logs_folder\unittest_output.txt" | tee unittest_output.txt
set -e

exit $result_run