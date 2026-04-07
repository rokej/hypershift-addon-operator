# Disabled Pattern: Full GitOps Control

This pattern demonstrates GitOps-first cluster management where the ManagedCluster resource is explicitly defined and versioned in Git. We disable ACM's auto-import and take full control of the cluster registration process.

## Overview

**Cluster Name:** `example-hcp-disabled`
**Approach:** Explicit Git-managed ManagedCluster
**ManagedCluster:** Defined in Git, applied via Argo
**Best For:** Strict GitOps, production, compliance
**Time to Deploy:** ~35-45 minutes

## Key Characteristics

| Feature | Details |
|---------|---------|
| **GitOps Control** | HostedCluster, NodePool, ManagedCluster, Addons |
| **Auto-Import** | Disabled via annotation |
| **ManagedCluster** | Explicit YAML in Git, full version control |
| **Pre-Configuration** | Can set labels and configure KlusterletAddonConfig |
| **YAML Files** | 5+ (HC, NP, MC, KAC, Argo app) |
| **ACM Complexity** | Medium (explicit control) |

## What Gets Created

### In Git (Managed by You)
```
clusters namespace
├── HostedCluster: example-hcp-disabled (with auto-import disabled)
├── NodePool: example-hcp-disabled-workers
├── ManagedCluster: example-hcp-disabled (explicit)
└── KlusterletAddonConfig: example-hcp-disabled
```

### Controlled by You via Git
```
All ACM resources are versioned in Git:
- ManagedCluster creation/deletion is tracked
- Addon configuration is reproducible
- Changes require Pull Requests
- Full audit trail in Git history
```

## Files in This Directory

| File | Purpose |
|------|---------|
| `hostedcluster.yaml` | Defines hosted cluster (WITH auto-import disable annotation) |
| `nodepool.yaml` | Defines worker nodes (2 replicas, 4 cores, 16GiB each) |
| `managedcluster.yaml` | Explicitly defines the ManagedCluster resource |
| `klusterlet-addon-config.yaml` | Configures ACM addons for this cluster |
| `argo-application.yaml` | Argo CD application that manages all resources |

## Prerequisites

Before deploying this pattern:

- [ ] Setup completed: `../../setup/verify-setup.sh` passes
- [ ] Secrets exist: `pull-secret`, `ssh-key` in `clusters` namespace
- [ ] Argo CD accessible and configured
- [ ] MCE with HyperShift addon running
- [ ] KubeVirt configured
- [ ] Compute resources available (32+ CPUs, 64+ GB RAM)

## Key Concept: Auto-Import Annotation

The critical difference from Full-Auto is this annotation:

```yaml
metadata:
  annotations:
    cluster.open-cluster-management.io/managedcluster-name: ""
```

**What it means:**
- Empty string value (`""`) tells MCE: "Do not auto-create ManagedCluster"
- Without this annotation (Full-Auto), ACM creates ManagedCluster automatically
- With this annotation (Disabled), you must create ManagedCluster explicitly

**Why this matters:**
- You control WHEN the cluster is registered
- You can pre-configure ManagedCluster properties
- You can add labels before ACM sees the cluster
- Everything is version-controlled in Git

## Deployment Steps

### Step 1: Review Manifests

Review the HostedCluster annotation that disables auto-import:

```bash
cat hostedcluster.yaml | grep -A 2 "managedcluster-name"
```

Expected: `cluster.open-cluster-management.io/managedcluster-name: ""`

Review the ManagedCluster that we'll create explicitly:

```bash
cat managedcluster.yaml
```

Note:
- ManagedCluster is cluster-scoped (no namespace)
- Has `hubAcceptsClient: true` to be joinable
- Can have labels for organization

Review the addon configuration:

```bash
cat klusterlet-addon-config.yaml
```

This configures:
- Application Manager (for app deployments)
- Policy Controller (for compliance policies)
- Search Collector (for resource search)
- Certificate Controller (for cert compliance)

### Step 2: Customize for Your Environment

**Change base domain:**
```bash
sed -i 's/example.com/your.domain/g' hostedcluster.yaml
```

**Add custom labels to ManagedCluster:**
```bash
# Edit managedcluster.yaml to add labels:
# labels:
#   environment: production
#   team: platform
#   region: us-west
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
oc apply --dry-run=client -f managedcluster.yaml
oc apply --dry-run=client -f klusterlet-addon-config.yaml
oc apply --dry-run=client -f argo-application.yaml
```

All should succeed with "(dry run)"

### Step 4: Apply Argo Application

```bash
oc apply -f argo-application.yaml
```

Verify:
```bash
oc get application -n openshift-gitops example-hcp-disabled
```

### Step 5: Trigger Initial Sync

