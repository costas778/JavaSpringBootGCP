#!/bin/bash
export AWS_REGION=us-east-1

# Exit on any error
set -e

# Set variables
PROJECT_ROOT=$(pwd)
AWS_REGION=${AWS_REGION:-"us-east-1"}
ENVIRONMENT=${ENVIRONMENT:-"dev"}
CLUSTER_NAME="${ENVIRONMENT}-ecabs-cluster"
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

###########################################
# Directory Structure Creation
###########################################
create_directory_structure() {
    echo "Creating directory structure..."
    mkdir -p terraform/{environments/$ENVIRONMENT,modules/{eks,networking}}
    mkdir -p kubernetes/{rabbitmq,configmaps,secrets,producer,consumer}
    mkdir -p docker/{producer,consumer}
}

###########################################
# Terraform Module Creation
###########################################
create_terraform_modules() {
    echo "Creating Terraform module files..."
   
    # Create EKS module
    cat > terraform/modules/eks/main.tf <<EOF
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.27"

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  # Add these lines for public access
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  eks_managed_node_groups = {
    default = {
      min_size     = 2
      max_size     = 3
      desired_size = 2

      instance_types = ["t3.medium"]
    }
  }
}
EOF

    # Create EKS variables
    cat > terraform/modules/eks/variables.tf <<EOF
variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where the EKS cluster will be created"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs where the EKS cluster will be created"
}
EOF

    # Create networking module
    cat > terraform/modules/networking/main.tf <<EOF
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  # Add version constraint here
  version = "~> 4.0" 

  name = "\${var.environment}-vpc"
  cidr = var.vpc_cidr

  azs             = data.aws_availability_zones.available.names
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = {
    Environment = var.environment
    "kubernetes.io/cluster/\${var.cluster_name}" = "shared"
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnets" {
  value = module.vpc.private_subnets
}

output "public_subnets" {
  value = module.vpc.public_subnets
}
EOF

    # Create networking variables
    cat > terraform/modules/networking/variables.tf <<EOF
variable "environment" {
  type        = string
  description = "Environment name"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR block"
}

variable "private_subnets" {
  type        = list(string)
  description = "Private subnet CIDR blocks"
}

variable "public_subnets" {
  type        = list(string)
  description = "Public subnet CIDR blocks"
}

variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster"
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
provider "aws" {
  region = var.aws_region
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.57.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}
EOF

    # Create main.tf
    cat > terraform/environments/$ENVIRONMENT/main.tf <<EOF
module "networking" {
  source = "../../modules/networking"

  environment     = var.environment
  vpc_cidr        = var.vpc_cidr
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets
  cluster_name    = local.cluster_name
}

module "eks" {
  source = "../../modules/eks"

  cluster_name = local.cluster_name
  vpc_id       = module.networking.vpc_id
  subnet_ids   = module.networking.private_subnets
}

locals {
  cluster_name = "${ENVIRONMENT}-ecabs-cluster"
}
EOF

    # Create variables.tf
    cat > terraform/environments/$ENVIRONMENT/variables.tf <<EOF
variable "aws_region" {
  description = "AWS region"
  default     = "$AWS_REGION"
}

variable "environment" {
  description = "Environment name"
  default     = "$ENVIRONMENT"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  default     = "10.0.0.0/16"
}

variable "private_subnets" {
  description = "Private subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "public_subnets" {
  description = "Public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}
EOF
}

