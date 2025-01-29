#!/bin/bash

check_resource() {
    local resource_name=$1
    local command=$2
    
    echo "----------------------------------------"
    echo "Checking $resource_name..."
    echo "----------------------------------------"
    eval $command
    echo ""
}

check_resource "EKS Clusters" "aws eks list-clusters"
check_resource "EC2 Instances" "aws ec2 describe-instances --query 'Reservations[].Instances[].{ID:InstanceId,State:State.Name,Name:Tags[?Key==\`Name\`].Value|[0]}'"
check_resource "Security Groups" "aws ec2 describe-security-groups --query 'SecurityGroups[?GroupName!=\`default\`]'"
check_resource "Load Balancers" "aws ec2 describe-load-balancers"
check_resource "Target Groups" "aws ec2 describe-target-groups"
check_resource "VPCs" "aws ec2 describe-vpcs --query 'Vpcs[?IsDefault==\`false\`]'"
check_resource "Subnets" "aws ec2 describe-subnets --query 'Subnets[*].{ID:SubnetId,VPC:VpcId,CIDR:CidrBlock}'"
check_resource "NAT Gateways" "aws ec2 describe-nat-gateways"
check_resource "Internet Gateways" "aws ec2 describe-internet-gateways"
check_resource "ECR Repositories" "aws ecr describe-repositories"
check_resource "IAM Roles" "aws iam list-roles | grep -i ecabs"
check_resource "IAM Policies" "aws iam list-policies --scope Local | grep -i ecabs"
check_resource "CloudFormation Stacks" "aws cloudformation list-stacks --query 'StackSummaries[?StackStatus!=\`DELETE_COMPLETE\`]'"
check_resource "EBS Volumes" "aws ec2 describe-volumes --query 'Volumes[?State!=\`available\`]'"
check_resource "Auto Scaling Groups" "aws autoscaling describe-auto-scaling-groups"
check_resource "Network Interfaces" "aws ec2 describe-network-interfaces"