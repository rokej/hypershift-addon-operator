# Getting Started: Setup and First Deployment

## Overview

This guide walks you through setting up your environment and deploying Scenario 1 (basic provisioning) for the first time.

**Timeline:** 45-60 minutes total  
**Difficulty:** Beginner  
**Prerequisites:** Hub cluster with HyperShift and Argo CD

---

## Prerequisites Checklist

### Hub Cluster Requirements

Check these before starting:

```bash
# Check HyperShift Operator is installed
kubectl get deployment -n hypershift-system hypershift-operator

# Check Argo CD is installed
kubectl get deployment -n argocd argocd-server

# Check ACM is installed (optional but recommended)
kubectl get deployment -n open-cluster-management-hub cluster-manager

# Verify kubeconfig access to hub
kubectl get nodes
```

### Required Tools

```bash
# Kubernetes CLI
kubectl version --short

# OpenShift CLI (for OCP features)
oc version

# Git (to clone examples)
git --version

# Optional: Argo CD CLI (for monitoring)
argocd version
```

### Required Credentials

Create these before deploying:

#### 1. Pull Secret

```bash
# Get from https://console.redhat.com/openshift/downloads
# Save to a file, then create secret

kubectl create secret generic pull-secret \
  --from-file=.dockerconfigjson=/path/to/pull-secret.json \
  --type=kubernetes.io/dockerconfigjson \
  -n clusters

# Verify
kubectl get secret -n clusters pull-secret
```

#### 2. SSH Key

```bash
# Generate if you don't have one
ssh-keygen -t rsa -b 4096 -N "" -f ~/.ssh/hcp_rsa

# Create secret
kubectl create secret generic ssh-key \
  --from-file=ssh-publickey=~/.ssh/hcp_rsa.pub \
  -n clusters

# Verify
kubectl get secret -n clusters ssh-key
```

#### 3. Cloud Provider Credentials (if using AWS)

```bash
# For KubeVirt, this is the KubeVirt cluster credentials
# For AWS, this is your AWS credentials
# See your cloud provider's documentation

# Create secret as needed:
kubectl create secret generic kubevirt-credentials \
  --from-file=kubeconfig=/path/to/kubevirt-kubeconfig.yaml \
  -n hypershift
```

### Network Requirements

Verify network connectivity:

```bash
# Hub cluster can reach Git repository
curl -I https://github.com

# Hub cluster can reach container registry
kubectl run --rm -it test --image=quay.io/openshift-release-dev/ocp-release:4.17.0-x86_64 -- /bin/true

# DNS resolution for base domain
nslookup <your-base-domain>

# Verify network policies allow HCP <-> Hub communication
# (depends on your platform and topology)
```

---

## Environment Setup

### Step 1: Create Namespaces

```bash
# Namespace for hosted clusters
kubectl create namespace clusters

# Namespace for Argo applications
kubectl create namespace argocd

# Verify
kubectl get namespace clusters argocd
```

### Step 2: Pre-Create Credentials

The credentials must exist in the hub cluster before deploying:

```bash
# Verify pull-secret exists
kubectl get secret -n clusters pull-secret \
  -o jsonpath='{.data.\.dockerconfigjson}' | wc -c

# Verify ssh-key exists
kubectl get secret -n clusters ssh-key \
  -o jsonpath='{.data.ssh-publickey}' | wc -c

# Should both show non-zero values
```

### Step 3: Configure Git Access

Argo CD needs to access your Git repository:

#### Option A: SSH Keys

```bash
# Create GitHub deploy key
# 1. Go to https://github.com/YOUR_ORG/YOUR_REPO/settings/keys
# 2. Add new deploy key:
#    - Title: "argocd-key"
#    - Key: (paste public key)
#    - Allow write access: YES

# Create secret in argocd namespace
kubectl create secret generic github-key \
  --from-file=ssh-private-key=~/.ssh/github_rsa \
  -n argocd

# Verify
kubectl get secret -n argocd github-key
```

#### Option B: Personal Access Token (PAT)

```bash
# Create token at https://github.com/settings/tokens
# Scopes: repo, admin:repo_hook

# Store in secret
kubectl create secret generic github-token \
  --from-literal=token=<YOUR_PAT> \
  -n argocd

# Verify
kubectl get secret -n argocd github-token
```

