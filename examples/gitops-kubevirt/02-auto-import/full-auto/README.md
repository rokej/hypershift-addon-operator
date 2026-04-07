# Full-Auto Pattern: Let ACM Handle Everything

This pattern demonstrates the simplest approach to GitOps HostedCluster management with ACM. We create the HostedCluster and NodePool in Git, and let ACM automatically discover and register it as a ManagedCluster.

## Overview

**Cluster Name:** `example-hcp-auto`
**Approach:** Fully automatic cluster discovery and import
**ManagedCluster:** Auto-created by ACM, NOT in Git
**Best For:** Demos, dev environments, learning
**Time to Deploy:** ~30-40 minutes

## Key Characteristics

| Feature | Details |
|---------|---------|
| **GitOps Control** | HostedCluster + NodePool only |
| **Auto-Import** | Enabled (no annotation needed) |
| **ManagedCluster** | Auto-created and managed by ACM |
| **Pre-Configuration** | Cannot pre-configure ACM settings |
| **YAML Files** | 3 (hostedcluster.yaml, nodepool.yaml, argo-application.yaml) |
| **ACM Complexity** | Minimal |

## What Gets Created

### In Git (Managed by You)
```
clusters namespace
├── HostedCluster: example-hcp-auto
└── NodePool: example-hcp-auto-workers
```

### Auto-Created (Managed by ACM)
```
ManagedCluster: example-hcp-auto
├── Klusterlet
├── Klusterlet Addon Config
└── ManifestWorks
```

## Files in This Directory

| File | Purpose |
|------|---------|
| `hostedcluster.yaml` | Defines the hosted cluster (NO auto-import disable annotation) |
| `nodepool.yaml` | Defines worker nodes (2 replicas, 4 cores, 16GiB each) |
| `argo-application.yaml` | Argo CD application that manages HC + NP |
| `observability/watch-script.sh` | Script to monitor auto-import progress |

## Prerequisites

Before deploying this pattern:

- [ ] Setup completed: `../../setup/verify-setup.sh` passes
- [ ] Secrets exist: `pull-secret`, `ssh-key` in `clusters` namespace
- [ ] Argo CD accessible and configured
- [ ] MCE with HyperShift addon running
- [ ] KubeVirt configured
- [ ] Compute resources available (32+ CPUs, 64+ GB RAM)

## Deployment Steps

### Step 1: Review Manifests

Before applying, review the HostedCluster manifest:

```bash
cat hostedcluster.yaml
```

**Key points:**
- **NO annotation** to disable auto-import (this enables auto-import!)
- Release image: `4.17.0-ec.2`
- Platform: `KubeVirt`
- Base domain: `example.com` (customize as needed)

Review the Argo Application:

```bash
cat argo-application.yaml
```

**Key points:**
- Set `spec.source.repoURL` to your fork
- `ignoreDifferences` configured for auto-created ManagedCluster

### Step 2: Customize for Your Environment (Optional)

**Change base domain:**
```bash
sed -i 's/example.com/your.domain/g' hostedcluster.yaml
```

**Change Argo repo:**
```bash
sed -i 's|https://github.com/YOUR_ORG/hypershift-addon-operator.git|https://github.com/your-org/your-repo.git|' argo-application.yaml
```

### Step 3: Dry-Run Validation

Validate YAML before applying:

```bash
oc apply --dry-run=client -f hostedcluster.yaml
oc apply --dry-run=client -f nodepool.yaml
oc apply --dry-run=client -f argo-application.yaml
```

Expected output: "created (dry run)" for each file

### Step 4: Apply Argo Application

```bash
oc apply -f argo-application.yaml
```

Verify it was created:

```bash
oc get application -n openshift-gitops example-hcp-auto
```

### Step 5: Trigger Initial Sync

**Option A: Via Argo CLI**
```bash
argocd app sync example-hcp-auto
```

**Option B: Via Argo Console**
1. Open Argo CD console (get URL from setup output)
2. Login with admin credentials
3. Find `example-hcp-auto` application
4. Click **SYNC** button
5. Click **SYNCHRONIZE** in dialog

