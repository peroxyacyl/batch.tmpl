To run `df` command on an AWS batch container with 1 vCPUs, 2GB memory and 10GB ephemeral storage:

```
./runbatch.sh --cpu 1 --memory 2000 --volume 10 --name display_free_disk_space "df"
```
