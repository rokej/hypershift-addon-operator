# Scenario 2: Auto-Import Patterns for ACM Integration

## Overview

Scenario 2 explores how ACM discovers and manages hosted clusters automatically after HyperShift provisions them.

**Key Concept:** When a HostedCluster is created, HyperShift deploys a klusterlet (ACM agent). ACM detects this registration and automatically creates a ManagedCluster. This enables policy enforcement, governance, and cluster console access.

**Three patterns explained:**
1. Full-Auto: Complete automatic import
2. Disabled: Manual control, no auto-import
3. Hybrid: Selective auto-import

---

## Import Timeline - The Observable Journey

This section shows the minute-by-minute progression from HostedCluster creation to full ACM management. Each phase includes observable state and verification commands.

### Auto-Import Timeline Diagram

```
Timeline: HyperShift → ACM Auto-Import (0-20 minutes)

T+0min                T+5min              T+8min              T+10min             T+15min
│                     │                   │                   │                   │
│ HostedCluster      │ Control Plane     │ ManagedCluster    │ Klusterlet        │ Registration
│ Created            │ Available         │ Created           │ Deployed          │ Complete
│                     │                   │                   │                   │
▼                     ▼                   ▼                   ▼                   ▼
┌─────────────────┐  ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│ Argo CD         │  │ HyperShift      │ │ hypershift-     │ │ cluster-import- │ │ Klusterlet      │
│ applies HC/NP   │─>│ creates control │─>│ addon-agent     │─>│ controller      │─>│ registers HC    │
│ manifests       │  │ plane pods      │ │ creates         │ │ deploys         │ │ with Hub        │
│                 │  │                 │ │ ManagedCluster  │ │ klusterlet +    │ │                 │
│                 │  │                 │ │                 │ │ external-       │ │                 │
│                 │  │                 │ │                 │ │ managed-        │ │                 │
│                 │  │                 │ │                 │ │ kubeconfig      │ │                 │
└─────────────────┘  └─────────────────┘ └─────────────────┘ └─────────────────┘ └─────────────────┘
        │                     │                   │                   │                   │
    Verify:             Verify:             Verify:             Verify:             Verify:
    kubectl get hc      kubectl get pods    kubectl get         kubectl get pods    kubectl get
                        -n hosted-*         managedcluster      -n klusterlet-*     managedcluster
                                                                kubectl get secret   (status=Available)
                                                                external-managed-
                                                                kubeconfig
```

### Phase 1: HyperShift Creates Control Plane (T+0 to T+5)

**What Happens:**

1. Argo CD applies HostedCluster and NodePool manifests to the Hub
2. HyperShift operator detects new HostedCluster resource
3. HyperShift creates hosted-<name> namespace for control plane
4. Control plane pods start: etcd, kube-apiserver, controllers
5. Pull secret and SSH key mounted from pre-created secrets
6. Worker node provisioning begins (parallel process)

**Observable State:**

```bash
# Check HostedCluster status (early state)
kubectl get hostedcluster -n clusters example-hcp -o wide

# Expected output (early):
# NAME          AVAILABLE   PROGRESSING   AGE
# example-hcp   False       True          2m

# Check control plane pods being created
kubectl get pods -n clusters-example-hcp

# Expected output (in progress):
# NAME                                READY   STATUS              AGE
# etcd-0                              1/1     Running             1m30s
# kube-apiserver-0                    0/1     ContainerCreating   1m
# kube-controller-manager-0           0/1     Pending             30s
```

**Verification Commands:**

```bash
# Check detailed Available condition
kubectl get hostedcluster -n clusters example-hcp \
  -o jsonpath='{.status.conditions[?(@.type=="Available")]}' | jq

# Expected (early): status: "False", reason: "HostedClusterAsExpected"
# Expected (ready): status: "True", reason: "AsExpected"

# Check all control plane pods are Running
kubectl get pods -n clusters-example-hcp --field-selector=status.phase!=Running

# Expected (when ready): No resources found
```