### Step 4: Configure Argo CD Repository

```bash
# Add repository to Argo CD
argocd repo add https://github.com/YOUR_ORG/hypershift-examples \
  --ssh-private-key-path ~/.ssh/github_rsa \
  --name hypershift-examples

# Or via kubectl
kubectl create secret generic hypershift-examples-repo \
  --from-literal=type=git \
  --from-literal=url=https://github.com/YOUR_ORG/hypershift-examples \
  --from-literal=sshPrivateKey="$(cat ~/.ssh/github_rsa)" \
  -n argocd \
  --dry-run=client -o yaml | kubectl apply -f -

# Label for Argo to discover
kubectl label secret hypershift-examples-repo \
  argocd.argoproj.io/secret-type=repository \
  -n argocd
```

---

## First Deployment: Scenario 1

### Phase 1: Prepare Manifests (10 minutes)

#### 1. Clone Examples

```bash
git clone https://github.com/stolostron/hypershift-addon-operator.git
cd hypershift-addon-operator/examples/gitops-kubevirt/01-provision
```

#### 2. Customize for Your Environment

**Edit `base/hostedcluster.yaml`:**

```bash
# Change baseDomain to your domain
sed -i 's/example\.com/your-domain.com/g' base/hostedcluster.yaml

# Change namespace if different from "clusters"
sed -i 's/namespace: clusters/namespace: your-namespace/g' base/hostedcluster.yaml

# Edit other fields as needed
nano base/hostedcluster.yaml
```

Key fields to customize:

```yaml
spec:
  baseDomain: your-domain.com
  platform:
    kubevirt:
      credentials:
        infraSecretRef:
          name: kubevirt-credentials  # verify this secret exists
  networking:
    machineNetwork:
      - cidr: "192.168.126.0/24"  # match your network
  pullSecret:
    name: pull-secret  # verify this secret exists
  sshKey:
    name: ssh-key  # verify this secret exists
```

**Edit `base/nodepool.yaml`:**

```bash
# Same namespace as HostedCluster
nano base/nodepool.yaml
```

Key fields:

```yaml
spec:
  clusterName: example-hcp  # must match HostedCluster name
  initialConfig:
    networkConfig: |
      # Ensure this matches cluster networking
  platform:
    type: KubeVirt
    kubevirt:
      rootVolume:
        accessModes: [ "ReadWriteOnce" ]
        storageClass: local  # match your storage class
```

**Edit `argo-application.yaml`:**

```bash
nano argo-application.yaml
```

Key fields:

```yaml
spec:
  source:
    repoURL: https://github.com/YOUR_ORG/hypershift-examples  # your fork
    targetRevision: main  # your branch
    path: examples/gitops-kubevirt/01-provision  # path in your repo
  destination:
    name: in-cluster
    namespace: argocd  # Argo namespace
```

#### 3. Verify Customization

```bash
# Check all substitutions succeeded
grep -r "example.com" .
grep -r "example-hcp" .

# Verify secrets are referenced correctly
grep "pullSecret\|sshKey" base/hostedcluster.yaml

# Verify storage class exists
kubectl get storageclass | grep local
```

### Phase 2: Apply to Git (5 minutes)

If using your own repository:

```bash
# Fork the repo
# https://github.com/stolostron/hypershift-addon-operator/fork

# Clone your fork
git clone https://github.com/YOUR_ORG/hypershift-addon-operator.git
cd hypershift-addon-operator

# Make changes
git checkout -b scenario1-deployment
# ... edit files ...

# Commit and push
git add examples/gitops-kubevirt/01-provision/
git commit -m "Configure Scenario 1 for production deployment"
git push origin scenario1-deployment

# Create pull request for review
# https://github.com/YOUR_ORG/hypershift-addon-operator/compare

# After approval, merge to main
```

### Phase 3: Deploy via Argo (5 minutes)

```bash
# Create namespace for argo applications
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# Apply Argo Application
kubectl apply -f argo-application.yaml

# Watch Argo sync
watch -n 5 kubectl get application -n argocd gitops-hcp-scenario1

# Check Application details
kubectl describe application -n argocd gitops-hcp-scenario1

# View Argo dashboard (optional)
kubectl port-forward -n argocd svc/argocd-server 8080:443 &
# Open https://localhost:8080 in browser
```

