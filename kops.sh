#!/bin/bash

set -e

# ============================================================
# kOps Kubernetes Cluster Setup / Delete Script
# ============================================================

# -------------------------------
# Variables
# -------------------------------
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

# -------------------------------
# kOps State Store
# -------------------------------
export KOPS_STATE_STORE="s3://${BUCKET_NAME}"


# ============================================================
# CREATE CLUSTER
# ============================================================

create_cluster() {

    echo ""
    echo "========================================"
    echo "Starting kOps Cluster Creation"
    echo "========================================"

    # -------------------------------
    # Update PATH
    # -------------------------------
    echo "Updating PATH..."

    export PATH="$PATH:/usr/local/bin"


    # -------------------------------
    # Generate SSH Key if not exists
    # -------------------------------
    echo "Checking SSH key..."

    if [ ! -f ~/.ssh/id_rsa ]; then

        echo "SSH key not found. Generating new SSH key..."

        mkdir -p ~/.ssh

        ssh-keygen \
            -t rsa \
            -b 4096 \
            -N "" \
            -f ~/.ssh/id_rsa

    else

        echo "SSH key already exists."

    fi

    cp ~/.ssh/id_rsa.pub my-keypair.pub

    chmod 644 my-keypair.pub


    # -------------------------------
    # Install kubectl
    # -------------------------------
    if ! command -v kubectl &> /dev/null; then

        echo "Installing kubectl..."

        curl -LO \
        "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

        chmod +x kubectl

        sudo mv kubectl /usr/local/bin/

    else

        echo "kubectl already installed."

    fi


    # -------------------------------
    # Install kOps
    # -------------------------------
    if ! command -v kops &> /dev/null; then

        echo "Installing kOps..."

        wget \
        https://github.com/kubernetes/kops/releases/download/v1.32.0/kops-linux-amd64

        chmod +x kops-linux-amd64

        sudo mv kops-linux-amd64 /usr/local/bin/kops

    else

        echo "kOps already installed."

    fi


    # -------------------------------
    # Create S3 Bucket
    # -------------------------------
    echo ""
    echo "Creating S3 bucket..."

    aws s3api create-bucket \
        --bucket "$BUCKET_NAME" \
        --region "$REGION" \
        --create-bucket-configuration LocationConstraint="$REGION" \
        || echo "Bucket may already exist. Continuing..."


    # -------------------------------
    # Enable Versioning
    # -------------------------------
    echo ""
    echo "Enabling S3 bucket versioning..."

    aws s3api put-bucket-versioning \
        --bucket "$BUCKET_NAME" \
        --region "$REGION" \
        --versioning-configuration Status=Enabled


    # -------------------------------
    # Create Cluster
    # -------------------------------
    echo ""
    echo "Creating kOps cluster..."

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


    # -------------------------------
    # Deploy Cluster
    # -------------------------------
    echo ""
    echo "Deploying cluster..."

    kops update cluster \
        --name="$CLUSTER_NAME" \
        --yes \
        --admin


    # -------------------------------
    # Wait for Cluster
    # -------------------------------
    echo ""
    echo "Waiting for cluster validation..."

    kops validate cluster \
        --wait 15m


    # -------------------------------
    # Cluster Information
    # -------------------------------
    echo ""
    echo "========================================"
    echo "Cluster Created Successfully"
    echo "========================================"

    kubectl get nodes

    echo ""
    echo "Cluster Name : $CLUSTER_NAME"
    echo "Region       : $REGION"
    echo "Zones        : $ZONES"
    echo "S3 State     : $KOPS_STATE_STORE"

    echo ""
    echo "To delete everything later run:"
    echo ""
    echo "./kops-cluster.sh delete"
    echo ""
}


# ============================================================
# DELETE ALL S3 OBJECTS INCLUDING VERSIONS
# ============================================================

