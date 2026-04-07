# Prerequisites

Before running the GitOps HCP examples, ensure you have the following:

## Management Cluster Requirements

- **OpenShift Version:** 4.16 or later
- **Cluster Access:** Cluster admin privileges
- **Resources:**
  - Minimum 32 CPUs available for worker nodes
  - Minimum 64 GB RAM
  - Minimum 500 GB storage

## Network Requirements

- **Ingress:** LoadBalancer service support or OpenShift routes
- **Egress:** Internet access for pulling images (or configured mirror registry)
- **DNS:** Proper DNS resolution for cluster domains

## CLI Tools

Install the following CLI tools on your workstation:

- `oc` - OpenShift CLI (version matching your cluster)
- `kubectl` - Kubernetes CLI
- `argocd` - Argo CD CLI (optional, for easier management)
- `hcp` - HyperShift CLI (optional, for generating manifests)

### Installing CLI Tools

**OpenShift CLI (oc):**
```bash
# Download from OpenShift console: Help (?) → Command Line Tools
# Or from https://mirror.openshift.com/pub/openshift-v4/clients/ocp/
```

**Argo CD CLI:**
```bash
# macOS
brew install argocd

# Linux
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd
sudo mv argocd /usr/local/bin/
```

**HyperShift CLI:**
```bash
# Download from HyperShift releases
# https://github.com/openshift/hypershift/releases
```

## Cluster Preparation

1. **Login to your management cluster:**
   ```bash
   oc login --token=<your-token> --server=https://<api-server>:6443
   ```

2. **Verify cluster version:**
   ```bash
   oc version
   ```

3. **Check available resources:**
   ```bash
   oc get nodes
   oc describe nodes | grep -A 5 "Allocated resources"
   ```

## Secrets Preparation

You will need the following secrets. Prepare them before starting:

1. **Pull Secret:**
   - Obtain from https://console.redhat.com/openshift/install/pull-secret
   - Save to a file (e.g., `pull-secret.txt`)

2. **SSH Key:**
   - Generate if you don't have one:
     ```bash
     ssh-keygen -t ed25519 -f ~/.ssh/hcp-key -N ""
     ```

## Next Steps

Once you have met all prerequisites, proceed to the setup scripts:
- [01-acm-mce-install.sh](01-acm-mce-install.sh) - Install ACM/MCE
- [02-argo-install.sh](02-argo-install.sh) - Install Argo CD
- [03-kubevirt-setup.sh](03-kubevirt-setup.sh) - Configure KubeVirt
- [04-secrets-template.yaml](04-secrets-template.yaml) - Create secrets
