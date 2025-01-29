#!/bin/bash

# Exit on any error
set -e

# Set variables
PROJECT_ROOT=$(pwd)
PROJECT_ID=$(gcloud config get-value project)
REGION=${REGION:-"us-central1"}
ZONE=${ZONE:-"us-central1-a"}
ENVIRONMENT=${ENVIRONMENT:-"dev"}
CLUSTER_NAME="${ENVIRONMENT}-ecabs-cluster"

###########################################
# Directory Structure Creation
###########################################
create_directory_structure() {
    echo "Creating directory structure..."
    mkdir -p terraform/{environments/$ENVIRONMENT,modules/{gke,networking}}
    mkdir -p kubernetes/{rabbitmq,configmaps,secrets,producer,consumer}
    mkdir -p docker/{producer,consumer}
}

###########################################
# Terraform Module Creation
###########################################
create_terraform_modules() {
    echo "Creating Terraform module files..."
   
    # Create GKE module
    cat > terraform/modules/gke/main.tf <<EOF
resource "google_container_cluster" "primary" {
  name               = var.cluster_name
  location           = var.zone
  network           = var.network
  subnetwork        = var.subnetwork
  
  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count       = 1
}

resource "google_container_node_pool" "primary_nodes" {
  name       = "\${var.cluster_name}-node-pool"
  location   = var.zone
  cluster    = google_container_cluster.primary.name
  
  node_count = 2

  node_config {
    machine_type = "e2-medium"

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}
EOF

    # Create networking module
    cat > terraform/modules/networking/main.tf <<EOF
resource "google_compute_network" "vpc" {
  name                    = "\${var.environment}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = "\${var.environment}-subnet"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc.id
}

# Allow internal communication
resource "google_compute_firewall" "internal" {
  name    = "\${var.environment}-allow-internal"
  network = google_compute_network.vpc.name

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  source_ranges = [var.subnet_cidr]
}
EOF
}

###########################################
# Terraform Environment Files
###########################################
create_terraform_files() {
    echo "Creating Terraform files..."
   
    # Create provider.tf
    cat > terraform/environments/$ENVIRONMENT/provider.tf <<EOF
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}
EOF

    # Create variables.tf
    cat > terraform/environments/$ENVIRONMENT/variables.tf <<EOF
variable "project_id" {
  description = "GCP Project ID"
}

variable "region" {
  description = "GCP region"
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone"
  default     = "us-central1-a"
}

variable "environment" {
  description = "Environment name"
  default     = "$ENVIRONMENT"
}

variable "subnet_cidr" {
  description = "Subnet CIDR block"
  default     = "10.0.0.0/24"
}
EOF
}

###########################################
# Kubernetes Manifests Creation
###########################################
create_kubernetes_manifests() {
    # Similar to original but with GCP-specific image paths
    echo "Creating Kubernetes manifests..."
   
    # Create producer deployment
    cat > kubernetes/producer/deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: booking-producer
spec:
  replicas: 2
  selector:
    matchLabels:
      app: booking-producer
  template:
    metadata:
      labels:
        app: booking-producer
    spec:
      containers:
      - name: booking-producer
        image: gcr.io/${PROJECT_ID}/booking-producer:latest
        envFrom:
        - configMapRef:
            name: app-config
        ports:
        - containerPort: 8080
EOF

    # Similar pattern for consumer and RabbitMQ deployments
    # [Previous Kubernetes manifests remain similar, just changing image paths to GCR]
}

###########################################
# Docker Configuration
###########################################
create_docker_files() {
    # Dockerfiles remain the same as they're platform-agnostic
    create_producer_dockerfile
    create_consumer_dockerfile
}

###########################################
# Build and Deploy
###########################################
create_and_push_images() {
    echo "Building Spring Boot applications..."
    mvn clean package -f booking-producer-service/pom.xml
    mvn clean package -f booking-consumer-service/pom.xml

    echo "Setting up Container Registry..."
    gcloud auth configure-docker

    echo "Building and pushing Docker images..."
    for service in producer consumer; do
        echo "Building and pushing ${service} image..."
        docker build -t gcr.io/${PROJECT_ID}/booking-${service}:latest -f docker/${service}/Dockerfile .
        docker push gcr.io/${PROJECT_ID}/booking-${service}:latest
    done
}

deploy_infrastructure() {
    echo "Deploying infrastructure..."
    cd terraform/environments/$ENVIRONMENT
    terraform init
    terraform apply -auto-approve

    echo "Configuring kubectl..."
    gcloud container clusters get-credentials $CLUSTER_NAME --zone $ZONE

    echo "Deploying Kubernetes resources..."
    kubectl apply -f $PROJECT_ROOT/kubernetes/configmaps/
    kubectl apply -f $PROJECT_ROOT/kubernetes/rabbitmq/
    kubectl apply -f $PROJECT_ROOT/kubernetes/producer/
    kubectl apply -f $PROJECT_ROOT/kubernetes/consumer/
}

###########################################
# Main Execution
###########################################
main() {
    # Ensure gcloud is authenticated and project is set
    if ! gcloud auth list --filter=status:ACTIVE --format="get(account)" > /dev/null; then
        echo "Please run 'gcloud auth login' first"
        exit 1
    }

    create_directory_structure
    create_terraform_modules
    create_terraform_files
    create_kubernetes_manifests
    create_docker_files
    create_and_push_images
    deploy_infrastructure
}

# Run main function
main