**When to Move to Next Phase:** HostedCluster Available=True

---

### Phase 2: ACM Detects Hosted Cluster (T+5 to T+8)

**What Happens:**

1. hypershift-addon-agent (ACM controller) detects HostedCluster is Available
2. hypershift-addon-agent creates ManagedCluster resource
3. Annotations automatically set:
   - `import.open-cluster-management.io/klusterlet-deploy-mode: "Hosted"`
   - `cluster.open-cluster-management.io/createdVia: "hypershift"`
4. Labels automatically set:
   - `cloud: auto`
   - `vendor: auto`

**Observable State:**

```bash
# Check if ManagedCluster was created
kubectl get managedcluster example-hcp

# Expected output:
# NAME          HUB ACCEPTED   MANAGED CLUSTER URLS   JOINED   AVAILABLE   AGE
# example-hcp   true                                  Unknown  Unknown     10s
```

**Verification Commands:**

```bash
# Check ManagedCluster annotations (CRITICAL for hosted clusters)
kubectl get managedcluster example-hcp -o yaml | grep -A 5 annotations

# Expected:
#   annotations:
#     cluster.open-cluster-management.io/createdVia: hypershift
#     import.open-cluster-management.io/klusterlet-deploy-mode: Hosted

# Check ManagedCluster labels
kubectl get managedcluster example-hcp -o jsonpath='{.metadata.labels}' | jq

# Expected to include:
#   "vendor": "auto",
#   "cloud": "auto"

# Check which controller created it (hypershift-addon-agent)
kubectl get managedcluster example-hcp \
  -o jsonpath='{.metadata.annotations.cluster\.open-cluster-management\.io/createdVia}'

# Expected: hypershift
```

**When to Move to Next Phase:** ManagedCluster resource exists

---

### Phase 3: Klusterlet Deployment (T+8 to T+10)

**What Happens:**

1. cluster-import-controller detects new ManagedCluster with `klusterlet-deploy-mode: "Hosted"`
2. cluster-import-controller creates klusterlet-<name> namespace on Hub
3. cluster-import-controller deploys klusterlet deployment to Hub (NOT to hosted cluster)
4. hypershift-addon-agent creates external-managed-kubeconfig secret
5. Secret contains kubeconfig pointing to hosted cluster API

**Observable State:**

```bash
# Check klusterlet namespace exists on Hub
kubectl get namespace | grep klusterlet-example-hcp

# Expected: klusterlet-example-hcp namespace listed

# Check klusterlet pods on Hub
kubectl get pods -n klusterlet-example-hcp

# Expected output:
# NAME                                READY   STATUS    AGE
# klusterlet-registration-<hash>      1/1     Running   30s
# klusterlet-work-<hash>              1/1     Running   30s

# Check external-managed-kubeconfig secret exists
kubectl get secret -n klusterlet-example-hcp external-managed-kubeconfig

# Expected: secret listed
```

**Verification Commands:**

```bash
# Verify klusterlet deployment exists
kubectl get deployment -n klusterlet-example-hcp

# Expected: At least one deployment named "klusterlet-*"

# Check external-managed-kubeconfig secret content
kubectl get secret -n klusterlet-example-hcp external-managed-kubeconfig \
  -o jsonpath='{.data.kubeconfig}' | base64 -d | head -10

# Expected: Valid kubeconfig YAML showing hosted cluster API server URL

# Validate kubeconfig points to correct cluster
kubectl get secret -n klusterlet-example-hcp external-managed-kubeconfig \
  -o jsonpath='{.data.kubeconfig}' | base64 -d | grep "server:"

# Expected: server: https://api.example-hcp.example.com:6443
```

**When to Move to Next Phase:** Klusterlet pods Running AND external-managed-kubeconfig exists

---

### Phase 4: Registration (T+10 to T+15)

**What Happens:**

