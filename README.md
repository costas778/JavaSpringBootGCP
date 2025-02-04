

# JavaSpringBoot Modules deployed using a script in GCP!

## Assumptions
* I'm assuming fire and forget approach - API endpoint is publishing message and not waiting for confirmation, returning HTTP 202 Accepted because data will be processed later in consumer
* I'm assuming that client application is holding the state of booking, and is able to use generated UUIDs for PUT and DELETE operations

## Solution 

### Modules
* booking-producer-service - Implements API, basic validation and produce RabbitMQ messages.
* booking-consumer-service - Implements RabbitMQ listeners, "business logic" and persistence.
* booking-contract - contains DTO objects and Consts shared between both applications. This module is communication contract.

### Known issues/limitations
* error handling is limited to bare minimum - real world application should handle much more edge cases based on requirement
* only integration test provided - because application has almost no business logic I provided only integration tests. Test coverage is > 80%.
* faulty, not processed messages are redirected to Dead Letter Queue 

### Endpoints documentation
Endpoints documentation is generated on the fly in OpenAPI format by booking-producer-service
http://localhost:8080/swagger-ui/index.html


### Deployment of the script
![Alt Text](./jsb1.png)

Once you run either **setup_gcp_lite.sh** or **setup_gcp.sh** the following detailed Script Actions will occur:

**1. Directory Setup**
Creates directories for:
Terraform modules and environments.
Kubernetes manifests for RabbitMQ, producer, consumer, configmaps, and secrets.
Docker configurations for producer and consumer services.

**2. Terraform Modules**
GKE Module:
Provisions an GKE cluster with managed node groups.
Configures public/private endpoint access.
Specifies instance types and scaling properties for the node groups.
Networking Module:
Creates a VPC with public and private subnets.
Enables a single NAT gateway.
Tags resources appropriately for Kubernetes.

**3. Terraform Environment Configuration**
Environment-specific files include:
provider.tf: Defines GCP and Kubernetes providers.
main.tf: Integrates the networking and GKE modules.
variables.tf: Defines configurable parameters (e.g., region, subnets).

**4. Kubernetes Manifests**
Producer:
Defines a deployment and service for a booking-producer application.
Configures liveness/readiness probes, resource limits, and environment variables from a config map.
Consumer:
Similar to the producer, with its deployment and configuration.
RabbitMQ:
Configures RabbitMQ as a stateful service with liveness/readiness probes.
Exposes ports for AMQP and management interfaces.

**5. Docker**
Prepares directory structure for producer and consumer Dockerfiles, though no specific Dockerfiles are created in this script.
Purpose
This script is designed to bootstrap an environment for deploying an application involving:

**GCP Infrastructure:**
Sets up the networking and compute resources using Terraform.
Kubernetes Cluster:
Configures GKE for container orchestration.
Application Deployment:
Provides manifests for deploying services like RabbitMQ, producer, and consumer in Kubernetes.
Docker Preparation:
Sets up a directory for building Docker images for the applications.

## **Usage**
Pre-requisites (use the commands below to check if you have anything missing)
* Gloud CLI configured with access credentials: gcloud version
* **Obtain the Project ID by logining into the GCP console or using gcloud projects list in the cli**
* Kubernetes: **kubectl version --client**
* Terraform: **terraform version**
* Docker: **docker --version**
* GIT: **git --version**
* JAVA: **java -version**
* MAVEN: **mvn -version**

* If any of the above is missing
* **sudo apt update** (followed by)
* **sudo apt install** (application name)

* WSL2 environment (mine is Ubuntu)
* **cat /etc/os-release** 

## **Setup**
* From the Linux CLI: **git clone https://github.com/costas778/JavaSpringBootGCP.git**
* from the root of the folder structure locate the setup.sh, and use the following command: **chmond +x setup_gcp_lite.sh**
* **Place the project ID name in the script (i.e. lines 296 and 590 or there abouts)**
* Run **gcloud init** and select the following prompts:
*  **y**
*  https://accounts.google.com/o/oauth2/auth?response_type=code&client_id=32555940559.apps.googleusercontent.com&redirect_uri=http%3A%2F%2Flocalhost%3A8085%2F&scope=openid+https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fuserinfo.email+https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fcloud-platform+https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fappengine.admin+https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fsqlservice.login+https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fcompute+https%3A%2F%2Fwww.googleapis.com%2Fauth%2Faccounts.reauth&state=uoCyy4pj2Eoq9QVgbLMbtxUJRaMarz&access_type=offline&code_challenge=HD20UyFOqTcwnTXwfrcL0bqX4WnfnzvcZbal8GqwS2s&code_challenge_method=S256
*  NOTE: Click and follow the prompts
*  **[4] Enter a project ID** <project name - i.e. what you placed in lines 296 and 590 or there abouts>
*  **Do you want to configure a default Compute Region and Zone? (Y/n)?  y**
*  **Enter "list" at prompt to print choices fully. Please enter numeric choice or text value (must exactly match list item):  8**
  

