#!/bin/bash

# Enable debug output
set -x

# Variables
IMAGE_NAME="booking-consumer"
ECR_REPO="961109809677.dkr.ecr.us-east-1.amazonaws.com"
TAG="latest"
REGION="us-east-1"

# Print current directory
echo "Current directory: $(pwd)"

# Since we're already in the JavaSpringBoot directory, that's our PROJECT_ROOT
PROJECT_ROOT=$(pwd)
echo "Project root: $PROJECT_ROOT"

# Verify directories exist
echo "Checking directories..."
ls -la "$PROJECT_ROOT"
ls -la "$PROJECT_ROOT/booking-consumer-service"

# Authenticate with ECR
echo "Authenticating with ECR..."
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_REPO

# Build the JAR file
echo "Building JAR file..."
cd "$PROJECT_ROOT/booking-consumer-service" || exit 1
./mvnw clean package -DskipTests

# Build the Docker image from project root
echo "Building Docker image..."
cd "$PROJECT_ROOT" || exit 1
docker build -t $IMAGE_NAME -f "$PROJECT_ROOT/docker/consumer/Dockerfile" .

# Tag the image for ECR
docker tag $IMAGE_NAME $ECR_REPO/$IMAGE_NAME:$TAG

# Push the image to ECR
docker push $ECR_REPO/$IMAGE_NAME:$TAG
