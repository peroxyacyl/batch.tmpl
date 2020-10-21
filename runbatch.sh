#!/bin/bash
set -e

# REPOSITORY_DOMAIN=xxxxxxxxx.dkr.ecr.ap-northeast-1.amazonaws.com
# REPOSITORY_NAME=my_repo
# JOB_QUEUE=default_queue

CPU=4
MEM=8000
VOL=50
JOB_NAME="ondemand"

while getopts cmnv-: opt; do
    optarg="${!OPTIND}"
    [[ "$opt" = - ]] && opt="-$OPTARG"

    case "-$opt" in
        -c|--cpu)
            CPU="$optarg"
            shift
            ;;
        -m|--memory)
            MEM="$optarg"
            shift
            ;;
        -v|--volume)
            VOL="$optarg"
            shift
            ;;
        -n|--name)
            JOB_NAME="$optarg"
            shift
            ;;
        --)
            break
            ;;
        -\?)
            echo "Usage: runbatch.sh [--cpu CPUs] [--memory MEM_MB] [--volume SIZE_GB] \"CMD_TO_RUN\""
            exit 1
            ;;
        --*)
            echo "$0: illegal option -- ${opt##-}" >&2
            exit 1
            ;;
    esac
done
shift $((OPTIND - 1))

SHELL_FORM_CMD=$1

if [ -z "$REPOSITORY_DOMAIN" ]
then
    echo 'A variable REPOSITORY_DOMAIN is not set'
    echo '    ex.    export REPOSITORY_DOMAIN=0123456789.dkr.ecr.ap-northeast-1.amazonaws.com'
    exit 1
fi

if [ -z "$REPOSITORY_NAME" ]
then
    echo 'A variable REPOSITORY_NAME is not set'
    echo '    ex.    export REPOSITORY_NAME=my_repo'
    exit 1
fi

if [ -z "$JOB_QUEUE" ]
then
    echo 'A variable JOB_QUEUE is not set'
    echo '    ex.    export JOB_QUEUE=default_queue'
    exit 1
fi

REGION=`aws configure get region`
REPOSITORY_URI=$REPOSITORY_DOMAIN/$REPOSITORY_NAME:$JOB_NAME
# convert shell formatted CMD to exec form
EXEC_FORM_CMD=`echo $SHELL_FORM_CMD | gawk -vFPAT='[^ ]*|"[^"]+"' '{out="\""$1"\""; for (i=2; i<=NF;i++) {if (substr($i, 1, 1) == "\"") { $i = substr($i, 2, length($i)-2)} out=out",\""$i"\""}; print out}'`

echo "Pushing to repository... $REPOSITORY_URI"
aws ecr get-login-password | docker login --username AWS --password-stdin $REPOSITORY_DOMAIN
docker build -t $REPOSITORY_URI .
docker push $REPOSITORY_URI

echo "Creating job definition..."
cat << EOF > jobdefinition.json
{
    "jobDefinitionName": "$JOB_NAME",
    "type": "container",
    "retryStrategy": {
        "attempts": 1
    },
    "containerProperties": {
        "image": "$REPOSITORY_URI",
        "vcpus": $CPU,
        "memory": $MEM,
        "command": [
            $EXEC_FORM_CMD
        ],
        "volumes": [
            {
                "host": {
                    "sourcePath": "/dev"
                },
                "name": "device"
            }
        ],
        "mountPoints": [
            {
                "containerPath": "/hostdev",
                "readOnly": false,
                "sourceVolume": "device"
            }
        ],
        "environment": [
            {
                "name": "EBS_GB",
                "value": "$VOL"
            }
        ],
        "readonlyRootFilesystem": false,
        "privileged": true,
        "ulimits": []
    },
    "timeout": {
        "attemptDurationSeconds": 7200
    }
}
EOF
aws batch register-job-definition --cli-input-json file://jobdefinition.json

echo "Submitting BatchJobRun"
JOB_ID=`aws batch submit-job --job-name $JOB_NAME --job-queue $JOB_QUEUE --job-definition $JOB_NAME | jq -r .jobId`

[ -z $JOB_ID ] && exit 1

echo "Job submitted to https://$REGION.console.aws.amazon.com/batch/v2/home?region=$REGION#jobs/detail/$JOB_ID"

function getstatus {
    aws batch describe-jobs --jobs $JOB_ID | jq -r .jobs[0].status
}

j=0
spinner="/|\\-/|\\-"
STATUS=`getstatus`
while [ "$STATUS" != "SUCCEEDED" -a "$STATUS" != "FAILED" ]
do
    echo $STATUS
    while [ `getstatus` == "$STATUS" ]
    do
        echo -n "${spinner:$j:1}"
        echo -en "\010"
        sleep 1
        j=`echo $j | tr "0-7" "1-70"`
    done
    STATUS=`getstatus`

    if [ $STATUS == "RUNNING" ]
    then
        LOGSTREAM=`aws batch describe-jobs --jobs $JOB_ID | jq -r .jobs[0].container.logStreamName`
        echo "Log available at https://$REGION.console.aws.amazon.com/cloudwatch/home?region=$REGION#logEventViewer:group=/aws/batch/job;stream=$LOGSTREAM"
    fi
done
echo $STATUS