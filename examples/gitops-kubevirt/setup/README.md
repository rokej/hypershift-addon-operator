# Setup Scripts

This directory contains scripts to prepare your OpenShift cluster for the GitOps HCP examples.

## Overview

Run these scripts in order to:
1. Install ACM/MCE with HyperShift addon
2. Install OpenShift GitOps (Argo CD)
3. Configure KubeVirt for hosting HCPs
4. Create required secrets
5. Verify the setup is complete

## Prerequisites

Before running these scripts, review [00-prerequisites.md](00-prerequisites.md) and ensure you have:
- OpenShift 4.16+ cluster with admin access
- Sufficient compute resources (32+ CPUs, 64+ GB RAM)
- Required CLI tools (`oc`, `kubectl`, `argocd`, `hcp`)
- Pull secret and SSH key ready

## Installation Steps

### Step 1: Install ACM/MCE

```bash
./01-acm-mce-install.sh
```

This script:
- Creates the `multicluster-engine` namespace
- Subscribes to the MCE operator
- Creates a MultiClusterEngine instance with HyperShift addon enabled
- Creates the `clusters` namespace
- Waits for all components to be ready

**Duration:** ~5-10 minutes

### Step 2: Install Argo CD

```bash
./02-argo-install.sh
```

This script:
- Subscribes to the OpenShift GitOps operator
- Configures RBAC for ArgoCD to manage HyperShift resources
- Prints the ArgoCD console URL and admin credentials

**Duration:** ~3-5 minutes

**Output:** Save the ArgoCD credentials for later use.

### Step 3: Configure KubeVirt

```bash
./03-kubevirt-setup.sh
```

This script:
- Installs OpenShift Virtualization (if not already installed)
- Creates a HyperConverged instance
- Validates compute and storage resources

**Duration:** ~5-10 minutes (if installing); <1 minute (if already installed)

### Step 4: Create Secrets

Secrets cannot be stored in Git, so create them manually:

```bash
# Create pull secret
oc create secret generic pull-secret \
  --from-file=.dockerconfigjson=/path/to/pull-secret.json \
  --type=kubernetes.io/dockerconfigjson \
  -n clusters

# Create SSH key secret
oc create secret generic ssh-key \
  --from-file=id_rsa.pub=~/.ssh/hcp-key.pub \
  -n clusters

# Verify
oc get secrets -n clusters
```

See [04-secrets-template.yaml](04-secrets-template.yaml) for detailed instructions.

### Step 5: Verify Setup

```bash
./verify-setup.sh
```

This script checks that all components are installed and ready.

**Expected output:** All checks should pass (✓)

If any checks fail, review the output and re-run the appropriate setup script.

## Cleanup

To remove the GitOps HCP setup:

```bash
./cleanup.sh
```

This removes the MultiClusterEngine instance, secrets, and clusters namespace, but leaves the operators installed.

## Troubleshooting

### MCE operator installation fails

Check operator status:
```bash
oc get csv -n multicluster-engine
oc logs -n multicluster-engine deployment/multicluster-engine-operator
```

### HyperShift operator not running

Check HyperShift operator status:
```bash
oc get deployment -n hypershift
oc logs -n hypershift deployment/operator
```

### ArgoCD not accessible

Check ArgoCD status:
```bash
oc get argocd -n openshift-gitops
oc get route -n openshift-gitops
```

## Next Steps

Once all checks pass, proceed to:
- [../01-provision/](../01-provision/) - Create your first HCP via GitOps
- [../../docs/gitops/02-getting-started.md](../../docs/gitops/02-getting-started.md) - Getting Started guide
