# SAS Viya on AWS AKS (deployment quickstart)

This deployment workshop will walk you through all steps of deploying SAS Viya on AWS EKS (Amazon Elastic Kubernetes Service). We'll start by setting up the AWS cloud infrastructure, then continue to install some required packages and finally deploy the SAS Viya software.

Let's briefly discuss the 3 steps:

* **AWS cloud infrastructure**. We will use the  SAS deployment framework found here: https://github.com/sassoftware/viya4-iac-aws . This framework uses Terraform (https://www.terraform.io/) to create all necessary infrastructure componts. In particular, we'll create:
    * an EKS cluster
    * a virtual machine running a NFS service (as a shared storage provider for SAS Viya)
    * and of course all the "glue" components required for this to work (networking, roles etc.)

* **Required packages**. SAS Viya requires some additional components to be able to run on Kubernetes. We'll need to deploy them before we can continue. We will install these components:
    * nginx ingress controller
    * NFS storage provisioner
    * metrics-server
    * LDAP server

* **SAS Viya**. We'll deploy SAS Viya using the "manual" approach where you will prepare and submit the YAML manifest which triggers the software installation process. For this you will need to become familiar with the `kustomize` tool (https://kustomize.io/). `kustomize` allows you to take the manifest templates shipped by SAS and merge them with site-specific input which you have to provide.


## Using the Cloud9 IDE

