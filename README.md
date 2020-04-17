# kops-migrate
---
Information about migrating a kops k8s cluster between AWS accounts, this was only tried with `k8s.local` clusters, and not with production ready kops clusters.


# Overview
---
Recently, I stumbled accross a situation where I needed to migrate an entire kops k8s cluster from one AWS account to another.
Kops uses S3 to save the state of the cluster including all changes made to it so I thought that just migrating from one S3 to another should make the trick.
I was wrong.

# How I did it
---
Lets say we migrate from aws `account-1` to aws `account-2`.
## Step 1
---
1. Configure awscli to work with `account-1`
2. Use the `s3-sync.sh <s3-url> <local-dir>` to sync the kops cluster s3 state-store locally, This data is the core information needed to deploy the new cluster and is mandatory.

## Step 2
1. Configure awscli to work with `account-2`
2. First, we need to create the S3 bucket, we can do it with the following commands:
```bash
export STATE_STORE=<your-new-state-store-name>
export REGION=<aws-region-to-create-bucket>
$ aws s3api create-bucket --bucket ${KOPS_STATE_STORE} --region ${REGION}
$ aws s3api put-bucket-versioning --bucket ${KOPS_STATE_STORE} --versioning-configuration Status=Enabled
```
1. Now, After the bucket is created we can push the data to this bucket:
	1. First, Configure the s3-url (also this will configure kops-state-dir for later)
	```bash
	$ export KOPS_STATE_STORE=s3://${STATE_STORE}
	```
	2. Run the `s3-sync.sh <local-dir> ${KOPS_STATE_STORE}`
	3. Data should now be pushed to `account-2` s3.

## Step 3
---
Now, You should see your cluster under `kops get clusters`.
There will be reference to the old S3 state directory under `kops edit cluster <your-cluster-name>`:
```yml
  .
  .
  .
  configBase: s3://<your-old-s3-state-store>/<your-cluster-name>
```
Change `<your-old-s3-state-store>` to the new s3 state store.

## Step 4
---
In my case, I also lost the ssh-keypair to the kops cluster, if this is not your case skip this.

Run this command:
```bash
$ kops get secret admin
```

You should see a secret of type `SSHPublicKey`.
This is the ssh-key secret that will be used to connect to the cluster machines.

If you wish to change it first remove the old secret:
```bash
$ kops delete secret sshpublickey admin
```
Now, generate a desired public key and push it to kops
```bash
ssh-keygen -t rsa
kops create secret --name <your-cluster-name> sshpublickey admin -i <path-to-public-key>
```
Now you are ready for the next step.

## Step 5
---
Here comes the state where you install the cluster.
<b>DO NOT RUN kops create cluster</b>
Instead, you want to run:
```bash
kops update cluster <your-cluster-name>
```
This command should finish successfully.
after that run:
```bash
kops update cluster <your-cluster-name> --yes
```
This will start creating your old cluster on the new AWS account with the old state including Security-groups,VPC's,ASG's and so on.

## Step 6
---
You should see your machines start to come up, but the k8s API will not work.
After some debugging I found out that the etcd cannot start properly, I suspect that the etcd data is saved on the ebs masters store, and when it is not present(because the machines are entirely different that `account-1` machines), the etcd won't be able to start with the s3 configuration.

also, If you ssh to the master and take a look at the etcd-manager-main logs, you should see that etcd cannot start and will request you to try to restore from backup.

Thankfully, kops is taking backups of the etcd to the S3 store, so we need to trigger etcd-manager and tell him to restore from one of this backups.

Follow this guide to restore from backup:
https://github.com/kubernetes/kops/blob/master/docs/operations/etcd_backup_restore_encryption.md

Done!
After following this guide, you should have your kubernetes up and running on the new account!

