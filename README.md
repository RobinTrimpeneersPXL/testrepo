# CI Runner Stress Test Framework

A complete infrastructure for stress-testing Kubernetes cluster limits by running intensive, parallelized CI/CD workloads across **Jenkins**, **GitHub Actions**, and **GitLab CI**.

## 🚀 Overview

This project automates the deployment of CI runners into a Kubernetes cluster (Local k3s or Azure AKS) and provides highly parallelized build pipelines using **Kaniko** to saturate CPU, Memory, and Disk I/O.

## 🛠️ Prerequisites

- **Kubectl**: Installed and configured.
- **Kustomize**: Built-in with `kubectl -k`.
- **Azure CLI (`az`)**: Required only for AKS deployment.
- **CI Tokens**:
  - **GitHub**: Repository registration token.
  - **GitLab**: Project registration token.
  - **Jenkins**: Agent name and secret (from an existing controller).

## 📥 Setup Instructions

### 1. Clone & Configure
First, prepare your environment variables:
```bash
cp .env.example .env
# Edit .env with your specific tokens and cluster preferences
```

### 2. Deployment
Run the automated installation script. This will provision the cluster, create Kubernetes secrets, and deploy all runners.

**For Local Testing (k3s):**
Ensure `CLUSTER_TYPE=k3s` in `.env`, then:
```bash
chmod +x install.sh
./install.sh
```

**For Cloud Testing (AKS):**
Ensure `CLUSTER_TYPE=aks` in `.env`, then:
```bash
az login
./install.sh
```

### 3. Verify Runners
Check the status of your runner pods:
```bash
kubectl get pods -w
```
Confirm they appear as "Online" or "Idle" in your respective CI/CD dashboards (Jenkins Node list, GitHub Settings > Actions > Runners, GitLab Settings > CI/CD > Runners).

## ⚡ Running the Stress Test

The repository includes pre-configured pipeline files designed to trigger **10+ parallel builds** of a heavy Docker image.

- **Jenkins**: Create a "Pipeline" job and point it to the `Jenkinsfile`.
- **GitHub**: Push to your repository; the workflow in `.github/workflows/stress-test.yml` will trigger automatically.
- **GitLab**: Push to your repository; the `.gitlab-ci.yml` will trigger the parallel jobs.

### Monitoring Cluster Limits
While the builds are running, monitor the resource utilization from your terminal:

```bash
# Monitor node resource usage
watch kubectl top nodes

# Monitor pod resource usage
watch kubectl top pods
```

## 🏗️ Architecture

- **Kaniko**: Used for building container images without requiring privileged `Docker-in-Docker` pods.
- **Kustomize**: Manages environment-specific overlays:
  - `k3s`: Lower resource requests/limits for local development.
  - `aks`: High-performance limits to maximize cloud node utilization.
- **Secrets**: Runner tokens are stored securely in Kubernetes `Secrets`.

## ⚠️ Cleanup

**For AKS:**
```bash
az group delete --name <your-resource-group> --yes --no-wait
```

**For k3s:**
```bash
/usr/local/bin/k3s-uninstall.sh
```