### Step 6: Monitor Deployment

**Use the provided watch script:**
```bash
./observability/watch-script.sh example-hcp-auto
```

This will show:
- HostedCluster creation and readiness
- ManagedCluster auto-creation (the key event!)
- Control plane pod status
- NodePool and node readiness
- Klusterlet deployment

**Or manually watch:**
```bash
# Watch HostedCluster status
oc get hostedcluster -n clusters example-hcp-auto -w

# In another terminal, watch ManagedCluster auto-creation
oc get managedcluster example-hcp-auto -w

# In another terminal, watch NodePool status
oc get nodepool -n clusters example-hcp-auto-workers -w
```

## Validation

### HostedCluster Ready
```bash
oc get hostedcluster -n clusters example-hcp-auto
```

Expected: AVAILABLE = True, VERSION = 4.17.0

### ManagedCluster Auto-Created
```bash
oc get managedcluster example-hcp-auto
```

Expected: ManagedCluster exists and is joinable

### Control Plane Running
```bash
oc get pods -n clusters-example-hcp-auto | grep -E "etcd|kube-apiserver|kube-controller"
```

Expected: All pods in Running state

### Workers Ready
```bash
oc get nodepool -n clusters example-hcp-auto-workers
```

Expected: READY = 2/2

### Access Hosted Cluster
```bash
# Get kubeconfig
oc get secret -n clusters example-hcp-auto-admin-kubeconfig \
  -o jsonpath='{.data.kubeconfig}' | base64 -d > /tmp/example-hcp-auto-kubeconfig

# Test access
export KUBECONFIG=/tmp/example-hcp-auto-kubeconfig
oc get nodes
oc get clusteroperators
```

Expected:
- 2 worker nodes in Ready state
- All cluster operators available

## Key Events During Deployment

Here's what happens in the background:

### Timeline

| Time | Event |
|------|-------|
| T+0m | Argo syncs manifests, HostedCluster created |
| T+2m | HyperShift operator detects HC and creates control plane namespace |
| T+5m | Control plane pods starting (etcd, API server, etc.) |
| T+10m | HostedCluster becomes Available |
| T+10m | **ACM detects HostedCluster and auto-creates ManagedCluster** |
| T+12m | Klusterlet deployed to hosted cluster |
| T+15m | First worker node VMs being created |
| T+25m | Both worker nodes join and become Ready |
| T+30m | Full deployment complete |

**Key moment:** Watch for ManagedCluster auto-creation around T+10m!

## Auto-Import Process Explained

### What Triggers Auto-Import?

1. **HostedCluster created** with name `example-hcp-auto`
2. **No annotation** disabling auto-import: `cluster.open-cluster-management.io/managedcluster-name: ""`
3. **MCE controller** detects the new HostedCluster
4. **ManagedCluster auto-created** with same name

### Why No Annotation?

The `cluster.open-cluster-management.io/managedcluster-name: ""` annotation explicitly disables auto-import. By NOT including it, we enable auto-import (the default).

### What Gets Auto-Created?

- **ManagedCluster** resource with the same name
- **Klusterlet** deployment in the hosted cluster
- **KlusterletAddonConfig** with default settings
- **ManifestWorks** for klusterlet components

## Monitoring Auto-Import

### Using the Watch Script
```bash
./observability/watch-script.sh example-hcp-auto
```

This is the recommended approach. The script will:
- Show real-time status of all components
- Highlight when ManagedCluster is auto-created
- Display when auto-import is complete
- Provide next steps

### Manual Monitoring

Watch ManagedCluster creation:
```bash
oc get managedcluster example-hcp-auto -w
```

Watch klusterlet deployment:
```bash
oc get manifestwork -n example-hcp-auto -w
```

Watch addon deployment:
```bash
oc get klusterletaddonconfig -n example-hcp-auto
```

## Pros and Cons

### Pros
✓ **Minimal YAML** - Only 3 files in Git
✓ **Fully Automated** - No manual ManagedCluster creation
✓ **Simple Workflow** - Git → Argo → Automatic
✓ **Perfect for Learning** - Understand basics without complexity
✓ **Fast Setup** - ~5 minutes to deploy

