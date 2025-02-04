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
    echo "Creating GCP-specific directory structure..."
    mkdir -p gcp/terraform/{environments/$ENVIRONMENT,modules/{gke,networking}}
    mkdir -p gcp/kubernetes/{rabbitmq,configmaps,secrets,producer,consumer}
    mkdir -p gcp/docker/{producer,consumer}
}

###########################################
# Terraform Module Creation
###########################################
create_terraform_modules() {
    echo "Creating Terraform module files..."
   
    # Create GKE module
    mkdir -p gcp/terraform/modules/gke
    cat > gcp/terraform/modules/gke/main.tf << 'EOF'
resource "google_container_cluster" "primary" {
  name               = var.cluster_name
  location           = var.zone
  network           = var.network
  subnetwork        = var.subnetwork
  project           = var.project_id
 
  remove_default_node_pool = true
  initial_node_count       = 1

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
}

resource "google_container_node_pool" "primary_nodes" {
  name       = "${var.cluster_name}-node-pool"
  location   = var.zone
  cluster    = google_container_cluster.primary.name
  project    = var.project_id
 
  node_count = 2

  node_config {
    machine_type = "e2-medium"
    disk_size_gb = 50
    disk_type    = "pd-standard"
    image_type   = "COS_CONTAINERD"

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = {
      environment = var.environment
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }
 
    # Add lifecycle block to handle updates
  lifecycle {
    ignore_changes = [
      node_config[0].image_type,
      node_config[0].labels,
      node_config[0].taint,
      node_config[0].workload_metadata_config
    ]
  }

}
EOF

    # Create GKE module variables
    cat > gcp/terraform/modules/gke/variables.tf << 'EOF'
variable "cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
}

variable "zone" {
  description = "GCP zone"
  type        = string
}

variable "network" {
  description = "VPC network name"
  type        = string
}

variable "subnetwork" {
  description = "Subnet name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}
EOF

    # Create networking module
    mkdir -p gcp/terraform/modules/networking
    cat > gcp/terraform/modules/networking/main.tf << 'EOF'
resource "google_compute_network" "vpc" {
  name                    = "${var.environment}-vpc"
  auto_create_subnetworks = false
  project                = var.project_id

}

resource "google_compute_subnetwork" "subnet" {
  name          = "${var.environment}-subnet"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc.id
  project       = var.project_id
}

resource "google_compute_firewall" "internal" {
  name    = "${var.environment}-allow-internal"
  network = google_compute_network.vpc.name
  project = var.project_id


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

    # Create networking module variables
    cat > gcp/terraform/modules/networking/variables.tf << 'EOF'
variable "environment" {
  description = "Environment name"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "subnet_cidr" {
  description = "Subnet CIDR block"
  type        = string
}

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}
EOF

    # Create networking module outputs
    cat > gcp/terraform/modules/networking/outputs.tf << 'EOF'
output "vpc_name" {
  value = google_compute_network.vpc.name
}

output "subnet_name" {
  value = google_compute_subnetwork.subnet.name
}

output "vpc_id" {
  value = google_compute_network.vpc.id
}
EOF
}


###########################################
# Terraform Environment Files
###########################################
create_terraform_files() {
    echo "Creating Terraform files..."
   
    mkdir -p gcp/terraform/environments/$ENVIRONMENT
   
    # Create main.tf
    cat > gcp/terraform/environments/$ENVIRONMENT/main.tf << 'EOF'
module "networking" {
  source = "../../modules/networking"

  environment = var.environment
  region     = var.region
  subnet_cidr = var.subnet_cidr
  project_id  = var.project_id
}

module "gke" {
  source = "../../modules/gke"

  cluster_name = "${var.environment}-ecabs-cluster"
  zone         = var.zone
  network      = module.networking.vpc_name
  subnetwork   = module.networking.subnet_name
  environment  = var.environment
  project_id   = var.project_id


  depends_on = [module.networking]
}
EOF

    # Create provider.tf
    cat > gcp/terraform/environments/$ENVIRONMENT/provider.tf << 'EOF'
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
    cat > gcp/terraform/environments/$ENVIRONMENT/variables.tf << 'EOF'
variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "us-central1-a"
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "subnet_cidr" {
  description = "Subnet CIDR block"
  type        = string
  default     = "10.0.0.0/24"
}
EOF

    # Update PROJECT_ID and create terraform.tfvars
    PROJECT_ID="playground-s-11-55814813"  # Use the correct project ID
   
    # Create terraform.tfvars with the correct project ID
    cat > gcp/terraform/environments/$ENVIRONMENT/terraform.tfvars << EOF
project_id = "$PROJECT_ID"
region     = "$REGION"
zone       = "$ZONE"
environment = "$ENVIRONMENT"
EOF
}


###########################################
# Kubernetes Manifests Creation
###########################################
create_kubernetes_manifests() {
    echo "Creating Kubernetes manifests..."
   
    # Create RabbitMQ deployment and service
    mkdir -p gcp/kubernetes/rabbitmq
    cat > gcp/kubernetes/rabbitmq/deployment.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rabbitmq
spec:
  replicas: 1
  selector:
    matchLabels:
      app: rabbitmq
  template:
    metadata:
      labels:
        app: rabbitmq
    spec:
      containers:
      - name: rabbitmq
        image: rabbitmq:3-management
        ports:
        - containerPort: 5672
        - containerPort: 15672
---
apiVersion: v1
kind: Service
metadata:
  name: rabbitmq-service
spec:
  selector:
    app: rabbitmq
  ports:
  - name: amqp
    port: 5672
    targetPort: 5672
  - name: management
    port: 15672
    targetPort: 15672
EOF

    # Create producer deployment
    mkdir -p gcp/kubernetes/producer
    cat > gcp/kubernetes/producer/deployment.yaml << EOF
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
---
apiVersion: v1
kind: Service
metadata:
  name: booking-producer-service
spec:
  type: LoadBalancer
  selector:
    app: booking-producer
  ports:
  - port: 8080
    targetPort: 8080
EOF

    # Create consumer deployment
    mkdir -p gcp/kubernetes/consumer
    cat > gcp/kubernetes/consumer/deployment.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: booking-consumer
spec:
  replicas: 2
  selector:
    matchLabels:
      app: booking-consumer
  template:
    metadata:
      labels:
        app: booking-consumer
    spec:
      containers:
      - name: booking-consumer
        image: gcr.io/${PROJECT_ID}/booking-consumer:latest
        envFrom:
        - configMapRef:
            name: app-config
EOF
}

###########################################
# Docker File Creation Functions
###########################################
create_producer_dockerfile() {
    mkdir -p gcp/docker/producer
    cat > gcp/docker/producer/Dockerfile << EOF
FROM openjdk:11-jre-slim
WORKDIR /app
COPY booking-producer-service/target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java","-jar","app.jar"]
EOF
}

create_consumer_dockerfile() {
    mkdir -p gcp/docker/consumer
    cat > gcp/docker/consumer/Dockerfile << EOF
FROM openjdk:11-jre-slim
WORKDIR /app
COPY booking-consumer-service/target/*.jar app.jar
ENTRYPOINT ["java","-jar","app.jar"]
EOF
}

create_docker_files() {
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

    # Verify project exists and is active before proceeding
    PROJECT_STATUS=$(gcloud projects describe $PROJECT_ID --format="value(lifecycleState)" 2>/dev/null || echo "NONEXISTENT")
    if [ "$PROJECT_STATUS" != "ACTIVE" ]; then
        echo "Error: Project $PROJECT_ID is not active or has been deleted."
        echo "Please create a new project and update PROJECT_ID in the script."
        exit 1
    fi    # <-- Added missing 'fi'

    # Check if Docker daemon is running
    if ! docker info >/dev/null 2>&1; then
        echo "Docker daemon is not running. Starting Docker..."
        sudo service docker start
        sleep 5
    fi

    echo "Checking and accepting GCP Terms of Service..."
    # We can't programmatically accept ToS, so we need to inform the user
    echo "Please visit https://console.developers.google.com/terms/cloud to accept the Google Cloud Terms of Service"
    echo "After accepting the Terms of Service, press any key to continue..."
    read -n 1 -s

    echo "Enabling required GCP APIs..."
    gcloud services enable artifactregistry.googleapis.com
    gcloud services enable containerregistry.googleapis.com

    echo "Setting up Container Registry..."
    gcloud auth configure-docker --quiet

    # Install buildx if missing
    if [ ! -f "/usr/local/lib/docker/cli-plugins/docker-buildx" ]; then
        echo "Installing Docker buildx..."
        sudo mkdir -p /usr/local/lib/docker/cli-plugins
        sudo curl -SL https://github.com/docker/buildx/releases/download/v0.12.1/buildx-v0.12.1.linux-amd64 -o /usr/local/lib/docker/cli-plugins/docker-buildx
        sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx
    fi

    echo "Building and pushing Docker images..."
    for service in producer consumer; do
        echo "Building and pushing ${service} image..."
        if [ ! -f "gcp/docker/${service}/Dockerfile" ]; then
            echo "Error: Dockerfile not found for ${service}"
            exit 1
        fi
        docker build -t gcr.io/${PROJECT_ID}/booking-${service}:latest -f gcp/docker/${service}/Dockerfile .
        if [ $? -eq 0 ]; then
            docker push gcr.io/${PROJECT_ID}/booking-${service}:latest
        else
            echo "Error building ${service} image"
            exit 1
        fi
    done
}




deploy_infrastructure() {
    # Store the project root directory
    PROJECT_ROOT=$(pwd)
    echo "Project root directory: $PROJECT_ROOT"

    # First, ensure we're using the correct project
    echo "Setting up project configuration..."
    PROJECT_ID="playground-s-11-55814813"  # Use the correct project ID
    gcloud config set project $PROJECT_ID

    # Ensure the directory structure exists
    echo "Creating directory structure if it doesn't exist..."
    mkdir -p gcp/terraform/environments/$ENVIRONMENT

    # Debug: Print current project and terraform.tfvars content
    echo "Current Project ID: $PROJECT_ID"
    echo "Current terraform.tfvars content:"
    cat gcp/terraform/environments/$ENVIRONMENT/terraform.tfvars || echo "terraform.tfvars not found"

    # Update terraform.tfvars with correct project ID
    echo "Updating terraform.tfvars with correct project ID..."
    sed -i "s/project_id = .*/project_id = \"$PROJECT_ID\"/" gcp/terraform/environments/$ENVIRONMENT/terraform.tfvars

    # Ensure all required directories and files exist
    echo "Checking if all required files exist..."
    if [ ! -f "gcp/terraform/environments/$ENVIRONMENT/main.tf" ]; then
        echo "Error: main.tf not found. Running create_terraform_files..."
        create_terraform_files
    fi

    if [ ! -d "gcp/terraform/modules/gke" ]; then
        echo "Error: GKE module not found. Running create_terraform_modules..."
        create_terraform_modules
    fi

    # Clean any existing state
    echo "Cleaning existing Terraform state..."
    cd "$PROJECT_ROOT/gcp/terraform/environments/$ENVIRONMENT" || exit
    rm -rf .terraform
    rm -f .terraform.lock.hcl
    rm -f terraform.tfstate*

    echo "Enabling required GCP APIs..."
    gcloud services enable container.googleapis.com
    gcloud services enable compute.googleapis.com
    gcloud services enable cloudresourcemanager.googleapis.com
    gcloud services enable iam.googleapis.com
   
    # Wait a bit for API enablement to propagate
    sleep 10

    echo "Installing GKE auth plugin..."
    sudo apt-get install google-cloud-sdk-gke-gcloud-auth-plugin

    echo "Setting up application default credentials..."
    gcloud auth application-default login

    # Verify project and authentication
    echo "Verifying project configuration..."
    gcloud config list project
    gcloud auth list

    # Set the compute zone
    gcloud config set compute/zone $ZONE

    echo "Deploying infrastructure..."
    terraform init
    terraform apply -auto-approve

    echo "Configuring kubectl..."
    gcloud container clusters get-credentials $CLUSTER_NAME --zone $ZONE

    echo "Creating ConfigMap..."
    kubectl create configmap app-config \
        --from-literal=SPRING_RABBITMQ_HOST=rabbitmq-service \
        --from-literal=SPRING_RABBITMQ_PORT=5672 \
        --from-literal=SPRING_RABBITMQ_USERNAME=guest \
        --from-literal=SPRING_RABBITMQ_PASSWORD=guest \
        -n default

    # Return to project root before applying Kubernetes resources
    cd "$PROJECT_ROOT" || exit
    
    echo "Deploying Kubernetes resources..."
    kubectl apply -f "$PROJECT_ROOT/gcp/kubernetes/rabbitmq/"
    kubectl apply -f "$PROJECT_ROOT/gcp/kubernetes/producer/"
    kubectl apply -f "$PROJECT_ROOT/gcp/kubernetes/consumer/"
}




###########################################
# Main Execution
###########################################
main() {
    # Ensure gcloud is authenticated and project is set
    if ! gcloud auth list --filter=status:ACTIVE --format="get(account)" > /dev/null; then
        echo "Please run 'gcloud auth login' first"
        exit 1
    fi

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