* After logging in to workshop studio (https://catalog.us-east-1.prod.workshops.aws/event/dashboard/en-US/workshop), click on the link in the left panel to open the AWS console
* Type "cloud9" into the search box at the top and select the "Cloud9" service link

![Cloud9 Workspace](assets/aws1.jpg)

* Now click on "Open" to launch the Cloud9 IDE

Let's first install a few helper utilities which we'll need later.

```shell
# verify that helm is installed
helm list -A

# verify that the docker runtime is installed
docker ps

# verify that kubectl is installed
kubectl version

# kustomize
opsys=linux
kvers=3.7.0
release_url=https://api.github.com/repos/kubernetes-sigs/kustomize/releases/tags/kustomize%2Fv${kvers}

curl -s $release_url |  grep browser_download.*${opsys}_${arch} |  cut -d '"' -f 4 |  sort -V | tail -n 1 |  xargs curl -sLO
tar xvzf kustomize_*_linux_amd64.tar.gz
sudo mv kustomize /usr/local/bin/
rm -f kustomize_*_linux_amd64.tar.gz

kustomize version

# yq
wget https://github.com/mikefarah/yq/releases/download/v4.30.8/yq_linux_amd64
chmod 755 yq_linux_amd64
sudo mv yq_linux_amd64 /usr/local/bin/yq

yq --version

# k9s - just for fun
wget https://github.com/derailed/k9s/releases/download/v0.27.3/k9s_Linux_amd64.tar.gz
tar xvzf k9s_Linux_amd64.tar.gz
sudo mv k9s /usr/local/bin/
rm -f k9s_Linux_amd64.tar.gz README.md LICENSE

k9s version

# password manager
sudo yum -y install kpcli
```

Finally clone this repository

```shell
# switch to this folder because it is shown in the file explorer panel
cd ~/environment/
git clone https://github.com/githje/viya-on-eks.git
```

You should now see a new folder named "viya-on-eks" in the file explorer on the left. Try to open the file README.md from this folder.


## 1. Create the AWS cloud infrastructure


### Prepare building the Terraform plan file

The SAS-provided IaC ("infrastructure-as-code") scripts use a local Docker container to prepare and run the Terraform scripts. First, let's clone the IaC repository.

```shell
# switch to this folder because it is shown in the file explorer panel
cd ~/environment/

git clone https://github.com/sassoftware/viya4-iac-aws.git --branch 5.4.0
cd viya4-iac-aws/
```

Now create the Docker container which we'll use to run the cloud infrastructure deployment script.

```shell
docker build . -t viya4-iac-aws:5.4.0

# verify that the container has been built successfully
docker images
```

You should see this output (note the first entry).

```
REPOSITORY            TAG       IMAGE ID       CREATED         SIZE
viya4-iac-aws         5.4.0     4a9fa50ad084   6 seconds ago   1.39GB
mikefarah/yq          latest    290cefa2b7ae   4 weeks ago     19.8MB
amazon/aws-cli        2.7.22    e0804ed12ef7   6 months ago    374MB
hashicorp/terraform   1.0.0     3ecccf079b62   20 months ago   106MB
```

The viya4-iac-aws container will be used twice: to create the Terraform plan file and to execute this plan. We need to set a few configuration parameters to make the plan suitable for this workshop.

```shell
# some variables for building names etc.
export iac_tag=5.4.0
export deployment_tag=6.1.0
export backup_date=$(date +%s)
export cloudprovider=aws

# create the project folders containing our customizations
mkdir -p /home/ec2-user/environment/iac-deploy
export IACHOMEDIR=/home/ec2-user/environment/iac-deploy

mkdir -p $IACHOMEDIR/deployments/$cloudprovider/old
mv $IACHOMEDIR/deployments/$cloudprovider/latest/ $IACHOMEDIR/deployments/$cloudprovider/old/$backup_date/
mkdir -p $IACHOMEDIR/deployments/$cloudprovider/latest/deploy
mkdir -p $IACHOMEDIR/deployments/$cloudprovider/latest/iac

export iac_dir=$IACHOMEDIR/deployments/$cloudprovider/latest/iac
export deploy_dir=$IACHOMEDIR/deployments/$cloudprovider/latest/deploy
```

By now you should have received a file containing some extra AWS credentials. We need to add this information to the plan file. The XML file containing the AWS credentials will look like this:

```json
{
    "AccessKey": {
        "UserName": "devops-iac",
        "AccessKeyId": "AAABBBCCC111222333",
        "Status": "Active",
        "SecretAccessKey": "abcdefgh12345",
        "CreateDate": "2023-02-12T21:41:11+00:00"
    }
}
```

We're interested in the `AccessKeyId` and `SecretAccessKey` values. Copy them into the following shell variables:

```shell
# do NOT copy&paste!
export APPID=AAABBBCCC111222333
export PASSWORD=abcdefgh12345
```

Create the credentials file needed by Terraform.

```shell
if [ ! -z $IACHOMEDIR/deployments/$cloudprovider/latest/.${cloudprovider}_docker_creds.env ]; then
echo "[INFO:] Creating credentials file"
cat << EOF > $IACHOMEDIR/deployments/$cloudprovider/latest/.${cloudprovider}_docker_creds.env
 TF_VAR_aws_access_key_id=$APPID
 TF_VAR_aws_secret_access_key=$PASSWORD
EOF
else
 echo "[INFO:] File already exists. Nothing to do"
fi

# verify that the information looks correct
cat $IACHOMEDIR/deployments/$cloudprovider/latest/.${cloudprovider}_docker_creds.env
```

More variables describing the cloud infrastructure.

```shell
export location=us-east-1
export prefix=sas-viya-aws
export tag='"user" = "sas"'
export postgres=internal
export registry=no
```

Finalizing the Terraform TFVARS file.

```shell
# using this template
curl https://raw.githubusercontent.com/sassoftware/viya4-iac-$cloudprovider/main/examples/sample-input.tfvars -o $iac_dir/sas-sample-input.tfvars

IP=$(dig @resolver1.opendns.com ANY myip.opendns.com +short)
CIDR=$(echo ${IP}/32 | sed 's/^/"/;s/$/"/')
echo "IP address of this VM: $IP"

sed -i "s|= \[\]|= \[ $CIDR \]|g" $iac_dir/sas-sample-input.tfvars

# crunchydata or external PG database?
if [ $postgres == "internal" ]; then
  sed -i '/postgres_servers = {/,+2d' $iac_dir/sas-sample-input.tfvars
fi

# use a mirror or not?
if [ $registry == "yes" ]; then
  sed -i "/create_container_registry/d" $iac_dir/sas-sample-input.tfvars
  sed -i "/container_registry_sku/i create_container_registry    = true" $iac_dir/sas-sample-input.tfvars
fi

sed -i "s/<prefix-value>/$prefix/g" $iac_dir/sas-sample-input.tfvars
sed -i "s/<aws-location-value>/$location/g" $iac_dir/sas-sample-input.tfvars
sed -i "s|~/.ssh/id_rsa.pub|/workspace/id_rsa.pub|g" $iac_dir/sas-sample-input.tfvars
sed -i "s/{ }/{ $tag }/g" $iac_dir/sas-sample-input.tfvars

# generate SSH key
ssh-keygen -t rsa -q -f "$iac_dir/id_rsa" -N "" <<< y

# verify results
cat $iac_dir/sas-sample-input.tfvars 
```


### Build the Terraform plan file and create the cloud infrastructure

Create the Terraform plan file.

```shell
docker run --rm \
  --env-file $IACHOMEDIR/deployments/$cloudprovider/latest/.${cloudprovider}_docker_creds.env \
  -v $iac_dir:/workspace:Z \
  viya4-iac-$cloudprovider:$iac_tag \
  plan -var-file /workspace/sas-sample-input.tfvars -out /workspace/terraform.plan
```

The command should end with the following output:

```
Saved the plan to: /workspace/terraform.plan

To perform exactly these actions, run the following command to apply:
    terraform apply "/workspace/terraform.plan"
```

Submit the plan file (build the cloud infrastructure). This will take around 20+ minutes. You will be able to watch the progress on the shell (and in the AWS console).

```shell
docker run --rm \
  --env-file $IACHOMEDIR/deployments/$cloudprovider/latest/.${cloudprovider}_docker_creds.env \
  -v $iac_dir:/workspace:Z \
  viya4-iac-$cloudprovider:$iac_tag \
  apply --auto-approve -state /workspace/terraform.tfstate /workspace/terraform.plan
```

The command should end with the following output:

```
Apply complete! Resources: 100 added, 0 changed, 0 destroyed.

Outputs:

autoscaler_account = "arn:aws:iam::622837347326:role/sas-viya-aws-cluster-autoscaler"
cluster_api_mode = "public"
...
```


### Validate that you can connect to the new EKS cluster

```shell
sudo chown $(id -u):$(id -g) $iac_dir/${prefix}-eks-kubeconfig.conf 
sudo chmod 600 $iac_dir/${prefix}-eks-kubeconfig.conf

export KUBECONFIG=$iac_dir/${prefix}-eks-kubeconfig.conf
kubectl get nodes
```

The command output should look like this:

```
NAME                             STATUS   ROLES    AGE     VERSION
ip-192-168-xx-xxx.ec2.internal   Ready    <none>   3m28s   v1.23.15-eks-49d8fe8
ip-192-168-xx-xxx.ec2.internal   Ready    <none>   3m34s   v1.23.15-eks-49d8fe8
ip-192-168-xx-xxx.ec2.internal   Ready    <none>   4m9s    v1.23.15-eks-49d8fe8
ip-192-168-xx-xxx.ec2.internal   Ready    <none>   4m36s   v1.23.15-eks-49d8fe8
ip-192-168-xx-xxx.ec2.internal   Ready    <none>   3m26s   v1.23.15-eks-49d8fe8
ip-192-168-xx-xxx.ec2.internal   Ready    <none>   3m33s   v1.23.15-eks-49d8fe8
```

Also, check the EKS landing page in the AWS console (https://us-east-1.console.aws.amazon.com/eks/home?region=us-east-1#/clusters). And try this - just for fun (CTRL-C to exit).

```shell
k9s
```

![k9s](assets/aws2.jpg)

This concludes the 1st step. We'll now deploy some required 3rd-party packages.


## 2. Deploy required infrastructure components


### nginx ingress controller

SAS Viya requires the nginx ingress controller (https://github.com/kubernetes/ingress-nginx), which is not installed yet. We'll install it using helm.

```shell
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# list all versions
# helm search repo ingress-nginx --versions

# make nginx use host network (uses port 80 and 443)
helm install ingress-nginx ingress-nginx/ingress-nginx --version 4.4.2 \
    --set controller.hostNetwork=true,controller.service.type="",controller.kind=DaemonSet

helm install nginx-ingress ingress-nginx/ingress-nginx --version 4.4.2 \
    --namespace nginx \
    --create-namespace \
    --set controller.service.type=LoadBalancer

# check version
POD_NAME=$(kubectl -n nginx get pods -l app.kubernetes.io/name=ingress-nginx -o jsonpath='{.items[0].metadata.name}')
kubectl -n nginx exec -it $POD_NAME -- /nginx-ingress-controller --version

# get the ingress-class name, should return: nginx
kubectl -n nginx get IngressClass -o yaml | yq .items[0].metadata.name

# get the service details
ELB_DNS=$(kubectl -n nginx get service nginx-ingress-ingress-nginx-controller -o yaml | \
  yq .status.loadBalancer.ingress[0].hostname)

echo "Hostname of LoadBalancer: $ELB_DNS"

# quick check - this returns 404 (nginx default backend)
curl -k https://$ELB_DNS
```

(Optional) Deploy a simple web application to test web-based access to the cluster

```shell
sed -i "s|{{ INGRESS_DNS }}|$ELB_DNS|" ~/environment/viya-on-eks/assets/test-deploy-http-webserver.yaml | \

kubectl -n default apply -f ~/environment/viya-on-eks/assets/test-deploy-http-webserver.yaml

# wait until the pod is "running"
kubectl -n default get all

# checl
echo "Point your browser to: http://$ELB_DNS/echoserver"
```

Your browser should show a simple web page with some information about the HTTP request:

```
Hostname: echoserver-699997586b-68vdv

Pod Information:
	-no pod information available-

Server values:
	server_version=nginx: 1.12.2 - lua: 10010

(...)
```

This validates that the nginx ingress controller has been successfully deployed.


### metrics-server

Metrics Server is a scalable, efficient source of container resource metrics for Kubernetes. It provides information to the Horizontal Pod Autoscaler (HPA).

See: https://github.com/kubernetes-sigs/metrics-server

```shell
kubectl apply -f ~/environment/viya-on-eks/assets/metrics-server-0.6.2.yaml

# test (repeat this command until the pod has started (~30 secs))
kubectl get --raw /apis/metrics.k8s.io/v1beta1/nodes/ | jq .
```


### NFS storage provisioner

Some services in SAS Viya require RWX storage ("ReadWriteMany") to store configuration data. Shared storage is quite often also used for keeping user data, but it is a system requirement for the deployment as well. The cloud infrastructure setup has created a virtual machine to act as a NFS server. We now need to deploy the storage driver to Kubernetes to access it.

See: https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner

```shell
cd ~/environment
git clone https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner.git

cd nfs-subdir-external-provisioner/

NFS_SERVER_IP=$(cat ~/environment/iac-deploy/deployments/aws/latest/iac/terraform.tfstate | \
    jq -r .outputs.nfs_private_ip.value)
echo "NFS Server IP addreess: $NFS_SERVER_IP"

sed -i "s/namespace:.*/namespace: nfs/g" ./deploy/rbac.yaml ./deploy/deployment.yaml
sed -i "s|/ifs/kubernetes|/nfsshare|g" deploy/deployment.yaml
sed -i "s|10.3.243.101|$NFS_SERVER_IP|g" deploy/deployment.yaml
sed -i 's|nfs-client|nfs-shared-storage|' deploy/class.yaml

kubectl create ns nfs
kubectl apply -f deploy/rbac.yaml
kubectl apply -f deploy/class.yaml
kubectl apply -f deploy/deployment.yaml

# check (nfs-shared-storage)
kubectl get sc
```


### LDAP server

SAS Viya relies on external services for user authentication. This is often delegated to an Active Directory server, but a simple LDAP server with some local users will be sufficient for this workshop. The next step deploys an instance of a LDAP server based on OpenLDAP (https://www.openldap.org/) as a pod running on EKS. Note that his LDAP server is not exposed outside the EKS cluster.

```shell
cd ~/environment/viya-on-eks/
unzip ~/environment/viya-on-eks/assets/openldap.zip

cd openldap
kustomize build ./no_TLS/ -o site.yaml
kubectl -n default apply -f site.yaml

# check (repeat command until pod is running)
kubectl -n default get all -l "app=viya4-openldap-server"    
```

The output of the last command should look like this:

```
NAME                                         READY   STATUS    RESTARTS   AGE
pod/viya4-openldap-server-779b48868d-f6vm7   1/1     Running   0          87s

NAME                                               DESIRED   CURRENT   READY   AGE
replicaset.apps/viya4-openldap-server-779b48868d   1         1         1       87s
```


## 3. Deploy SAS Viya

This is the final step of the workshop. We will prepare and submit a YAML manifest to deploy SAS Viya on the EKS cluster. We will use the kustomize tool which merges the YAML templates provided by SAS with our own, site-specific, modifications.

### Prepare deployment

Create a folder structure for building the SAS Viya YAML manifest:

```shell
mkdir -p /home/ec2-user/environment/viya-deploy/site-config/patches
mkdir -p /home/ec2-user/environment/viya-deploy/site-config/security
```

As a first step, we need to download the YAML templates provided by SAS. These deployment assets contain the SAS license, so they should be handled with care. For the workshop we've prepared a set of deployment assets which need to be downloaded first. The download is protected with a SSH key which is encrypted using gpg.

```shell
# decrypt the SSH key, the password will be given during the workshop
cd /home/ec2-user/environment/viya-on-eks/assets
gpg -o transfer-ssh.key -d transfer-ssh.key.gpg
chmod 400 transfer-ssh.key

# validate MD5 checksum
echo "15c36a8cd75e2ba2d7cbcd8c9c2b77b9  transfer-ssh.key" | md5sum -c -
```

The last command should generate this output:

```
transfer-ssh.key: OK
```

With the private SSH key we can now download the deployment assets.

```shell
cd /home/ec2-user/environment/viya-deploy

# open sftp shell
sftp -r -i ~/environment/viya-on-eks/assets/transfer-ssh.key \
    sas@s-88082dde18b94d429.server.transfer.eu-central-1.amazonaws.com
    
# download file
ls
get SASViyaV4_stable_2023.01_deployment.tgz SASViyaV4_stable_2023.01_deployment.tgz
quit
```

Validate checksum and extract the archive:

```yaml
# validate checksum
echo "9142fc85135b51e0838112e058b33a5d  SASViyaV4_stable_2023.01_deployment.tgz" | md5sum -c -

# extract
tar xvzf SASViyaV4_stable_2023.01_deployment.tgz

# check
ls -lisa
```

The last command should generate this output:

```
total 952
drwxrwxr-x 8 ec2-user ec2-user    140 Feb 13 12:23 sas-bases
-rwxr--r-- 1 ec2-user ec2-user 972494 Feb 13 12:23 SASViyaV4_stable_2023.01_deployment.tgz
drwxrwxr-x 4 ec2-user ec2-user     38 Feb 13 12:52 site-config
```


### Add (k|c)ustomizations

See: https://go.documentation.sas.com/doc/en/itopscdc/v_036/itopswlcm/home.htm

For this workshop we will only apply the minimum amount of sites-specific patches. Most patches are already prepared and you only need to modify a few of them.

Copy the prepared content to the deployment directory:

```shell
cd /home/ec2-user/environment/viya-on-eks/assets
cp -r site-config/ /home/ec2-user/environment/viya-deploy
```

You should now be able to view the files in the site-config directory from the file explorer panel.

![View deployment assets](assets/aws3.jpg)


#### kustomization.yaml

Double click to open `kustomization.yaml`. You need to replace the variable `{{ INGRESS-DNS }}` 2 times with the DNS name of the AWS Load Balancer.

```shell
# retrieve DNS name
echo "Hostname of LoadBalancer: $ELB_DNS"
```

```yaml
configMapGenerator:
- name: ingress-input
  behavior: merge
  literals:
  - INGRESS_HOST={{ INGRESS-DNS }}
- name: sas-shared-config
  behavior: merge
  literals:
  - SAS_SERVICES_URL=https://{{ INGRESS-DNS }}
```


#### sitedefault.yaml

Double click to open `sitedefault.yaml`. You need to replace the variables `{{ LDAP-SERVER-DNS }}` and `{{ SAS-ADMINISTRATOR-USERID }}`.

```shell
# retrieve LDAP DNS name (cluster-internal DNS name)
# the internal DNS name is generated like this:
# <name-of-service>.<namespace>.svc.cluster.local

# get name of services (check the openldap service)
kubectl get svc -n default

# output:
# NAME                     TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)   AGE
# echoserver-svc           ClusterIP   10.100.184.158   <none>        80/TCP    10h
# kubernetes               ClusterIP   10.100.0.1       <none>        443/TCP   13h
# viya4-openldap-service   ClusterIP   10.100.45.156    <none>        389/TCP   3h3m

echo "DNS name of OpenLDAP server is: viya4-openldap-service.default.svc.cluster.local"
```

Use `viyademo01` as the SAS Administrator User.

```yaml
config:
    application:
        sas.identities.providers.ldap.connection:
            host: '{{ LDAP-SERVER-DNS }}'
(...)
        sas.identities:
            administrator: '{{ SAS-ADMINISTRATOR-USERID }}'
```


#### patches/rwx-storage-class.yaml

Double click to open `patches/rwx-storage-class.yaml`. You need to replace the variable `{{ RWX-STORAGE-CLASS }}` with `nfs-shared-storage`. 

```shell
# confirm name of RWX storage class
kubectl get sc
```

```yaml
spec:
  storageClassName: {{ RWX-STORAGE-CLASS }}
```


#### security/openssl-generated-ingress-certificate.yaml

This file does not yet exist. Create it from a SAS-provided template:

```shell
cd /home/ec2-user/environment/viya-deploy
cp sas-bases/examples/security/openssl-generated-ingress-certificate.yaml site-config/security

# validate content (nothing to change)
cat site-config/security/openssl-generated-ingress-certificate.yaml
```


### Build and deploy

We can now finally create the master YAML manifest and submit it to EKS.

```shell
cd /home/ec2-user/environment/viya-deploy
kustomize build -o site.yaml

kubectl apply --selector="sas.com/admin=cluster-api" --server-side --force-conflicts -f site.yaml

kubectl apply --selector="sas.com/admin=cluster-wide" -f site.yaml
kubectl apply --selector="sas.com/admin=cluster-local" -f site.yaml --prune
kubectl apply --selector="sas.com/admin=namespace" -f site.yaml --prune

```