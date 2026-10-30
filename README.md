# kOps Kubernetes Cluster Setup & Cleanup Script

Automated Bash script to create and delete a **Kubernetes cluster using kOps on AWS**.

The script also manages the **kOps S3 state store** and automatically removes:

- Kubernetes cluster resources
- EC2 instances
- Auto Scaling Groups
- Load Balancers
- EBS volumes
- S3 objects
- S3 object versions
- S3 delete markers
- kOps S3 state bucket

---

## 📌 Overview

This script provides two operations:

```bash
./kops-cluster.sh create
```

Creates and deploys the kOps Kubernetes cluster.

```bash
./kops-cluster.sh delete
```

Deletes the Kubernetes cluster and completely removes the kOps S3 state bucket, including versioned objects.

---

## 🏗️ Architecture

```text
                         AWS
                          |
                          |
                   +--------------+
                   |     S3       |
                   | kOps State   |
                   |    Store     |
                   +--------------+
                          |
                          |
                   +--------------+
                   |     kOps     |
                   +--------------+
                          |
                          |
              +-------------------------+
              | Kubernetes Cluster      |
              |                         |
              |  Control Plane (1)      |
              |                         |
              |  Worker Nodes (2)       |
              |                         |
              |  Calico Networking      |
              +-------------------------+
```

---

# ⚙️ Configuration

The main configuration is defined at the beginning of the script.

```bash
BUCKET_NAME="ajay-client-bkt-143"
CLUSTER_NAME="reyaz.k8s.local"
REGION="ap-south-1"
ZONES="ap-south-1a,ap-south-1b"

CONTROL_PLANE_SIZE="m7i-flex.large"
NODE_SIZE="m7i-flex.large"

CONTROL_PLANE_COUNT=1
NODE_COUNT=2

CONTROL_PLANE_VOLUME=40
NODE_VOLUME=40

AMI_ID="ami-0f918f7e67a3323f0"
```

### Configuration Details

| Variable | Description |
|---|---|
| `BUCKET_NAME` | S3 bucket used as the kOps state store |
| `CLUSTER_NAME` | Kubernetes cluster name |
| `REGION` | AWS region |
| `ZONES` | Availability Zones |
| `CONTROL_PLANE_SIZE` | EC2 instance type for control plane |
| `NODE_SIZE` | EC2 instance type for worker nodes |
| `CONTROL_PLANE_COUNT` | Number of control-plane nodes |
| `NODE_COUNT` | Number of worker nodes |
| `CONTROL_PLANE_VOLUME` | Control-plane EBS volume size in GB |
| `NODE_VOLUME` | Worker-node EBS volume size in GB |
| `AMI_ID` | AMI used for cluster instances |

---

# 🔐 Prerequisites

Before running the script, make sure the following are available.

## 1. AWS CLI

Check:

```bash
aws --version
```

Configure AWS credentials:

```bash
aws configure
```

Verify:

```bash
aws sts get-caller-identity
```

The AWS IAM user/role should have sufficient permissions to create and delete:

- EC2
- VPC/network resources
- Auto Scaling Groups
- Load Balancers
- EBS
- S3
- IAM-related resources required by kOps

---

## 2. Bash

Check:

```bash
bash --version
```

The script is designed to run on Linux.

---

## 3. Python 3

Python is used during deletion to process S3 object versions and delete markers.

Check:

```bash
python3 --version
```

---

## 4. SSH

Check:

```bash
ssh -V
```

The script automatically creates an RSA SSH key if:

```text
~/.ssh/id_rsa
```

does not already exist.

---

# 📦 Tools Installed Automatically

During `create`, the script checks whether these tools exist:

### kubectl

If not installed, the script downloads the latest stable Linux AMD64 version.

### kOps

If not installed, the script installs:

```text
kOps v1.32.0
```

The installation path is:

```text
/usr/local/bin/
```

---

# 🔑 kOps State Store

kOps stores the cluster configuration and state in S3.

The script sets:

```bash
export KOPS_STATE_STORE="s3://${BUCKET_NAME}"
```

For the current configuration:

```text
s3://ajay-client-bkt-143
```

The bucket is automatically created during cluster creation.

---

# 🪣 S3 Versioning

The script enables S3 versioning:

```bash
aws s3api put-bucket-versioning \
    --bucket "$BUCKET_NAME" \
    --region "$REGION" \
    --versioning-configuration Status=Enabled
```

Versioning is useful for protecting the kOps state store from accidental overwrites or deletions.

However, versioning creates an important consideration during deletion.

Simply running:

```bash
aws s3 rb s3://bucket --force
```

may not be sufficient for a versioned bucket containing old object versions and delete markers.

Therefore, this script has a dedicated cleanup function.

---

# 🧹 S3 Cleanup Process

The script uses:

```bash
delete_s3_bucket_completely
```

The cleanup process is:

```text
S3 Bucket
    |
    +-- Current Objects
    |
    +-- Old Object Versions
    |
    +-- Delete Markers
    |
    ↓
Delete all versions
    |
    ↓
Delete delete markers
    |
    ↓
Delete empty bucket
```

The script first retrieves:

```bash
aws s3api list-object-versions
```

Then it deletes the objects in batches using:

```bash
aws s3api delete-objects
```

AWS allows up to **1000 objects per delete request**, so the script automatically processes large numbers of objects in batches.

Finally:

```bash
aws s3api delete-bucket
```

removes the empty S3 bucket.

---

# 🚀 Create Cluster

Make the script executable:

```bash
chmod +x kops-cluster.sh
```

Run:

```bash
./kops-cluster.sh create
```

The script performs the following operations:

```text
1. Update PATH
       ↓
2. Check SSH key
       ↓
3. Generate SSH key if required
       ↓
4. Install kubectl if required
       ↓
5. Install kOps if required
       ↓
6. Create S3 bucket
       ↓
7. Enable S3 versioning
       ↓
8. Create kOps cluster configuration
       ↓
9. Deploy cluster
       ↓
10. Validate cluster
       ↓
11. Display Kubernetes nodes
```

---

# ☸️ Cluster Creation Command

Internally, the script runs:

```bash
kops create cluster \
    --name="$CLUSTER_NAME" \
    --zones="$ZONES" \
    --control-plane-count="$CONTROL_PLANE_COUNT" \
    --control-plane-size="$CONTROL_PLANE_SIZE" \
    --node-count="$NODE_COUNT" \
    --node-size="$NODE_SIZE" \
    --node-volume-size="$NODE_VOLUME" \
    --control-plane-volume-size="$CONTROL_PLANE_VOLUME" \
    --ssh-public-key=my-keypair.pub \
    --image="$AMI_ID" \
    --networking=calico \
    --topology=public
```

Then:

```bash
kops update cluster \
    --name="$CLUSTER_NAME" \
    --yes \
    --admin
```

Finally:

```bash
kops validate cluster --wait 15m
```

---

# 🔍 Verify Cluster

After creation:

```bash
kubectl get nodes
```

Example:

```text
NAME                         STATUS   ROLES
ip-xxx-xxx-xxx-xxx           Ready    control-plane
ip-xxx-xxx-xxx-xxx           Ready    <none>
ip-xxx-xxx-xxx-xxx           Ready    <none>
```

Check all Kubernetes resources:

```bash
kubectl get all -A
```

Check kOps:

```bash
kops validate cluster
```

---

# 🗑️ Delete Cluster

Run:

```bash
./kops-cluster.sh delete
```

The script displays a warning:

```text
========================================
WARNING
========================================

This will delete:

1. Kubernetes cluster
2. EC2 instances
3. Load Balancers
4. Auto Scaling Groups
5. EBS volumes
6. All S3 objects
7. All S3 object versions
8. All S3 delete markers
9. kOps S3 state bucket
```

---

# ⚠️ Deletion Confirmation

The script requires the exact confirmation:

```text
DELETE
```

Example:

```text
Are you sure? Type DELETE to continue: DELETE
```

Do **not** enter:

```text
yes
```

or:

```text
YES
```

Only:

```text
DELETE
```

will continue.

Any other input cancels the operation.

---

# 🧨 Delete Flow

When the delete command is executed:

```text
./kops-cluster.sh delete
             |
             ↓
     Confirmation
             |
             ↓
    kops delete cluster
             |
             ↓
     Delete AWS resources
             |
             ↓
   Check S3 bucket exists
             |
             ↓
    List object versions
             |
             ↓
 Delete object versions
             |
             ↓
 Delete delete markers
             |
             ↓
      Delete S3 bucket
             |
             ↓
       Cleanup complete
```

---

# 🔒 Safety Features

The script uses:

```bash
set -e
```

This causes the script to stop when a command fails.

Deletion also requires explicit confirmation:

```text
DELETE
```

This helps prevent accidental cluster deletion.

---

# 📁 Files Generated

During execution, the script may create:

```text
my-keypair.pub
```

This contains the public SSH key used by kOps.

During S3 cleanup, a temporary file may be created:

```text
/tmp/<bucket-name>-versions.json
```

The temporary file is removed automatically after processing.

---

# 🛠️ Useful Commands

### Check cluster

```bash
kops validate cluster
```

### List nodes

```bash
kubectl get nodes
```

### List all resources

```bash
kubectl get all -A
```

### Check cluster configuration

```bash
kops get cluster
```

### View cluster configuration

```bash
kops get cluster --name reyaz.k8s.local -o yaml
```

### Check S3 bucket

```bash
aws s3 ls s3://ajay-client-bkt-143
```

### Check S3 versioning

```bash
aws s3api get-bucket-versioning \
    --bucket ajay-client-bkt-143
```

---

# ⚠️ Important Notes

## 1. Deletion is destructive

Running:

```bash
./kops-cluster.sh delete
```

deletes the Kubernetes infrastructure and S3 state bucket.

Make sure you do not need the cluster or its state before proceeding.

---

## 2. Verify the bucket name

Before deleting, verify:

```bash
grep BUCKET_NAME kops-cluster.sh
```

The current bucket configured in the script is:

```text
ajay-client-bkt-143
```

If your actual bucket is different, update:

```bash
BUCKET_NAME="..."
```

before running the script.

---

## 3. AWS permissions

The AWS identity running this script needs permissions for the resources being created and deleted.

Verify the current identity:

```bash
aws sts get-caller-identity
```

---

## 4. AMI compatibility

The configured AMI:

```text
ami-0f918f7e67a3323f0
```

is region-specific.

If you change the AWS region, verify that the AMI exists and is compatible with the selected kOps version.

---

# 📋 Complete Usage

## Create

```bash
chmod +x kops-cluster.sh

./kops-cluster.sh create
```

## Delete

```bash
./kops-cluster.sh delete
```

## Invalid command

```bash
./kops-cluster.sh
```

Output:

```text
Usage:

  ./kops-cluster.sh create
  ./kops-cluster.sh delete
```

---

# 🎯 Summary

This script automates the complete lifecycle of a kOps Kubernetes cluster on AWS.

### Create

```text
S3 State Store
      ↓
kOps Configuration
      ↓
AWS Infrastructure
      ↓
Kubernetes Cluster
      ↓
Cluster Validation
```

### Delete

```text
Kubernetes Cluster
      ↓
AWS Infrastructure
      ↓
S3 Objects
      ↓
S3 Object Versions
      ↓
S3 Delete Markers
      ↓
S3 State Bucket
      ↓
Complete Cleanup
```

The main benefit is that **one command can create the complete kOps environment and another command can clean up the cluster and its versioned S3 state store**.

---

## Commands

```bash
# Make executable
chmod +x kops-cluster.sh

# Create cluster
./kops-cluster.sh create

# Delete cluster and completely clean S3
./kops-cluster.sh delete
```