**Via Argo CLI:**
```bash
argocd app sync example-hcp-disabled
```

**Via Argo Console:**
1. Open Argo CD console
2. Find `example-hcp-disabled` application
3. Click **SYNC** button

### Step 6: Monitor Deployment

Watch the resources in order:

**Terminal 1: HostedCluster**
```bash
oc get hostedcluster -n clusters example-hcp-disabled -w
```

**Terminal 2: ManagedCluster**
```bash
# First check: was it created?
oc get managedcluster example-hcp-disabled

# Then watch status
oc get managedcluster example-hcp-disabled -w
```

**Terminal 3: NodePool**
```bash
oc get nodepool -n clusters example-hcp-disabled-workers -w
```

Timeline:
- T+0m: Argo syncs resources
- T+1m: HostedCluster, NodePool, ManagedCluster all created
- T+10m: HostedCluster becomes Available
- T+12m: Klusterlet starts deploying to hosted cluster
- T+15m: First worker nodes joining
- T+30m: All nodes Ready and cluster fully available

## Validation

### HostedCluster with Disabled Auto-Import

Verify annotation is set:
```bash
oc get hostedcluster -n clusters example-hcp-disabled -o jsonpath='{.metadata.annotations.cluster\.open-cluster-management\.io/managedcluster-name}'
```

Expected: `` (empty string)

### HostedCluster Ready

```bash
oc get hostedcluster -n clusters example-hcp-disabled
```

Expected: AVAILABLE = True

### ManagedCluster Created from Git

Verify ManagedCluster exists:
```bash
oc get managedcluster example-hcp-disabled
```

Expected: ManagedCluster resource exists

Check labels we defined in Git:
```bash
oc get managedcluster example-hcp-disabled -L environment,import-pattern
```

Expected: Shows the labels from managedcluster.yaml

Check it's joinable:
```bash
oc get managedcluster example-hcp-disabled -o jsonpath='{.spec.hubAcceptsClient}'
```

Expected: `true`

### KlusterletAddonConfig Applied

```bash
oc get klusterletaddonconfig -n example-hcp-disabled
```

Expected: Shows the addon config

Check what addons are enabled:
```bash
oc get klusterletaddonconfig -n example-hcp-disabled -o yaml | grep "enabled: true"
```

### Klusterlet Deployed

```bash
oc get pods -n example-hcp-disabled
```

Expected: klusterlet pods running in hosted cluster

### Workers Ready

```bash
oc get nodepool -n clusters example-hcp-disabled-workers
```

Expected: READY = 2/2

### Access Hosted Cluster

```bash
# Get kubeconfig
oc get secret -n clusters example-hcp-disabled-admin-kubeconfig \
  -o jsonpath='{.data.kubeconfig}' | base64 -d > /tmp/example-hcp-disabled-kubeconfig

# Test access
export KUBECONFIG=/tmp/example-hcp-disabled-kubeconfig
oc get nodes
oc get clusteroperators
```

Expected:
- 2 worker nodes in Ready state
- All cluster operators available

## GitOps Workflow

### Making Changes

This pattern enables full GitOps workflows:

**Example 1: Add a label to the ManagedCluster**

1. Edit `managedcluster.yaml`
2. Add label in spec.labels:
   ```yaml
   labels:
     new-team: platform
   ```
3. Commit and push
4. Argo detects change and syncs
5. Label appears on cluster immediately

**Example 2: Enable/disable an addon**

1. Edit `klusterlet-addon-config.yaml`
2. Change `enabled: false` to `enabled: true` (or vice versa)
3. Commit and push
4. Argo syncs and updates addon configuration
5. Addon deployed/removed from cluster

**Example 3: Change node count**

1. Edit `nodepool.yaml`
2. Change `spec.replicas: 2` to `spec.replicas: 3`
3. Commit and push
4. Argo syncs the change
5. New worker node automatically created

### Full Audit Trail

All changes leave a Git history:

```bash
git log --oneline examples/gitops-kubevirt/02-auto-import/disabled/

# Example output:
# a1b2c3d Enable search addon for cluster
# e5f6g7h Scale cluster to 3 workers
# i9j0k1l Create example-hcp-disabled cluster
```

Every change has:
- What changed (YAML diff)
- Who changed it (commit author)
- When it changed (timestamp)
- Why it changed (commit message)

## Coordination Between Resources

This pattern requires coordinating multiple resources:

### Resource Dependencies

```
HostedCluster (disables auto-import)
    ↓ (must exist first)
    ├─→ NodePool (workers for HC)
    │    ↓
    └─→ ManagedCluster (explicit registration)
         ↓ (waits for HC to be available)
         └─→ KlusterletAddonConfig (addon setup)
             ↓ (addons deploy to hosted cluster)
             └─→ Klusterlet manifests deployed
```

