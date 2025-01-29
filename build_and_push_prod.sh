#!/bin/bash

# Enable debug output
set -x

# Variables
IMAGE_NAME="booking-producer"  # Changed from booking-consumer
ECR_REPO="961109809677.dkr.ecr.us-east-1.amazonaws.com"
TAG="latest"
REGION="us-east-1"

# Print current directory
echo "Current directory: $(pwd)"

PROJECT_ROOT=$(pwd)
echo "Project root: $PROJECT_ROOT"

# Verify directories exist
echo "Checking directories..."
ls -la "$PROJECT_ROOT"
ls -la "$PROJECT_ROOT/booking-producer-service"  # Changed from booking-consumer-service

# Authenticate with ECR
echo "Authenticating with ECR..."
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_REPO

# Build the JAR file
echo "Building JAR file..."
cd "$PROJECT_ROOT/booking-producer-service" || exit 1  # Changed from booking-consumer-service
./mvnw clean package -DskipTests

# Build the Docker image from project root
echo "Building Docker image..."
cd "$PROJECT_ROOT" || exit 1
docker build -t $IMAGE_NAME -f "$PROJECT_ROOT/docker/producer/Dockerfile" .  # Changed from consumer to producer

# Tag the image for ECR
docker tag $IMAGE_NAME $ECR_REPO/$IMAGE_NAME:$TAG

# Push the image to ECR
docker push $ECR_REPO/$IMAGE_NAME:$TAG
