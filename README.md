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


## Using the Cloud9 workspace

* After logging in to workshop studio (https://catalog.us-east-1.prod.workshops.aws/event/dashboard/en-US/workshop), click on the link in the left panel to open the AWS console
* Type "cloud9" into the search box at the top and select the "Cloud9" service link

![Cloud9 Workspace](assets/aws1.jpg)



## Create the AWS cloud infrastructure