Expected progression:

```
NAME                    SYNC STATUS   HEALTH STATUS
gitops-hcp-scenario1    Syncing       Progressing    (takes 1-2 minutes)
gitops-hcp-scenario1    Synced        Healthy        (ready)
```

### Phase 4: Monitor Cluster Creation (25-30 minutes)

In a new terminal:

```bash
# Watch HostedCluster creation
watch -n 5 'kubectl get hostedcluster -n clusters -o wide'

# Expected timeline:
# T+0m:  Creating
# T+3m:  Progressing (control plane starting)
# T+8m:  Available (control plane healthy)
# T+40m: Nodes Ready (workers running)
```

Detailed monitoring:

```bash
# Check HostedCluster status
kubectl get hostedcluster example-hcp -n clusters -o json | \
  jq '.status.conditions[] | {type, status, reason}'

# Expected conditions:
# - ReconciliationSucceeded: True
# - Available: True (after ~8 minutes)
# - Progressing: True (during creation)

# Check control plane Pods
kubectl get pods -n clusters-example-hcp

# Check NodePool status
kubectl get nodepool -n clusters

# Expected replicas to reach: 2 (or your custom count)
```

### Phase 5: Verify Access (5 minutes)

```bash
# Get the admin kubeconfig
kubectl get secret -n clusters admin-kubeconfig -o json | \
  jq -r '.data.kubeconfig' | base64 -d > /tmp/hcp-kubeconfig

# Test connectivity
kubectl --kubeconfig=/tmp/hcp-kubeconfig cluster-info

# Check nodes in hosted cluster
kubectl --kubeconfig=/tmp/hcp-kubeconfig get nodes
# Should show 2 Ready nodes (or your count)

# Access via oc
oc login --kubeconfig=/tmp/hcp-kubeconfig

# Check API is responding
oc --kubeconfig=/tmp/hcp-kubeconfig api-resources | head -20
```

### Phase 6: Verify ACM Integration (5 minutes)

```bash
# Check ManagedCluster was created
kubectl get managedcluster example-hcp

# Check klusterlet deployment
kubectl get deployment -n open-cluster-management-agent \
  -A

# View in ACM dashboard
# Login to ACM hub
# Navigate to: Clusters > All Clusters
# Should see "example-hcp" with status "Ready"
```

---

## Expected Timelines

| Phase | Duration | Notes |
|-------|----------|-------|
| Setup credentials | 10 min | One-time setup |
| Customize manifests | 10 min | Edit YAML files |
| Deploy via Argo | 2 min | kubectl apply |
| Control plane creation | 5-10 min | HyperShift reconciles |
| Worker nodes boot | 20-30 min | Depends on infrastructure |
| Full cluster ready | **45-60 min** | Total time |

**Factors affecting duration:**

- Pull image cache (first deploy slower)
- Network bandwidth
- Storage provisioning speed
- Infrastructure API response time

---

## Common First-Run Issues

### Issue 1: Pull Secret Not Found

**Symptom:**
```
Error: pull-secret secret not found in namespace clusters
```

**Fix:**
```bash
# Verify secret exists
kubectl get secret -n clusters pull-secret

# If not, create it
kubectl create secret generic pull-secret \
  --from-file=.dockerconfigjson=/path/to/pull-secret.json \
  --type=kubernetes.io/dockerconfigjson \
  -n clusters

# Update HostedCluster to reference it
# Edit base/hostedcluster.yaml
kubectl apply -f base/hostedcluster.yaml
```

### Issue 2: Argo Application Out of Sync

**Symptom:**
```
SYNC STATUS   HEALTH STATUS
OutOfSync     Degraded
```

**Diagnosis:**
```bash
# Check Argo logs
kubectl logs -n argocd deployment/argocd-application-controller

# Check specific error
kubectl describe application -n argocd gitops-hcp-scenario1

# Common causes:
# - Repository URL wrong
# - Branch doesn't exist
# - YAML syntax error
```

**Fix:**
```bash
# If repository wrong:
argocd repo list
argocd repo remove <bad-url>
argocd repo add <correct-url> --ssh-private-key-path ~/.ssh/github_rsa

# If branch wrong:
git checkout -b main  # ensure main branch exists
git push origin main

# Force resync
argocd app sync gitops-hcp-scenario1
```

