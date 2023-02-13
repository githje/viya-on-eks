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
    * cert-manager
    * metrics-server
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
```

Finally clone this repository

```shell
# switch to this folder because it is shown in the file explorer panel
cd ~/environment/
git clone https://github.com/githje/viya-on-eks.git
```

You should now see a new folder named "viya-on-eks" in the file explorer on the left. Try to open the file README.md from this folder.


## Create the AWS cloud infrastructure

```shell
git clone https://github.com/sassoftware/viya4-iac-aws.git --branch 5.4.0

cd viya4-iac-aws/

```
