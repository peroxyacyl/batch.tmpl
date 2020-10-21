To run `df` command on an AWS batch container with 1 vCPUs, 2GB memory and 10GB ephemeral storage:

```
# set up ECR and AWS Batch queue
export REPOSITORY_DOMAIN=xxxxxxxxx.dkr.ecr.ap-northeast-1.amazonaws.com
export REPOSITORY_NAME=my_repo
export JOB_QUEUE=default_queue

./runbatch.sh --cpu 1 --memory 2000 --volume 10 --name display_free_disk_space "df"
```

## dependencies

You'll need:
```
awscli
gawk
docker
```