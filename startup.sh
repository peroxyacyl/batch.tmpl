#!/bin/bash
set -e
set -o pipefail

function waitebsstate {
    while [ `aws ec2 describe-volumes --volume-ids $1 | jq -r .Volumes[0].State` != $2 ]; do sleep 1; done
}
export -f waitebsstate

function mkebs {
    echo "create ebs volume of $EBS_GB GB"
    VOLUME_ID=`aws ec2 create-volume --availability-zone $ZONE --size $EBS_GB --volume-type $EBS_TYPE --tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value=BatchEphemral},{Key=Project,Value=MonocerosLearn}]' | jq -r .VolumeId`
    timeout 600 bash -c "waitebsstate $VOLUME_ID available"
    echo "volume created: $VOLUME_ID"

    n=f
    while [ $n != "_" ]
    do
        DEVNAME=xvd${n}
        tfile="/hostdev/xvd${n}"
        if [ ! -b $tfile ]
        then
            echo "try to attach volume $VOLUME_ID to $INSTANCE_ID at /dev/$DEVNAME"
            OK=0
            aws ec2 attach-volume --volume-id $VOLUME_ID --instance-id $INSTANCE_ID --device /dev/$DEVNAME || OK=$?
            if [ $OK -eq 0 ]
            then
                break
            fi
        fi
        n=$(echo "$n" | tr "a-z" "b-z_")
    done

    [ $OK -eq 0 ]
    echo "attaching..."
    timeout 600 bash -c "waitebsstate $VOLUME_ID in-use"
    timeout 600 bash -c "while [ ! -b /hostdev/$DEVNAME ] ; do sleep 1; done"
    echo "attached"

    echo "enable DeletionOnTermination to ensure eventual deletion"
    cat << EOF >> mapping.json
[
  {
    "DeviceName": "/dev/${DEVNAME}",
    "Ebs": {
      "DeleteOnTermination": true
    }
  }
]
EOF
    aws ec2 modify-instance-attribute --instance-id $INSTANCE_ID --block-device-mappings file://mapping.json || echo "proceed anyway"

    echo "mount $DEVNAME on $EBS_PATH"
    mkfs.xfs -f /hostdev/$DEVNAME
    mkdir -p $EBS_PATH
    mount /hostdev/$DEVNAME $EBS_PATH
}

function rmebs {
    set +e
    umount -l $EBS_PATH
    aws ec2 detach-volume --force --volume-id $VOLUME_ID
    timeout 600 bash -c "waitebsstate $VOLUME_ID available"
    aws ec2 delete-volume --volume-id $VOLUME_ID && echo "volume successfully deleted"
}

function mkefs {
    echo "mount efs"
    mkdir -p $EFS_PATH
    mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport $EFS_URL:/ $EFS_PATH
}

EBS_GB=${EBS_GB:-0}
EBS_TYPE=${EBS_TYPE:-gp2}
EBS_PATH=${EBS_PATH:-/wd/ebs}
EFS_PATH=${EFS_PATH:-/wd/efs}
ZONE=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone`
INSTANCE_ID=`curl -s http://169.254.169.254/latest/meta-data/instance-id`
export AWS_DEFAULT_REGION=`echo $ZONE | sed 's/\(.*\)[a-z]/\1/'`


if [ $EBS_GB -gt 0 ]
then
    trap rmebs EXIT
    mkebs
fi

if [ ! -z "$EFS_URL" ]
then
    mkefs
fi

$@