* finally, type in he Linux CLI the following: **./setup_gcp_lite.sh**

*  GCP is different to AWS and requires you to respond to a few prompts running the script. Just copy the links presented in the CLI and respond to
*  the authentication prompts.

*  **NOTE: there is also a setup_gcp.sh script with enhanced features including: greater error handling, removing existing assets**
*  **of the software, dealing with Buildx issues, ensuring you have a supportive k8S client as well as when docker folders failed to be created.**
*  **I recommend using the setup_gcp.sh script if you run into issues using the setup_gcp_lite.sh.**



* You should get the following:


![Alt Text](./jsb2.png)

## **Testing**

### Check the pods
  
* **kubectl get pods -w**
  
* NAME                                READY   STATUS    RESTARTS   AGE
* booking-consumer-6d9f74974-84xlw    1/1     Running   0          12h
* booking-consumer-6d9f74974-slf9r    1/1     Running   0          12h
* booking-producer-845b699bdd-56qlm   1/1     Running   0          8h
* booking-producer-845b699bdd-j7s6l   1/1     Running   0          8h
* rabbitmq-5cfd974bf6-zd8xm           1/1     Running   0          33h

![Alt Text](./jsb4.png)

### Check service types
kubectl get svc -o wide

### Check ConfigMaps
kubectl get configmaps

### Check environment variables in deployments
kubectl get deployments -o yaml

## **Troubleshooting Commands**

### 1. containers that keep crashing and restarting
**kubectl get pods -w**
* NAME                                READY   STATUS    RESTARTS      AGE
* booking-consumer-54598b877d-7h7mf   0/1     Running   1 (14s ago)   66s
* booking-consumer-54598b877d-hmbdh   0/1     Running   1 (15s ago)   66s
* booking-producer-845b699bdd-85bk5   1/1     Running   0             63s
* booking-producer-845b699bdd-vd727   1/1     Running   0             63s
* rabbitmq-5cfd974bf6-zd8xm           1/1     Running   0             103m
* booking-consumer-54598b877d-7h7mf   0/1     Running   2 (1s ago)    112s
* booking-consumer-54598b877d-hmbdh   0/1     Running   2 (1s ago)    112s
* booking-consumer-54598b877d-hmbdh   0/1     Running   3 (1s ago)    2m52s
* booking-consumer-54598b877d-7h7mf   0/1     Running   3 (0s ago)    2m53s

* ** This is, likely, due to resources for the containers or / and connexctivity issues!**


### Gathering logs for consumer pods
kubectl logs -l app=booking-consumer --tail=100

### Gathering logs for producer pods
kubectl logs -l app=booking-producer --tail=100

### Gathering verbose details for a managed pod
kubectl describe pod -l app=booking-consumer

### Delete existing pods (Kubernetes will automatically recreate them with the new configuration)
kubectl delete pod -l app=booking-consumer
kubectl delete pod -l app=booking-producer

### We might need to adjust the probe timing in the Kubernetes deployment. 

### Searching for the settings to apply Vertical Scaling of resources! 
find . -name "*deployment*.yaml" | grep <e.g. consumer>


cat ./kubernetes/consumer/deployment.yaml 

![Alt Text](./jsb3.png)

### Now to apply changes to a YAML after editing. 
kubectl apply -f deployment.yaml 

### If that fails you may need to rebuild the images and reploy them to the GKE!


## 5. A breakdown of the GCP scripts!

Both the **setup_gcp_lite.sh** and the **setup_gcp.sh** scripts are intended to do what the AWS setup.sh does in terms of CI/CD deployment on the Google GCP platform!
This will set up similar infrastructure using GKE (Google Kubernetes Engine) instead of EKS.

**NOTE: if you want access to the EKS script please go to https://github.com/costas778/JavaSpringBoot**

## **Key differences from the AWS version:**

### **Uses GCP-specific services:**

### GKE instead of EKS
Google Container Registry (GCR) instead of ECR
Google Cloud VPC instead of AWS VPC

### **Authentication:**
Uses gcloud CLI instead of AWS CLI
Uses GCP service account authentication

### **Infrastructure:**
Simplified networking setup (GCP has different networking concepts)
Uses GKE-specific node pool configuration
Different firewall rules structure

### **Container Registry:**
Uses gcr.io instead of AWS ECR
Different authentication mechanism for container registry

### To use this script, you'll need:
Google Cloud SDK installed
Authenticated gcloud CLI
A GCP project created
Appropriate IAM permissions
Terraform installed
kubectl installed

### Before running, make sure to:
Set up a GCP project
Enable necessary APIs (Container Registry, GKE, Compute Engine)
Set up appropriate service account permissions
Initialize gcloud configuration

**NOTE:** These scripts have been tested and work! 
* Any issues please get back to me!
