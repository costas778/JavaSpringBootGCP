#!/bin/bash

# Create setup.sh
cat > setup.sh << 'EOL'
#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Creating eCabs project structure...${NC}"

# Create main project directories
mkdir -p {kubernetes/{rabbitmq,configmaps,secrets,producer,consumer},terraform/{environments/dev,modules/{eks,networking}},docker/{producer,consumer}}

# Create Kubernetes manifests
echo -e "${GREEN}Creating Kubernetes manifests...${NC}"

# RabbitMQ deployment
cat > kubernetes/rabbitmq/deployment.yaml << 'EOF'
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
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
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

# RabbitMQ service
cat > kubernetes/rabbitmq/service.yaml << 'EOF'
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

# ConfigMap for application configuration
cat > kubernetes/configmaps/app-config.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  RABBITMQ_HOST: "rabbitmq-service"
  RABBITMQ_PORT: "5672"
  SPRING_PROFILES_ACTIVE: "prod"
EOF

# Secrets for sensitive data
cat > kubernetes/secrets/app-secrets.yaml << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
type: Opaque
data:
  RABBITMQ_USERNAME: YWRtaW4=
  RABBITMQ_PASSWORD: cGFzc3dvcmQ=
EOF

# Producer deployment
cat > kubernetes/producer/deployment.yaml << 'EOF'
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
        image: ${ECR_REGISTRY}/booking-producer:latest
        ports:
        - containerPort: 8080
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
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
        envFrom:
        - configMapRef:
            name: app-config
        - secretRef:
            name: app-secrets
EOF

# Producer HPA
cat > kubernetes/producer/hpa.yaml << 'EOF'
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: booking-producer-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: booking-producer
  minReplicas: 2
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 80
EOF

# Producer service
cat > kubernetes/producer/service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: booking-producer-service
spec:
  selector:
    app: booking-producer
  ports:
  - port: 80
    targetPort: 8080
  type: ClusterIP
EOF

# Producer ingress
cat > kubernetes/producer/ingress.yaml << 'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: booking-producer-ingress
  annotations:
    kubernetes.io/ingress.class: "nginx"
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
spec:
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: booking-producer-service
            port:
              number: 80
EOF

# Consumer deployment
cat > kubernetes/consumer/deployment.yaml << 'EOF'
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
        image: ${ECR_REGISTRY}/booking-consumer:latest
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
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
        envFrom:
        - configMapRef:
            name: app-config
        - secretRef:
            name: app-secrets
EOF

# Consumer HPA
cat > kubernetes/consumer/hpa.yaml << 'EOF'
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: booking-consumer-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: booking-consumer
  minReplicas: 2
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 80
EOF

# Network Policy
cat > kubernetes/network-policies.yaml << 'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: rabbitmq-network-policy
spec:
  podSelector:
    matchLabels:
      app: rabbitmq
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: booking-producer
    - podSelector:
        matchLabels:
          app: booking-consumer
    ports:
    - protocol: TCP
      port: 5672
EOF

# Create Terraform files
echo -e "${GREEN}Creating Terraform configurations...${NC}"

# Variables file
cat > terraform/environments/dev/variables.tf << 'EOF'
variable "aws_region" {
  default = "eu-west-1"
}

variable "environment" {
  default = "dev"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "private_subnets" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "public_subnets" {
  type    = list(string)
  default = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}
EOF

# Main Terraform configuration
cat > terraform/environments/dev/main.tf << 'EOF'
provider "aws" {
  region = var.aws_region
}

module "networking" {
  source = "../../modules/networking"
  
  environment     = var.environment
  vpc_cidr        = var.vpc_cidr
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets
}

module "eks" {
  source = "../../modules/eks"
  
  environment         = var.environment
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  public_subnet_ids  = module.networking.public_subnet_ids
}
EOF

# Networking module
cat > terraform/modules/networking/main.tf << 'EOF'
data "aws_availability_zones" "available" {}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.environment}-vpc"
    Environment = var.environment
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnets)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name        = "${var.environment}-private-subnet-${count.index + 1}"
    Environment = var.environment
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_subnet" "public" {
  count             = length(var.public_subnets)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnets[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name        = "${var.environment}-public-subnet-${count.index + 1}"
    Environment = var.environment
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.environment}-igw"
    Environment = var.environment
  }
}

resource "aws_nat_gateway" "main" {
  count         = length(var.public_subnets)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name        = "${var.environment}-nat-${count.index + 1}"
    Environment = var.environment
  }
}

resource "aws_eip" "nat" {
  count = length(var.public_subnets)
  vpc   = true

  tags = {
    Name        = "${var.environment}-eip-${count.index + 1}"
    Environment = var.environment
  }
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}
EOF

# EKS module
cat > terraform/modules/eks/main.tf << 'EOF'
resource "aws_eks_cluster" "main" {
  name     = "${var.environment}-cluster"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.27"

  vpc_config {
    subnet_ids              = concat(var.private_subnet_ids, var.public_subnet_ids)
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]
}

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.environment}-node-group"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = var.private_subnet_ids

  scaling_config {
    desired_size = 2
    max_size     = 4
    min_size     = 1
  }

  instance_types = ["t3.medium"]

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_policy
  ]
}

resource "aws_iam_role" "eks_cluster" {
  name = "${var.environment}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role" "eks_node" {
  name = "${var.environment}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_iam_role_policy_attachment" "eks_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node.name
}
EOF

# Create Dockerfiles
echo -e "${GREEN}Creating Dockerfiles...${NC}"

cat > docker/producer/Dockerfile << 'EOF'
FROM openjdk:11-jre-slim
WORKDIR /app
COPY booking-producer-service/target/*.jar app.jar
ENTRYPOINT ["java","-jar","app.jar"]
EOF

cat > docker/consumer/Dockerfile << 'EOF'
FROM openjdk:11-jre-slim
WORKDIR /app
COPY booking-consumer-service/target/*.jar app.jar
ENTRYPOINT ["java","-jar","app.jar"]
EOF

# Create deployment script
cat > deploy.sh << 'EOF'
#!/bin/bash

# Set AWS credentials
if [ -z "${AWS_ACCESS_KEY_ID}" ] || [ -z "${AWS_SECRET_ACCESS_KEY}" ]; then
  echo "Please set AWS credentials first"

  EOL

# Make the script executable
chmod +x setup.sh

echo "Setup script created! Run ./setup.sh to create the project structure."