1. Klusterlet pod starts on Hub cluster
2. Klusterlet reads external-managed-kubeconfig secret
3. Klusterlet connects to hosted cluster API using the kubeconfig
4. Klusterlet registers hosted cluster with ACM Hub
5. ManagedCluster status updates: Joined=True, then Available=True

**Observable State:**

```bash
# Watch ManagedCluster conditions evolve
kubectl get managedcluster example-hcp \
  -o jsonpath='{.status.conditions[*].type}' | tr ' ' '\n'

# Expected progression:
# HubAcceptedManagedCluster
# ManagedClusterJoined
# ManagedClusterConditionAvailable

# Check full ManagedCluster status
kubectl get managedcluster example-hcp -o yaml | grep -A 30 "status:"

# Expected: conditions showing progression to Available
```

**Verification Commands:**

```bash
# Check ManagedCluster is joined
kubectl get managedcluster example-hcp \
  -o jsonpath='{.status.conditions[?(@.type=="ManagedClusterJoined")].status}'
# Expected: True

# Check ManagedCluster is available
kubectl get managedcluster example-hcp \
  -o jsonpath='{.status.conditions[?(@.type=="ManagedClusterConditionAvailable")].status}'
# Expected: True

# Check klusterlet logs for successful registration
kubectl logs -n klusterlet-example-hcp deployment/klusterlet-registration-agent --tail=50 | grep -i "cluster registered\|registration successful"

# Expected: Log entries showing successful registration
```

**When to Move to Next Phase:** ManagedCluster status Available=True AND Joined=True

---

### Phase 5: Management Enabled (T+15+)

**What Happens:**

1. ManagedCluster status fully reconciled (Available=True, Joined=True)
2. ManagedClusterInfo resource gets populated with cluster details
3. ACM add-ons deployed based on KlusterletAddonConfig
4. Cluster appears in ACM console
5. Policies and governance can now be applied

**Observable State:**

```bash
# Check ManagedCluster final status
kubectl get managedcluster example-hcp -o wide

# Expected:
# NAME          HUB ACCEPTED   MANAGED CLUSTER URLS                    JOINED   AVAILABLE   AGE
# example-hcp   true           https://api.example-hcp.example.com     True     True        5m

# Check ManagedClusterInfo populated
kubectl get managedclusterinfo -n example-hcp example-hcp -o yaml | head -50

# Expected: Detailed cluster information including version, nodes, etc.
```

**Verification Commands:**

```bash
# Complete verification - all resources healthy
kubectl get managedcluster example-hcp && \
kubectl get managedclusterinfo -n example-hcp example-hcp && \
kubectl get klusterletaddonconfig -n example-hcp example-hcp

# All should exist and show healthy status

# Check node inventory in ManagedClusterInfo
kubectl get managedclusterinfo -n example-hcp example-hcp \
  -o jsonpath='{.status.nodeList[*].name}' | tr ' ' '\n'

# Expected: List of worker node names

# Verify cluster appears in ACM (if console access available)
# Navigate to: ACM Console → Clusters → All Clusters
# Expected: example-hcp listed with status "Ready"
```

**Import Complete!** The hosted cluster is now fully managed by ACM.

---

### Complete Timeline Summary

| Time | Phase | Component | Key Event | Verification Command |
|------|-------|-----------|-----------|---------------------|
| T+0 | 1 | GitOps | HostedCluster created | `kubectl get hc -n clusters` |
| T+5 | 1 | HyperShift | Control plane Available | `kubectl get hc -o jsonpath='{.status.conditions...}'` |
| T+8 | 2 | ACM | ManagedCluster created by hypershift-addon-agent | `kubectl get managedcluster` |
| T+10 | 3 | ACM | Klusterlet deployed to Hub by cluster-import-controller | `kubectl get pods -n klusterlet-*` |
| T+10 | 3 | ACM | external-managed-kubeconfig created | `kubectl get secret -n klusterlet-* external-managed-kubeconfig` |
| T+12 | 4 | ACM | Registration handshake begins | `kubectl get managedcluster -o jsonpath='{.status.conditions...}'` |
| T+15 | 4-5 | ACM | ManagedCluster Available=True | `kubectl get managedcluster -o wide` |
| T+15+ | 5 | ACM | Management fully enabled | `kubectl get managedclusterinfo -n <name>` |