### Cons
✗ **No Pre-Configuration** - Can't configure ManagedCluster before creation
✗ **Not in Git** - ManagedCluster outside version control
✗ **Less Predictable** - Auto-creation timing varies
✗ **Hard to Template** - Difficult to create cluster blueprints
✗ **Limited GitOps** - ManagedCluster not under Git control
✗ **Not Production-Ready** - Better for dev/demo

## Best Use Cases

This pattern is ideal for:

- **Learning Environments** - Understand HCP and auto-import
- **Quick Demos** - Rapid cluster creation
- **Development Clusters** - Ephemeral test environments
- **PoCs** - Proof of concept deployments
- **Training** - Teach GitOps + HCP concepts

## Not Recommended For

- **Production Environments** - Use Hybrid or Disabled
- **Strict GitOps** - Everything should be in Git
- **Cluster Templates** - Can't pre-configure
- **Audit Requirements** - ManagedCluster not tracked in Git
- **Pre-Configured ACM** - Can't set policies before import

## Upgrading from Full-Auto

If you later want to switch patterns:

1. **Switch to Disabled Pattern:**
   - Add annotation to disable auto-import
   - Create explicit ManagedCluster YAML
   - Let existing MC be overwritten by new one

2. **Switch to Hybrid Pattern:**
   - Keep HostedCluster (auto-import stays enabled)
   - Add ManagedClusterSet YAML
   - Add Placement YAML
   - Add Policy YAML

## Cleanup

To remove this cluster:

```bash
# Option 1: Delete via Argo
argocd app delete example-hcp-auto --cascade

# Option 2: Delete resources directly
oc delete hostedcluster -n clusters example-hcp-auto
oc delete nodepool -n clusters example-hcp-auto-workers

# This triggers cleanup of:
# - Control plane namespace
# - KubeVirt VMs
# - ManagedCluster (auto-deleted)
# - Klusterlet (auto-deleted)
```

Wait 5-10 minutes for full cleanup.

## Troubleshooting

### ManagedCluster Not Auto-Creating

**Check if auto-import is disabled:**
```bash
oc get hostedcluster -n clusters example-hcp-auto -o yaml | grep -A 2 "cluster.open-cluster-management.io/managedcluster-name"
```

Should output nothing (annotation not present = auto-import enabled)

**Check MCE is running:**
```bash
oc get mce multiclusterengine -o jsonpath='{.status.phase}'
```

Should output: `Available`

**Check MCE logs:**
```bash
oc logs -n multicluster-engine deployment/multicluster-engine-operator | grep -i "import\|hostedcluster"
```

### Argo Application Stuck in Progressing

**Check Argo logs:**
```bash
oc logs -n openshift-gitops deployment/openshift-gitops-argocd-application-controller
```

**Check if repo is accessible:**
```bash
argocd repo list
```

**Re-sync manually:**
```bash
argocd app sync example-hcp-auto --force
```

### HostedCluster Stuck in Progressing

**Check control plane namespace:**
```bash
oc get pods -n clusters-example-hcp-auto
```

**Check HyperShift operator logs:**
```bash
oc logs -n hypershift deployment/operator | tail -50
```

**Check cluster events:**
```bash
oc get events -n clusters --sort-by='.lastTimestamp'
```

## Next Steps

After successful deployment:

1. **Access the cluster** - Get kubeconfig and explore
2. **Monitor with watch script** - Continue monitoring with the script
3. **Enable auto-sync** - Set Argo to auto-sync changes
4. **Try other patterns** - Deploy Disabled or Hybrid in separate namespace
5. **Read deeper docs** - See [../README.md](../README.md) for pattern comparison

## See Also

- [Disabled Pattern](../disabled/) - Full GitOps control
- [Hybrid Pattern](../hybrid/) - Production-ready fleet management
- [Scenario 1: Provisioning](../../01-provision/) - Basic HCP setup
- [Architecture Overview](../../../docs/gitops/01-architecture.md)
