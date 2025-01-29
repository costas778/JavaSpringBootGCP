#!/bin/bash
export AWS_REGION=us-east-1

# Exit on any error, except for specific commands we want to allow to fail
set -e

# Set variables (same as in setup.sh)
PROJECT_ROOT=$(pwd)
AWS_REGION=${AWS_REGION:-"us-east-1"}
ENVIRONMENT=${ENVIRONMENT:-"dev"}
CLUSTER_NAME="${ENVIRONMENT}-ecabs-cluster"
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

# First delete all Kubernetes workloads (if they exist)
echo "Checking for Kubernetes resources..."
if [ -d "kubernetes" ]; then
    echo "Deleting Kubernetes resources..."
    kubectl delete -f kubernetes/consumer/ --ignore-not-found || true
    kubectl delete -f kubernetes/producer/ --ignore-not-found || true
    kubectl delete -f kubernetes/rabbitmq/ --ignore-not-found || true
    kubectl delete -f kubernetes/configmaps/ --ignore-not-found || true
    echo "Waiting for Kubernetes resources to be deleted..."
    sleep 30
else
    echo "No Kubernetes directory found, skipping Kubernetes cleanup..."
fi

# Check if EKS cluster exists and delete node groups first
echo "Checking for EKS cluster..."
if aws eks describe-cluster --name ${CLUSTER_NAME} >/dev/null 2>&1; then
    echo "Checking for node groups..."
    NODE_GROUPS=$(aws eks list-nodegroups --cluster-name ${CLUSTER_NAME} --query 'nodegroups[*]' --output text)
    
    if [ ! -z "$NODE_GROUPS" ]; then
        echo "Found node groups, deleting them first..."
        for ng in $NODE_GROUPS; do
            echo "Deleting node group: $ng"
            aws eks delete-nodegroup --cluster-name ${CLUSTER_NAME} --nodegroup-name $ng
            echo "Waiting for node group deletion..."
            aws eks wait nodegroup-deleted --cluster-name ${CLUSTER_NAME} --nodegroup-name $ng
        done
    fi

    echo "Deleting EKS cluster..."
    aws eks delete-cluster --name ${CLUSTER_NAME}
    echo "Waiting for EKS cluster deletion..."
    aws eks wait cluster-deleted --name ${CLUSTER_NAME}
else
    echo "No EKS cluster found, skipping cluster deletion..."
fi

# Delete CloudFormation stacks
echo "Checking and deleting CloudFormation stacks..."
STACKS=$(aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE --query 'StackSummaries[].StackName' --output text)
for stack in $STACKS; do
    if [[ $stack == *"BlueGreenContainerImageStack"* ]] || [[ $stack == *"CDKToolkit"* ]]; then
        echo "Deleting stack: $stack"
        aws cloudformation delete-stack --stack-name $stack
        echo "Waiting for stack deletion..."
        aws cloudformation wait stack-delete-complete --stack-name $stack
    fi
done

# Delete ECR repositories
echo "Checking ECR repositories..."
REPOS=(
    "booking-producer" 
    "booking-consumer"
    "cdk-hnb659fds-container-assets-961109809677-us-east-1"
    "bluegreencontainerimagestack-ecsbluegreenbuildimageecrrepo49cbe659-qrzayosbq0gq"
    "bluegreencontainerimagestack-ecsbluegreenbuildimageecrrepo49cbe659-2l7kavmyimav"
)
for repo in "${REPOS[@]}"; do
    if aws ecr describe-repositories --repository-names "${repo}" >/dev/null 2>&1; then
        echo "Deleting ECR repository: ${repo}"
        aws ecr delete-repository \
            --repository-name "${repo}" \
            --force \
            --region ${AWS_REGION}
    else
        echo "ECR repository ${repo} not found, skipping..."
    fi
done

# Check if Terraform state exists before trying to destroy
echo "Checking Terraform state..."
if [ -d "terraform/environments/$ENVIRONMENT" ]; then
    echo "Destroying Terraform infrastructure..."
    cd terraform/environments/$ENVIRONMENT
    if [ -f "terraform.tfstate" ]; then
        terraform destroy -auto-approve || true
    else
        echo "No Terraform state found, skipping terraform destroy..."
    fi
    
    # Clean up Terraform local files
    rm -rf .terraform || true
    rm -f .terraform.lock.hcl || true
    rm -f terraform.tfstate* || true
    cd $PROJECT_ROOT
else
    echo "No Terraform environment directory found, skipping Terraform cleanup..."
fi

# Clean up local directories if they exist
echo "Cleaning up local directories..."
rm -rf terraform/environments/$ENVIRONMENT || true
rm -rf terraform/modules || true
rm -rf kubernetes || true
rm -rf docker || true

# Final cleanup of VPC and associated resources
echo "Checking for lingering VPC resources..."
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${ENVIRONMENT}-ecabs-vpc" --query 'Vpcs[0].VpcId' --output text || echo "none")
if [ "$VPC_ID" != "None" ] && [ "$VPC_ID" != "null" ] && [ "$VPC_ID" != "none" ]; then
    echo "Found VPC: ${VPC_ID}, cleaning up associated resources..."
    
    # Delete all Network Interfaces first
    echo "Deleting Network Interfaces..."
    ENIs=$(aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=${VPC_ID}" --query 'NetworkInterfaces[].NetworkInterfaceId' --output text)
    for eni in $ENIs; do
        echo "Deleting ENI: $eni"
        aws ec2 delete-network-interface --network-interface-id $eni || true
    done
    
    # Delete NAT Gateways
    NAT_GATEWAY_IDS=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=${VPC_ID}" --query 'NatGateways[].NatGatewayId' --output text)
    for nat in $NAT_GATEWAY_IDS; do
        echo "Deleting NAT Gateway: ${nat}"
        aws ec2 delete-nat-gateway --nat-gateway-id $nat
    done
    if [ ! -z "$NAT_GATEWAY_IDS" ]; then
        echo "Waiting for NAT Gateways to delete..."
        sleep 60  # Increased wait time
    fi

    # Delete Subnets
    SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" --query 'Subnets[].SubnetId' --output text)
    for subnet in $SUBNETS; do
        echo "Deleting subnet: $subnet"
        aws ec2 delete-subnet --subnet-id $subnet || true
    done

    # Detach and delete internet gateway
    IGW_ID=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=${VPC_ID}" --query 'InternetGateways[0].InternetGatewayId' --output text)
    if [ "$IGW_ID" != "None" ] && [ "$IGW_ID" != "null" ]; then
        echo "Deleting Internet Gateway: ${IGW_ID}"
        aws ec2 detach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID
        aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID
    fi

    # Finally delete the VPC
    echo "Deleting VPC: ${VPC_ID}"
    aws ec2 delete-vpc --vpc-id $VPC_ID || true
else
    echo "No VPC found, skipping VPC resource cleanup..."
fi

echo "Cleanup completed successfully!"
