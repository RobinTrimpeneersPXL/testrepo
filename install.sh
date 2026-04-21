#!/bin/bash
set -e

# Default values
INSTALL_GITHUB=false
INSTALL_GITLAB=false
INSTALL_JENKINS=false
ANY_FLAG=false

# Function to display help
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  --github    Install GitHub runner"
    echo "  --gitlab    Install GitLab runner"
    echo "  --jenkins   Install Jenkins agent"
    echo "  --all       Install all components (default if no flags provided)"
    echo "  --help      Display this help message"
}

# Parse flags
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --github) INSTALL_GITHUB=true; ANY_FLAG=true ;;
        --gitlab) INSTALL_GITLAB=true; ANY_FLAG=true ;;
        --jenkins) INSTALL_JENKINS=true; ANY_FLAG=true ;;
        --all) 
            INSTALL_GITHUB=true
            INSTALL_GITLAB=true
            INSTALL_JENKINS=true
            ANY_FLAG=true
            ;;
        --help) usage; exit 0 ;;
        *) echo "Unknown parameter passed: $1"; usage; exit 1 ;;
    esac
    shift
done

# Default to all if no flags specified
if [ "$ANY_FLAG" = false ]; then
    INSTALL_GITHUB=true
    INSTALL_GITLAB=true
    INSTALL_JENKINS=true
fi

# Function to load .env file robustly
load_env() {
    if [ -f .env ]; then
        export $(grep -v '^#' .env | sed 's/\r$//' | xargs)
    else
        echo "Error: .env file not found. Please create it based on .env.example."
        exit 1
    fi
}

load_env

CLUSTER_TYPE=${CLUSTER_TYPE:-k3s}

echo "Starting CI Stress Test Installation for CLUSTER_TYPE: $CLUSTER_TYPE"

# 0. Check dependencies
for tool in kubectl; do
    if ! command -v $tool &> /dev/null; then
        echo "Error: $tool is not installed."
        exit 1
    fi
done

# 1. Cluster Provisioning
if [ "$CLUSTER_TYPE" == "k3s" ]; then
    if ! kubectl cluster-info > /dev/null 2>&1; then
        if command -v k3d &> /dev/null; then
            echo "k3d detected. Creating k3d cluster..."
            k3d cluster create mycluster --volume /var/run/docker.sock:/var/run/docker.sock --agents 2
        else
            echo "Installing k3s locally..."
            curl -sfL https://get.k3s.io | sh -
            mkdir -p ~/.kube
            sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
            sudo chown $USER:$USER ~/.kube/config
            export KUBECONFIG=~/.kube/config
        fi
    else
        echo "Kubernetes cluster already detected, skipping provisioning."
    fi
elif [ "$CLUSTER_TYPE" == "aks" ]; then
    echo "Provisioning AKS cluster in Azure..."
    az account show > /dev/null || az login
    az group create --name "$AZURE_RESOURCE_GROUP" --location "$AZURE_REGION" || true
    az aks create --resource-group "$AZURE_RESOURCE_GROUP" --name "$AZURE_CLUSTER_NAME" --node-count 3 --generate-ssh-keys --node-vm-size Standard_DS2_v2
    az aks get-credentials --resource-group "$AZURE_RESOURCE_GROUP" --name "$AZURE_CLUSTER_NAME" --overwrite-existing
fi

# 2. Secret Management & Deployment
deploy_component() {
    local name=$1
    local label=$2
    echo "Deploying $name..."
    kubectl kustomize kubernetes/overlays/$CLUSTER_TYPE | kubectl apply -l app=$label -f -
}

if [ "$INSTALL_JENKINS" = true ]; then
    echo "Configuring Jenkins secrets..."
    kubectl create secret generic jenkins-secrets \
        --from-literal=JENKINS_URL="$JENKINS_URL" \
        --from-literal=JENKINS_AGENT_NAME="$JENKINS_AGENT_NAME" \
        --from-literal=JENKINS_SECRET="$JENKINS_SECRET" \
        --dry-run=client -o yaml | kubectl apply -f -
    deploy_component "Jenkins Agent" "jenkins-agent"
fi

if [ "$INSTALL_GITHUB" = true ]; then
    if [ -n "$GITHUB_RUNNER_TOKEN" ]; then
        echo "Configuring GitHub secrets..."
        kubectl create secret generic github-secrets \
            --from-literal=GITHUB_REPO_URL="$GITHUB_REPO_URL" \
            --from-literal=GITHUB_RUNNER_TOKEN="$GITHUB_RUNNER_TOKEN" \
            --dry-run=client -o yaml | kubectl apply -f -
        deploy_component "GitHub Runner" "github-runner"
        
        if [ -n "$GITHUB_RUNNER_REPLICAS" ]; then
            echo "Patching GitHub runner replicas to $GITHUB_RUNNER_REPLICAS..."
            kubectl patch deployment github-runner -p "{\"spec\":{\"replicas\":$GITHUB_RUNNER_REPLICAS}}"
        fi
    else
        echo "Skipping GitHub: GITHUB_RUNNER_TOKEN not set."
    fi
fi

if [ "$INSTALL_GITLAB" = true ]; then
    if [ -n "$GITLAB_REGISTRATION_TOKEN" ]; then
        echo "Configuring GitLab secrets..."
        kubectl create secret generic gitlab-secrets \
            --from-literal=GITLAB_URL="$GITLAB_URL" \
            --from-literal=GITLAB_REGISTRATION_TOKEN="$GITLAB_REGISTRATION_TOKEN" \
            --from-literal=GITLAB_RUNNER_CONCURRENT="${GITLAB_RUNNER_CONCURRENT:-50}" \
            --from-literal=GITLAB_RUNNER_TAG_LIST="${GITLAB_RUNNER_TAG_LIST:-stress-test}" \
            --from-literal=GITLAB_JOB_CPU_REQUEST="${GITLAB_JOB_CPU_REQUEST:-500m}" \
            --from-literal=GITLAB_JOB_MEMORY_REQUEST="${GITLAB_JOB_MEMORY_REQUEST:-1Gi}" \
            --from-literal=GITLAB_JOB_CPU_LIMIT="${GITLAB_JOB_CPU_LIMIT:-1}" \
            --from-literal=GITLAB_JOB_MEMORY_LIMIT="${GITLAB_JOB_MEMORY_LIMIT:-2Gi}" \
            --dry-run=client -o yaml | kubectl apply -f -
        deploy_component "GitLab Runner" "gitlab-runner"
    else
        echo "Skipping GitLab: GITLAB_REGISTRATION_TOKEN not set."
    fi
fi

echo "Installation complete. Check runner pods status with: kubectl get pods"
