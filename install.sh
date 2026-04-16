#!/bin/bash
set -e

# Load environment variables
if [ -f .env ]; then
    export $(cat .env | xargs)
else
    echo "Error: .env file not found. Please create it based on .env.example."
    exit 1
fi

CLUSTER_TYPE=${CLUSTER_TYPE:-k3s}

echo "Starting CI Stress Test Installation for CLUSTER_TYPE: $CLUSTER_TYPE"

# 1. Cluster Provisioning
if [ "$CLUSTER_TYPE" == "k3s" ]; then
    echo "Installing k3s locally..."
    curl -sfL https://get.k3s.io | sh -
    mkdir -p ~/.kube
    sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
    sudo chown $USER:$USER ~/.kube/config
    export KUBECONFIG=~/.kube/config
elif [ "$CLUSTER_TYPE" == "aks" ]; then
    echo "Provisioning AKS cluster in Azure..."
    # Ensure az CLI is logged in
    az account show > /dev/null || az login
    
    az group create --name $AZURE_RESOURCE_GROUP --location $AZURE_REGION || true
    az aks create \
        --resource-group $AZURE_RESOURCE_GROUP \
        --name $AZURE_CLUSTER_NAME \
        --node-count 3 \
        --generate-ssh-keys \
        --node-vm-size Standard_DS2_v2
    
    az aks get-credentials --resource-group $AZURE_RESOURCE_GROUP --name $AZURE_CLUSTER_NAME --overwrite-existing
else
    echo "Unknown CLUSTER_TYPE: $CLUSTER_TYPE"
    exit 1
fi

# 2. Secret Management
echo "Creating secrets in the cluster..."
kubectl create secret generic jenkins-secrets \
    --from-literal=JENKINS_URL="$JENKINS_URL" \
    --from-literal=JENKINS_AGENT_NAME="$JENKINS_AGENT_NAME" \
    --from-literal=JENKINS_SECRET="$JENKINS_SECRET" \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic github-secrets \
    --from-literal=GITHUB_REPO_URL="$GITHUB_REPO_URL" \
    --from-literal=GITHUB_RUNNER_TOKEN="$GITHUB_RUNNER_TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic gitlab-secrets \
    --from-literal=GITLAB_URL="$GITLAB_URL" \
    --from-literal=GITLAB_REGISTRATION_TOKEN="$GITLAB_REGISTRATION_TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f -

# 3. Deploy Runners
echo "Deploying runners using Kustomize overlay: $CLUSTER_TYPE"
kubectl apply -k kubernetes/overlays/$CLUSTER_TYPE

echo "Installation complete. Check runner pods status with: kubectl get pods"