delete_s3_bucket_completely() {

    echo ""
    echo "========================================"
    echo "Cleaning S3 Bucket"
    echo "========================================"

    echo ""
    echo "Bucket: $BUCKET_NAME"

    # -------------------------------
    # Check if bucket exists
    # -------------------------------
    if ! aws s3api head-bucket \
        --bucket "$BUCKET_NAME" \
        --region "$REGION" 2>/dev/null; then

        echo "S3 bucket does not exist."
        return 0
    fi


    # -------------------------------
    # Get all object versions
    # -------------------------------
    echo ""
    echo "Checking object versions and delete markers..."

    TEMP_FILE="/tmp/${BUCKET_NAME}-versions.json"

    aws s3api list-object-versions \
        --bucket "$BUCKET_NAME" \
        --region "$REGION" \
        --output json > "$TEMP_FILE"


    # -------------------------------
    # Delete all versions
    # -------------------------------
    python3 - "$TEMP_FILE" "$BUCKET_NAME" "$REGION" <<'PYTHON'

import json
import subprocess
import sys

file_name = sys.argv[1]
bucket = sys.argv[2]
region = sys.argv[3]

with open(file_name, "r") as file:
    data = json.load(file)

objects = []

# -------------------------------
# Object versions
# -------------------------------
for item in data.get("Versions", []):

    objects.append({
        "Key": item["Key"],
        "VersionId": item["VersionId"]
    })


# -------------------------------
# Delete markers
# -------------------------------
for item in data.get("DeleteMarkers", []):

    objects.append({
        "Key": item["Key"],
        "VersionId": item["VersionId"]
    })


# -------------------------------
# Delete objects in batches
# AWS allows maximum 1000 objects
# per delete-objects request
# -------------------------------
if objects:

    total = len(objects)

    print("")
    print(f"Found {total} object versions/delete markers.")
    print("Deleting them...")

    for i in range(0, total, 1000):

        batch = objects[i:i + 1000]

        delete_payload = {
            "Objects": batch,
            "Quiet": True
        }

        subprocess.run(
            [
                "aws",
                "s3api",
                "delete-objects",
                "--bucket",
                bucket,
                "--region",
                region,
                "--delete",
                json.dumps(delete_payload)
            ],
            check=True
        )

        print(
            f"Deleted {min(i + 1000, total)} / {total}"
        )

else:

    print("")
    print("Bucket contains no object versions or delete markers.")

PYTHON


    # -------------------------------
    # Remove temporary file
    # -------------------------------
    rm -f "$TEMP_FILE"


    # -------------------------------
    # Delete bucket
    # -------------------------------
    echo ""
    echo "Deleting S3 bucket..."

    aws s3api delete-bucket \
        --bucket "$BUCKET_NAME" \
        --region "$REGION"

    echo ""
    echo "S3 bucket deleted successfully."
}


# ============================================================
# DELETE CLUSTER + S3 BUCKET
# ============================================================

delete_cluster() {

    echo ""
    echo "========================================"
    echo "WARNING"
    echo "========================================"
    echo ""

    echo "This will delete:"
    echo ""
    echo "1. Kubernetes cluster"
    echo "2. EC2 instances"
    echo "3. Load Balancers"
    echo "4. Auto Scaling Groups"
    echo "5. EBS volumes"
    echo "6. All S3 objects"
    echo "7. All S3 object versions"
    echo "8. All S3 delete markers"
    echo "9. kOps S3 state bucket"
    echo ""

    echo "Cluster : $CLUSTER_NAME"
    echo "Bucket  : $BUCKET_NAME"
    echo ""

    read -p "Are you sure? Type DELETE to continue: " CONFIRM

    if [ "$CONFIRM" != "DELETE" ]; then

        echo ""
        echo "Deletion cancelled."

        exit 0

    fi


    # ========================================================
    # DELETE KUBERNETES CLUSTER
    # ========================================================

    echo ""
    echo "========================================"
    echo "Deleting Kubernetes Cluster"
    echo "========================================"

    kops delete cluster \
        --name="$CLUSTER_NAME" \
        --yes


    echo ""
    echo "Cluster deletion completed successfully."


    # ========================================================
    # DELETE S3 BUCKET COMPLETELY
    # ========================================================

    delete_s3_bucket_completely


    # ========================================================
    # FINAL MESSAGE
    # ========================================================

    echo ""
    echo "========================================"
    echo "CLEANUP COMPLETED"
    echo "========================================"
    echo ""

    echo "Cluster : $CLUSTER_NAME"
    echo "Bucket  : $BUCKET_NAME"
    echo ""

    echo "All kOps resources and S3 state storage"
    echo "have been removed successfully."

    echo ""
}


# ============================================================
# SCRIPT MENU
# ============================================================

case "$1" in

    create)

        create_cluster

        ;;

    delete)

        delete_cluster

        ;;

    *)

        echo ""
        echo "Usage:"
        echo ""
        echo "  $0 create"
        echo "  $0 delete"
        echo ""

        echo "Examples:"
        echo ""
        echo "  $0 create"
        echo "  $0 delete"
        echo ""

        exit 1

        ;;

esac