### Issue 3: HostedCluster Stuck in "Progressing"

**Symptom:**
```
kubectl get hostedcluster
NAME          AVAILABLE   PROGRESSING
example-hcp   False       True
```

After 15+ minutes, still not Available.

**Diagnosis:**
```bash
# Check detailed status
kubectl get hostedcluster example-hcp -n clusters -o json | \
  jq '.status'

# Check HyperShift operator logs
kubectl logs -n hypershift-system deployment/hypershift-operator -f

# Check control plane Pods
kubectl get pods -n clusters-example-hcp -o wide

# Look for failures
kubectl describe pod -n clusters-example-hcp
```

**Common causes:**
- Release image pull failing (pull secret)
- Base domain DNS not resolving
- Storage provisioning stuck
- Insufficient cluster resources

**Fix:**
```bash
# For pull secret: create secret, redeploy
# For DNS: ensure nslookup works
# For storage: check PVCs
kubectl get pvc -A

# For resources: check Hub cluster capacity
kubectl top nodes
```

### Issue 4: Nodes Won't Become Ready

**Symptom:**
```
kubectl --kubeconfig=hcp-kubeconfig get nodes
NAME    STATUS     ROLES    AGE
node1   NotReady   worker   10m
node2   NotReady   worker   10m
```

**Diagnosis:**
```bash
# Check node status
kubectl --kubeconfig=hcp-kubeconfig describe node node1

# Check kubelet logs on node (if accessible)
# From host: ssh user@node-ip journalctl -u kubelet

# Check ignition/cloud-init errors
# From host: ssh user@node-ip cat /var/log/cloud-init-output.log

# Check machine status on Hub
kubectl get machines -A
kubectl describe machine <name> -n clusters
```

**Common causes:**
- Ignition config issues (SSH key, network)
- Storage not attached to VM
- CNI not deployed
- Network plugin not ready

**Fix:**
```bash
# Usually need to fix NodePool manifest
# Edit base/nodepool.yaml
# Update initialConfig or platform settings
kubectl apply -f base/nodepool.yaml

# Operator will roll nodes and retry
```

### Issue 5: ManagedCluster Never Appears

**Symptom:**
```
kubectl get managedcluster
No resources found
```

After 20 minutes.

**Diagnosis:**
```bash
# Check klusterlet deployment
kubectl get deployment -n open-cluster-management-agent -A

# Check if cluster's klusterlet running
kubectl logs -n open-cluster-management-agent <pod> -f

# Check if HCP has kubeconfig
kubectl get secret -n clusters admin-kubeconfig
```

**Fix:**
```bash
# Ensure control plane is Available
kubectl get hostedcluster example-hcp -n clusters

# Manually trigger klusterlet deployment
kubectl rollout restart deployment/hypershift-operator \
  -n hypershift-system

# Wait for klusterlet to deploy
kubectl get deployment -n open-cluster-management-agent -A

# Check import status
kubectl logs -n open-cluster-management-hub <pod> | grep example-hcp
```

---

## Next Steps

1. **Verify success:** Run the verification commands in Phase 5-6 above
2. **Access your cluster:** Use the kubeconfig to deploy workloads
3. **Explore Argo:** Log in to Argo dashboard, see the Application
4. **View in ACM:** Check the cluster in ACM console
5. **Continue learning:**
   - [03-provisioning.md](./03-provisioning.md) - Deep dive into provisioning
   - [05-auto-import-deep-dive.md](./05-auto-import-deep-dive.md) - Auto-import details
   - [06-managing-scale-operations.md](./06-managing-scale-operations.md) - Scaling operations (Scenario 3)

---

## Troubleshooting Resources

- [08-troubleshooting.md](./08-troubleshooting.md) - Comprehensive troubleshooting guide
- Example logs: `examples/gitops-kubevirt/01-provision/VALIDATION.md`
- HyperShift docs: [hypershift-docs.netlify.app](https://hypershift-docs.netlify.app/)
- ACM docs: [Red Hat Advanced Cluster Management](https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes/)

---

**Last Updated:** April 2, 2026  
**Status:** Complete