### Common Timeline Deviations

**Faster than expected (<10 minutes):**
- Small control plane (SingleReplica)
- Fast image pulls (cached)
- Quick network provisioning

**Slower than expected (>20 minutes):**
- Large control plane (HighlyAvailable with 3 replicas)
- Slow image pulls (first time, large images)
- Network provisioning delays
- Resource contention on Hub

**Troubleshooting stuck imports:**
- See [Section 5: Troubleshooting Import Issues](#troubleshooting-import-issues) below
- Check [08-troubleshooting.md](./08-troubleshooting.md) Part B for detailed diagnostics

---

## Pattern 1: Full-Auto Import

### What Happens

```
Create HostedCluster
    ↓ (HyperShift)
Deploy klusterlet
    ↓ (klusterlet agent)
Register with ACM Hub
    ↓ (ACM controller)
Create ManagedCluster
    ↓ (Kubernetes)
Available in ACM console
```

**Timeline:** Cluster appears in ACM in 10-15 minutes automatically.

### Configuration

Nothing special needed! Just create a HostedCluster normally:

```yaml
apiVersion: hypershift.openshift.io/v1beta1
kind: HostedCluster
metadata:
  name: example-hcp
  namespace: clusters
spec:
  baseDomain: example.com
  release:
    image: quay.io/openshift-release-dev/ocp-release:4.17.0-x86_64
  # ... rest of spec
  # By default, klusterlet is deployed = auto-import enabled
```

### What ACM Creates Automatically

When the cluster is detected, ACM creates:

```yaml
# 1. ManagedCluster (cluster representation)
apiVersion: cluster.open-cluster-management.io/v1
kind: ManagedCluster
metadata:
  name: example-hcp
spec:
  hubAcceptsClient: true
  leaseDurationSeconds: 60
status:
  conditions:
    - type: HubAccepted
      status: "True"
    - type: ManagedClusterJoined
      status: "True"
    - type: Available
      status: "True"

# 2. KlusterletAddonConfig (add-on configuration)
apiVersion: agent.open-cluster-management.io/v1
kind: KlusterletAddonConfig
metadata:
  name: example-hcp
  namespace: example-hcp
spec:
  clusterName: example-hcp
  clusterNamespace: example-hcp
  applicationManager:
    enabled: true
  policyController:
    enabled: true
  searchCollector:
    enabled: true

# 3. Namespace (cluster's namespace on Hub)
apiVersion: v1
kind: Namespace
metadata:
  name: example-hcp
```

### Verify Full-Auto

```bash
# 1. Check klusterlet deployment on Hub
kubectl get deployment -n open-cluster-management-agent \
  klusterlet-addon-* -A

# 2. Check ManagedCluster exists
kubectl get managedcluster example-hcp
# Should show: Available=True

# 3. Check in ACM console
# Login to Hub cluster ACM console
# Navigate to: Clusters > All Clusters
# Should see "example-hcp" with status "Ready"

# 4. Check cluster metadata
kubectl get managedcluster example-hcp -o json | \
  jq '.metadata.labels'
# Should show cloud, vendor, and other auto-added labels
```

### Advantages

- **Automatic:** No manual import steps
- **Fast:** Cluster ready for management in 10-15 minutes
- **Complete:** All ACM features available immediately
- **Safe:** Klusterlet is standard HyperShift component

### When to Use

- Production clusters
- Standard deployments
- When you want ACM governance
- Default choice for most users

---

## Pattern 2: Disabled Import

### What Happens

```
Create HostedCluster
    ↓ (HyperShift)
NO klusterlet deployed
    ↓
Cluster isolated
    ↓
No ACM management available
```

**Result:** Cluster works fine, just not managed by ACM.

### Configuration

To disable auto-import, don't deploy klusterlet:

```bash
# Modify HostedCluster to skip klusterlet
kubectl patch hostedcluster example-hcp -p \
  '{"spec":{"disableDestinationCA":true}}'
```

Or in manifests, use a custom HostedCluster configuration that omits klusterlet settings.

**Note:** There's no explicit "disable" flag. Instead, configure HyperShift to not deploy the agent pod.

### Alternative: Import Later

Deploy normally with auto-import, then delete the ManagedCluster:

```bash
# Cluster created with auto-import
# Then:
kubectl delete managedcluster example-hcp

# Cluster continues running on Hub
# Just not managed by ACM
# You can manually import later if needed
```

### When to Use

- Development/test clusters
- Air-gapped environments (no Hub connectivity)
- Temporary clusters (planning to delete soon)
- Complex custom configurations
- Early lifecycle (before production readiness)

### Disadvantages

- No ACM governance or policies
- No cluster console access via ACM
- Manual operations needed for cluster management
- No integration with ACM multi-cluster features

---

## Pattern 3: Hybrid Import

### What Happens

```
Cluster 1 (Full-Auto)    → Imported, Managed by ACM
Cluster 2 (Full-Auto)    → Imported, Managed by ACM
Cluster 3 (Disabled)     → Not imported, Independent

Same Hub managing mix
```

**Concept:** Some clusters auto-import, some don't, all on same Hub.

### Configuration

Simple: Just create some clusters with auto-import, others without:

```yaml
# In Git repository:

clusters/
├── production/
│   ├── hostedcluster.yaml      (will be auto-imported)
│   └── nodepool.yaml
│
├── development/
│   ├── hostedcluster.yaml      (will be auto-imported)
│   └── nodepool.yaml
│
└── testing/
    ├── hostedcluster.yaml      (disable import via delete)
    └── nodepool.yaml
```

Argo Application:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gitops-hcp-all
spec:
  source:
    path: clusters/
  destination:
    namespace: clusters
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

Then manually manage which are imported:

```bash
# Production: keep auto-import
kubectl get managedcluster prod-hcp

# Development: keep auto-import
kubectl get managedcluster dev-hcp

# Testing: delete ManagedCluster to disable import
kubectl delete managedcluster test-hcp
# Cluster still runs, just not managed
```

### Cluster-by-Cluster Control

```bash
# Get list of all clusters
kubectl get hostedcluster -A

# For each cluster, choose:
# - Auto-import: do nothing (default)
# - Disabled: kubectl delete managedcluster <name>
# - Re-enable: kubectl apply -f managedcluster-<name>.yaml
```

### When to Use

- Mixed environments (prod + test on same Hub)
- Gradual rollout (import prod, test others first)
- Different management levels needed
- Complex organizational requirements

### Advantages

- Flexibility per cluster
- Selective governance
- Easy on/off per cluster
- Matches real-world complexity

---

## Decision Tree

Choose your pattern:

```
                      Want cluster?
                         |
         ┌───────────────┼───────────────┐
         │               │               │
      Dev/Test        Production      Mixed
         │               │               │
    Disabled         Full-Auto        Hybrid
  (Simple,fast)  (Automatic,       (Flexible)
                 complete)
```

**Detailed decision tree:**

```
1. Is this a production cluster?
   ├─ YES → Full-Auto (recommended)
   └─ NO → Continue to 2

2. Do you need ACM features?
   ├─ YES → Full-Auto (recommended)
   └─ NO → Continue to 3

3. Is cluster temporary?
   ├─ YES → Disabled
   └─ NO → Continue to 4

4. Will this environment evolve?
   ├─ YES → Hybrid (start Disabled, move to Full-Auto later)
   └─ NO → Disabled
```

---

## Comparing the Three Patterns

| Aspect | Full-Auto | Disabled | Hybrid |
|--------|-----------|----------|--------|
| **Setup** | Default, nothing needed | Modify HCP config | Per-cluster choice |
| **Time to ready** | 10-15 min | N/A (no ACM) | 10-15 min per cluster |
| **ACM features** | All available | None | Per-cluster choice |
| **Governance** | ACM policies apply | Manual control | Mixed |
| **Console access** | Via ACM | Direct only | Mixed |
| **Cluster dashboard** | Full | Basic | Mixed |
| **Policy enforcement** | Automatic | Manual | Mixed |
| **Disaster recovery** | ACM-integrated | Manual | Mixed |
| **Effort** | Minimal | Minimal | Medium |
| **Flexibility** | Good | Excellent | Best |

---

## ACM Features by Pattern

### Available with Full-Auto (or Hybrid when enabled)

```
✓ Cluster dashboard in ACM console
✓ Multi-cluster application deployment (Application CRD)
✓ Governance policies (ConfigurationPolicy)
✓ Compliance scanning
✓ Multi-cluster observability
✓ Automatic cluster health monitoring
✓ Cluster resource quotas
✓ Network policy enforcement
✓ Image vulnerability scanning
```

### Not Available with Disabled Import

```
✗ ACM console management
✗ Multi-cluster app deployment via ACM
✗ ACM policies
✗ Multi-cluster observability
```

But cluster still works fine for:
```
✓ Deploying applications directly
✓ Using cluster's native Argo CD
✓ Local monitoring and management
✓ Direct kubectl access
```

---

## Migration Paths

### Path 1: Disabled → Full-Auto

Start with testing, then enable ACM:

```bash
# Initially: cluster created, no auto-import
# Later, when ready:
# Apply standard ManagedCluster
kubectl apply -f - <<EOF
apiVersion: cluster.open-cluster-management.io/v1
kind: ManagedCluster
metadata:
  name: example-hcp
spec:
  hubAcceptsClient: true
  leaseDurationSeconds: 60
EOF

# Redeploy klusterlet
kubectl rollout restart deployment/hypershift-operator \
  -n hypershift-system

# Wait for klusterlet to deploy
sleep 30
kubectl get managedcluster example-hcp
```

### Path 2: Full-Auto → Disabled

Remove ACM management temporarily:

```bash
# Delete ManagedCluster (cluster continues running)
kubectl delete managedcluster example-hcp

# Cluster still works, just not ACM-managed
# Can re-enable later by recreating ManagedCluster
```

### Path 3: Single Cluster → Full-Auto

Add more clusters and scale:

```bash
# First cluster: careful setup
# Later clusters: copy/replicate pattern
# All automatically discovered by ACM
```

---

## Enterprise Considerations

### Governance Requirements

**Requirement:** All clusters must be managed by ACM for compliance

**Solution:** Use Full-Auto, use policy enforcement

```yaml
# Ensure all clusters are imported:
apiVersion: cluster.open-cluster-management.io/v1
kind: ClusterClaim
metadata:
  name: open-cluster-management.io/clusterset-admin
spec:
  # All clusters must respond to ClusterSet selections
```

### Organizational Boundaries

**Requirement:** Different teams manage different clusters

**Solution:** Use Hybrid or namespace-based Disabled pattern

```yaml
# Team A clusters (Production) → Full-Auto
# Team B clusters (Testing) → Disabled or Hybrid
# Separate RBAC and policies per team
```

### Air-Gapped Environments

**Requirement:** No outbound Hub connectivity

**Solution:** Use Disabled or Disconnected Agents

```bash
# Disconnected agent pattern (separate from Full-Auto)
# Agent pulls policies from Hub via pull instead of push
# Requires agent-pull-agent addon
```

### Multi-Hub Scenario

**Requirement:** Cluster managed by multiple ACM instances

**Solution:** Deploy multiple klusterlets with different configurations

```bash
# Each klusterlet connects to different Hub
# Each Hub sees same cluster
# Enables disaster recovery and failover
```

---

## Troubleshooting Auto-Import

### Issue: ManagedCluster Never Appears

**Diagnosis:**

```bash
# Check if klusterlet pod exists
kubectl get pods -A | grep klusterlet

# Check klusterlet logs
kubectl logs -n open-cluster-management-agent <pod> -f

# Check control plane health
kubectl get hostedcluster example-hcp
# Must be Available=True

# Check kubeconfig secret
kubectl get secret -n clusters admin-kubeconfig
```

**Solutions:**

```bash
# 1. If klusterlet not deployed:
kubectl rollout restart deployment/hypershift-operator \
  -n hypershift-system
sleep 30

# 2. If klusterlet can't connect to Hub:
# Check network policies
# Verify DNS resolution
# Check certificate validity

# 3. If control plane not ready:
# Wait for Available=True
# Then klusterlet will deploy
```

### Issue: ManagedCluster in "Not Ready" Status

**Diagnosis:**

```bash
# Check detailed status
kubectl get managedcluster example-hcp -o json | \
  jq '.status.conditions'

# Check agent logs
kubectl logs -n open-cluster-management-agent <pod> -f
```

**Solutions:**

```bash
# 1. Network connectivity issue:
# Ensure Hub can reach cluster
# Check firewalls, security groups

# 2. Certificate expired:
kubectl rollout restart deployment/klusterlet-addon-apimgr \
  -n open-cluster-management-agent

# 3. Hub API not responding:
# Check Hub cluster health
# Check connectivity from agents
```

### Issue: Want to Disable Import After Auto-Import

**Solution:**

```bash
# Simply delete the ManagedCluster
kubectl delete managedcluster example-hcp

# Cluster continues running
# klusterlet pod still exists (can redeploy if needed)
# Just no longer synced to ACM
```

---

## Observability

### Check Import Status

```bash
# Cluster status
kubectl get hostedcluster -n clusters example-hcp -o wide

# Agent status
kubectl get managedcluster example-hcp -o wide

# Detailed conditions
kubectl get managedcluster example-hcp -o json | \
  jq '.status.conditions'

# Expected output:
# - type: HubAccepted, status: True
# - type: ManagedClusterJoined, status: True
# - type: Available, status: True
```

### Check Klusterlet Deployment

```bash
# Deployment status
kubectl get deployment -n open-cluster-management-agent \
  -A | grep example-hcp

# Pod status
kubectl get pods -n open-cluster-management-agent

# Logs
kubectl logs -n open-cluster-management-agent \
  <pod> -f

# Agent health
kubectl top pods -n open-cluster-management-agent
```

### Monitor via ACM Console

```bash
# Web UI approach:
# 1. Login to Hub cluster
# 2. Navigate to: Clusters > All Clusters
# 3. Click on cluster name
# 4. View status, conditions, events
```

---

## Best Practices

1. **Default to Full-Auto** - Easiest and most complete
2. **Document your choice** - Add comments explaining pattern
3. **Consistent policy** - Use same pattern for similar clusters
4. **Monitor imports** - Verify ManagedCluster creation regularly
5. **Plan migrations** - Know how to move between patterns
6. **Test first** - Try pattern on dev before prod
7. **Secure connectivity** - Ensure Hub ↔ Cluster security

---

## Next Steps

- [06-managing-scale-operations.md](./06-managing-scale-operations.md) - Scenario 3: Scaling operations
- [07-managing-upgrades.md](./07-managing-upgrades.md) - Scenario 4: Cluster upgrades
- [08-troubleshooting.md](./08-troubleshooting.md) - Troubleshooting guide

---

**Last Updated:** April 2, 2026
