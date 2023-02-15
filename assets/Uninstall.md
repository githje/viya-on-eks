Run these commands to remove everything we deployed during the workshop.

```shell
cd ~/environment/viya4-iac-aws/

export iac_tag=5.4.0
export deployment_tag=6.1.0
export backup_date=$(date +%s)
export cloudprovider=aws

helm uninstall nginx-ingress -n nginx

docker run --rm \
  --env-file $IACHOMEDIR/deployments/$cloudprovider/latest/.${cloudprovider}_docker_creds.env \
  -v $iac_dir:/workspace:Z \
  viya4-iac-$cloudprovider:$iac_tag \
  apply -destroy --auto-approve -state /workspace/terraform.tfstate \
  --var-file /workspace/sas-sample-input.tfvars
```