###########################################
# Kubernetes Manifests Creation
###########################################
create_kubernetes_manifests() {
    echo "Creating Kubernetes manifests..."
   
    # Create producer deployment and service
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
        image: ${AWS_ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com/booking-producer:latest
        envFrom:
        - configMapRef:
            name: app-config
        ports:
        - containerPort: 8080
        livenessProbe:
          httpGet:
            path: /actuator/health
            port: 8080
          initialDelaySeconds: 60
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /actuator/health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        resources:
          limits:
            cpu: "500m"
            memory: "512Mi"
          requests:
            cpu: "200m"
            memory: "256Mi"
EOF

    cat > kubernetes/producer/service.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: booking-producer-service
spec:
  type: LoadBalancer
  selector:
    app: booking-producer
  ports:
  - port: 80
    targetPort: 8080
EOF

    # Create consumer deployment
    cat > kubernetes/consumer/deployment.yaml <<EOF
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
        image: ${AWS_ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com/booking-consumer:latest
        envFrom:
        - configMapRef:
            name: app-config
        livenessProbe:
          httpGet:
            path: /actuator/health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /actuator/health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        resources:
          limits:
            cpu: "500m"
            memory: "512Mi"
          requests:
            cpu: "200m"
            memory: "256Mi"
EOF

    # Create RabbitMQ deployment and service
    cat > kubernetes/rabbitmq/deployment.yaml <<EOF
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
        - containerPort: 5672  # AMQP port
        - containerPort: 15672 # Management port
        resources:
          limits:
            cpu: "500m"
            memory: "512Mi"
          requests:
            cpu: "200m"
            memory: "256Mi"
        livenessProbe:
          tcpSocket:
            port: 5672
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          tcpSocket:
            port: 5672
          initialDelaySeconds: 30
          periodSeconds: 10
EOF

    cat > kubernetes/rabbitmq/service.yaml <<EOF
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
  type: ClusterIP
EOF

    # Create ConfigMap
    cat > kubernetes/configmaps/app-config.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  # RabbitMQ Configuration
  SPRING_RABBITMQ_HOST: "rabbitmq"
  SPRING_RABBITMQ_PORT: "5672"
  SPRING_RABBITMQ_USERNAME: "guest"
  SPRING_RABBITMQ_PASSWORD: "guest"
 
  # Spring Boot Configuration
  SPRING_PROFILES_ACTIVE: "prod"
  SERVER_PORT: "8080"
 
  # Management Endpoints Configuration
  MANAGEMENT_ENDPOINTS_WEB_EXPOSURE_INCLUDE: "health,info,metrics"
  MANAGEMENT_ENDPOINT_HEALTH_SHOW_DETAILS: "always"
 
  # H2 Database Configuration
  SPRING_DATASOURCE_URL: "jdbc:h2:mem:bookingdb"
  SPRING_DATASOURCE_DRIVERCLASSNAME: "org.h2.Driver"
  SPRING_DATASOURCE_USERNAME: "sa"
  SPRING_DATASOURCE_PASSWORD: ""
  SPRING_JPA_DATABASE_PLATFORM: "org.hibernate.dialect.H2Dialect"
  SPRING_H2_CONSOLE_ENABLED: "false"
  SPRING_JPA_HIBERNATE_DDL_AUTO: "update"
  SPRING_JPA_SHOW_SQL: "false"
 
  # Additional Spring Boot Configuration
  SPRING_APPLICATION_NAME: "booking-service"
  LOGGING_LEVEL_ROOT: "INFO"
  LOGGING_LEVEL_COM_ECABS: "DEBUG"
EOF
}

###########################################
# Docker Configuration
###########################################
# Create Dockerfile for producer
create_producer_dockerfile() {
    cat > docker/producer/Dockerfile <<EOF
FROM openjdk:11-jre-slim
WORKDIR /app
COPY booking-producer-service/target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java","-jar","app.jar"]
EOF
}

# Create Dockerfile for consumer
create_consumer_dockerfile() {
    cat > docker/consumer/Dockerfile <<EOF
FROM openjdk:11-jre-slim
WORKDIR /app
COPY booking-consumer-service/target/*.jar app.jar
ENTRYPOINT ["java","-jar","app.jar"]
EOF
}

###########################################
# Build and Deploy
###########################################
create_and_push_images() {
    echo "Building Spring Boot applications..."
    # Build Maven projects first
    mvn clean package -f booking-producer-service/pom.xml
    mvn clean package -f booking-consumer-service/pom.xml

    echo "Setting up ECR repositories..."
    # Create ECR repositories if they don't exist
    for repo in booking-producer booking-consumer; do
        if ! aws ecr describe-repositories --repository-names "${repo}" --region ${AWS_REGION} 2>/dev/null; then
            echo "Creating ECR repository: ${repo}"
            aws ecr create-repository --repository-name "${repo}" --region ${AWS_REGION}
        fi
    done

    # Get ECR login token
    aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com

    echo "Building and pushing Docker images..."
    # Build and push Docker images
    for service in producer consumer; do
        echo "Building and pushing ${service} image..."
        docker build -t booking-${service}:latest -f docker/${service}/Dockerfile .
        docker tag booking-${service}:latest ${AWS_ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com/booking-${service}:latest
        docker push ${AWS_ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com/booking-${service}:latest
    done
}

# Deploy infrastructure and applications
deploy_infrastructure() {
    echo "Deploying infrastructure..."
    cd terraform/environments/$ENVIRONMENT
    terraform init
    terraform apply -auto-approve

    echo "Configuring kubectl..."
    aws eks update-kubeconfig --name $CLUSTER_NAME --region $AWS_REGION

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
    create_directory_structure
    create_terraform_modules
    create_terraform_files
    create_kubernetes_manifests
    create_producer_dockerfile
    create_consumer_dockerfile
    create_and_push_images
    deploy_infrastructure
}

# Run main function
main