### Critical Ordering

1. **HostedCluster** must be created first
   - MCE will detect it (but won't auto-import due to annotation)
2. **ManagedCluster** can be created simultaneously
   - It doesn't matter if HC or MC is created first
3. **KlusterletAddonConfig** must reference the cluster name
   - Must match ManagedCluster name
4. **Klusterlet deployment** happens automatically
   - MCE detects ManagedCluster and deploys klusterlet

This pattern handles all dependencies correctly when deployed via Argo.

## Pros and Cons

### Pros
✓ **Full Git Control** - Everything versioned and tracked
✓ **Reproducible** - Exact same configuration every time
✓ **Audit Trail** - Complete Git history of all changes
✓ **Pre-Configuration** - Set labels and addons before import
✓ **Compliance** - Meets strict GitOps requirements
✓ **Production Ready** - Suitable for production use
✓ **Pull Request Workflow** - Changes require review

### Cons
✗ **More YAML** - Additional managedcluster.yaml
✗ **More Coordination** - Must manage multiple resources
✗ **Slower to Update** - Changes need Git → PR → Merge → Sync
✗ **Learning Curve** - Must understand ManagedCluster concepts
✗ **Longer Setup** - Takes ~35-45 minutes
✗ **Not for Demos** - More ceremony for quick prototypes

## Best Use Cases

This pattern is ideal for:

- **Production Environments** - Full control and audit
- **Compliance Teams** - Git audit trails required
- **GitOps-First** - Everything in version control
- **Enterprise Deployments** - Change management required
- **Single Cluster** - Full focus on one cluster
- **Policy Enforcement** - Configure policies from day 1
- **Cost Centers** - Track cluster configurations per team

## Not Recommended For

- **Quick Demos** - Too much setup ceremony
- **Learning Environments** - More complex than needed
- **Ephemeral Clusters** - Overkill for temporary resources
- **Fully Automated** - Manual coordination needed
- **Fleet Management** - Too much per-cluster configuration

## Troubleshooting

### ManagedCluster Not Joining

**Check annotation on HostedCluster:**
```bash
oc get hostedcluster -n clusters example-hcp-disabled -o jsonpath='{.metadata.annotations.cluster\.open-cluster-management\.io/managedcluster-name}'
```

Should output: `` (empty string)

**Check ManagedCluster exists:**
```bash
oc get managedcluster example-hcp-disabled
oc describe managedcluster example-hcp-disabled
```

**Check klusterlet deployment:**
```bash
oc get manifestwork -n example-hcp-disabled
oc logs -n example-hcp-disabled -l app=klusterlet
```

### Addon Config Not Applied

**Check namespace exists:**
```bash
oc get namespace example-hcp-disabled
```

If not, create it first:
```bash
oc create namespace example-hcp-disabled
```

**Check config was created:**
```bash
oc get klusterletaddonconfig -n example-hcp-disabled
```

**Check Argo synced:**
```bash
argocd app get example-hcp-disabled
```

### Out of Sync in Argo

Manually re-sync:
```bash
argocd app sync example-hcp-disabled --force
```

Or fix via Argo console:
1. Open Argo console
2. Click on `example-hcp-disabled`
3. Check for errors in "Result" section
4. Click **SYNC** to force reconciliation

## Upgrading from Full-Auto

If coming from Full-Auto pattern:

1. **Create explicit ManagedCluster YAML:**
   - Copy labels from auto-created MC
   - Add KlusterletAddonConfig

2. **Add annotation to HostedCluster:**
   - Add: `cluster.open-cluster-management.io/managedcluster-name: ""`

3. **Delete auto-created ManagedCluster:**
   - `oc delete managedcluster example-hcp-auto`
   - Watch for klusterlet to be reinstalled

4. **Let Argo recreate from explicit YAML:**
   - Resources will stabilize in Git-defined state

## Cleanup

To remove this cluster:

```bash
# Option 1: Delete via Argo (cleanest)
argocd app delete example-hcp-disabled --cascade

# Option 2: Delete resources directly
oc delete hostedcluster -n clusters example-hcp-disabled
oc delete nodepool -n clusters example-hcp-disabled-workers
oc delete managedcluster example-hcp-disabled
```

This will trigger cleanup of:
- HostedCluster and control plane
- NodePool and worker VMs
- ManagedCluster and klusterlet
- KlusterletAddonConfig

Wait 5-10 minutes for full cleanup.

## See Also

- [Full-Auto Pattern](../full-auto/) - Simpler, fully automated
- [Hybrid Pattern](../hybrid/) - Production fleet management
- [Architecture Overview](../../../docs/gitops/01-architecture.md)
- [ACM Documentation](https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes/)
