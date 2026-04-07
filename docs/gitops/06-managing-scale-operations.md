# Scenario 3: Scaling and NodePool Management

## Overview

Scenario 3 demonstrates scaling operations on hosted clusters through GitOps. All operations are declarative (Git-based) rather than imperative (manual commands).

**What you'll learn:**
- Horizontal scaling (adding/removing nodes)
- Vertical scaling (changing node resources)
- Autoscaling with the Cluster Autoscaler
- Multi-NodePool management
- Safe removal procedures

**Duration:** 45-90 minutes  
**Location:** `examples/gitops-kubevirt/03-scaling/`

---

## Scaling Operations Overview

### Horizontal Scaling

Add or remove worker nodes:

```yaml
# Current state:
spec:
  replicas: 2

# After scaling up:
spec:
  replicas: 5

# After scaling down:
spec:
  replicas: 2
```

**Time:** 10-20 minutes per node  
**Rollback:** Revert Git commit

### Vertical Scaling

Change resource limits per node:

```yaml
# Current state:
spec:
  platform:
    kubevirt:
      cores: 2
      memory: 8Gi

# After scaling up:
spec:
  platform:
    kubevirt:
      cores: 4
      memory: 16Gi
```

**Time:** 20-40 minutes (nodes replaced)  
**Rollback:** Revert Git commit

### Autoscaling

Enable automatic scaling based on demand:

```yaml
# Enable autoscaling
spec:
  autoScaling:
    min: 2
    max: 8
```

**Time:** 5-10 minutes per scale event  
**How:** Cluster Autoscaler watches for pending pods

### Multi-NodePool

Create specialized node groups:

```yaml
# Worker pool (general purpose)
- name: worker
  replicas: 3
  labels:
    workload: general

# Infra pool (system components)
- name: infra
  replicas: 2
  taints:
    - key: node-role.kubernetes.io/infra
      value: reserved
      effect: NoSchedule
  labels:
    node-role.kubernetes.io/infra: ""
```

**Use cases:** Separating workloads, cost allocation, compliance

---

## Horizontal Scaling: Scale Up

### Scenario: Increase from 2 to 5 Nodes

**Use case:** Application needs more capacity

#### Step 1: Update Git Manifest

```bash
# Edit NodePool manifest
nano base/nodepool.yaml
```

Change:
```yaml
spec:
  replicas: 2  # old
```

To:
```yaml
spec:
  replicas: 5  # new
```

#### Step 2: Commit and Push

```bash
git checkout -b scale-up
git add base/nodepool.yaml
git commit -m "Scale up to 5 nodes for peak demand"
git push origin scale-up

# Create PR, wait for approval, merge to main
```

#### Step 3: Argo Detects and Syncs

```bash
# Monitor Argo sync (automatic if auto-sync enabled)
watch -n 5 kubectl get application -n argocd gitops-hcp-scenario3

# Should show: Synced, Healthy
```

#### Step 4: Watch Machines Provision

```bash
# On Hub cluster, watch machine creation
watch -n 10 'kubectl get machines -A'

# Expected progression:
# T+0m: 2 Running + 3 Provisioning
# T+5m: 2 Running + 3 Provisioning
# T+15m: 5 Running

# Check HCP nodes
watch -n 5 'kubectl --kubeconfig=hcp.yaml get nodes'

# Expected progression:
# T+0m: 2 Ready
# T+15m: 5 Ready
```

#### Step 5: Verify Success

```bash
# Nodes should all be Ready
kubectl --kubeconfig=hcp.yaml get nodes
# NAME    STATUS   ROLES    AGE
# node1   Ready    worker   3h
# node2   Ready    worker   3h
# node3   Ready    worker   10m
# node4   Ready    worker   10m
# node5   Ready    worker   10m

# Pods should be schedulable
kubectl --kubeconfig=hcp.yaml get pods -A | grep -v Running
# Should see no Pending pods
```

#### Rollback (if needed)

```bash
# Revert Git commit
git revert HEAD

# Or edit again
nano base/nodepool.yaml
# Change replicas: 5 back to replicas: 2
git add base/nodepool.yaml
git commit -m "Rollback scaling to 2 nodes"
git push origin main

# Argo will scale down
# Takes 10-20 minutes as nodes drain
```

---

## Vertical Scaling: Change Node Resources

### Scenario: Increase CPU/Memory per Node

**Use case:** Application needs more resources per container

#### Step 1: Update Manifest

```bash
nano base/nodepool.yaml
```

Change:
```yaml
spec:
  platform:
    kubevirt:
      cores: 2
      memory: 8Gi
```

To:
```yaml
spec:
  platform:
    kubevirt:
      cores: 4
      memory: 16Gi
```

#### Step 2: Commit and Push

```bash
git checkout -b vertical-scale
git add base/nodepool.yaml
git commit -m "Increase node resources: 2c/8Gi → 4c/16Gi"
git push origin vertical-scale

# Create PR, merge after approval
```

#### Step 3: Monitor Node Replacement

```bash
# Horizontal Pod Autoscaler will:
# 1. Create new machine with new resources
# 2. Drain old machine
# 3. Delete old machine

watch -n 10 'kubectl get machines -A'

# Expected progression:
# T+0m: 2 existing machines
# T+2m: 2 existing + 1 new machine (provisioning)
# T+15m: 1 existing + 1 new machine (draining old)
# T+20m: 2 new machines only

watch -n 5 'kubectl --kubeconfig=hcp.yaml get nodes'

# Expected progression:
# T+0m: 2 Ready (small)
# T+15m: 2 Ready (one small, one large)
# T+20m: 2 Ready (both large)
```

#### Step 4: Verify

```bash
# Check node resources
kubectl --kubeconfig=hcp.yaml describe node | grep -A 5 "Allocated resources"

# Should show increased capacity
# Capacity: cpu: 4, memory: 16Gi
```

---

## Autoscaling: Enable Auto-Scaling

### Scenario: Enable Cluster Autoscaler

**Use case:** Workload varies; want automatic scaling

#### Configuration

```yaml
spec:
  autoScaling:
    min: 2  # Minimum nodes
    max: 8  # Maximum nodes
```

#### Step 1: Update Manifest

```bash
nano base/nodepool.yaml
```

Change from:
```yaml
spec:
  replicas: 2
```

To:
```yaml
spec:
  autoScaling:
    min: 2
    max: 8
  # NOTE: remove "replicas" field
```

#### Step 2: Deploy via Git

```bash
git checkout -b enable-autoscaling
git add base/nodepool.yaml
git commit -m "Enable autoscaling: min=2, max=8"
git push origin enable-autoscaling

# Merge to main after approval
```

#### Step 3: Verify Autoscaler Deployed

```bash
# Cluster Autoscaler should run on control plane
kubectl get deployment -n clusters-example-hcp \
  cluster-autoscaler

# Check logs
kubectl logs -n clusters-example-hcp \
  deployment/cluster-autoscaler -f
```

#### Step 4: Test Autoscaling

```bash
# Deploy a large job that requires multiple nodes
kubectl --kubeconfig=hcp.yaml apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: test-scaling
spec:
  parallelism: 10
  completions: 10
  template:
    spec:
      containers:
        - name: test
          image: busybox
          command: ["sleep", "60"]
          resources:
            requests:
              cpu: 1
              memory: 1Gi
      restartPolicy: Never
EOF

# Watch cluster scale
watch -n 5 'kubectl --kubeconfig=hcp.yaml get nodes'

# Expected: nodes scale from 2 to 4-5 as job pods pending
```

#### How Cluster Autoscaler Works

```
1. Job creates 10 pods requesting 1 CPU each
2. Nodes have only 2 CPUs (2 core nodes)
3. Autoscaler detects pending pods
4. Creates new machines to satisfy requests
5. As job completes, nodes empty
6. Autoscaler removes empty nodes (after ~10 min cooldown)
```

---

## Multi-NodePool: Create Additional Pools

### Scenario: Add Infrastructure NodePool

**Use case:** Separate system components from application nodes

#### Current State

```yaml
# Single worker pool
apiVersion: hypershift.openshift.io/v1beta1
kind: NodePool
metadata:
  name: worker
  namespace: clusters
spec:
  clusterName: example-hcp
  replicas: 3
```

#### Step 1: Create Infra Pool Manifest

```bash
# Create new operation file
cat > operations/04-add-nodepool.yaml <<'EOF'
apiVersion: hypershift.openshift.io/v1beta1
kind: NodePool
metadata:
  name: infra
  namespace: clusters
spec:
  clusterName: example-hcp
  replicas: 2
  
  platform:
    type: KubeVirt
    kubevirt:
      cores: 4
      memory: 16Gi
      rootVolume:
        accessModes: [ "ReadWriteOnce" ]
        storageClass: local
  
  # Mark as infrastructure nodes
  taints:
    - key: node-role.kubernetes.io/infra
      value: reserved
      effect: NoSchedule
  
  labels:
    node-role.kubernetes.io/infra: ""
    purpose: infrastructure
EOF
```

#### Step 2: Commit and Deploy

```bash
git add operations/04-add-nodepool.yaml
git commit -m "Add infrastructure NodePool with 2 replicas"
git push origin main

# Argo syncs automatically
```

#### Step 3: Verify Pool Creation

```bash
# Check both NodePools exist
kubectl get nodepool -n clusters
# NAME    CLUSTER       NODES
# worker  example-hcp   3
# infra   example-hcp   2

# Check machines created
kubectl get machines -A | grep infra

# Check nodes have taints
kubectl --kubeconfig=hcp.yaml get nodes -o wide

# Should see:
# node1-worker   Ready   worker      (no taints)
# node2-worker   Ready   worker      (no taints)
# node3-worker   Ready   worker      (no taints)
# node1-infra    Ready   infra       (tainted: infra=reserved:NoSchedule)
# node2-infra    Ready   infra       (tainted: infra=reserved:NoSchedule)
```

#### Step 4: Schedule Workload on Specific Pool

```bash
# System operator (tolerates infra taint)
kubectl --kubeconfig=hcp.yaml apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-infra
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test
  template:
    metadata:
      labels:
        app: test
    spec:
      tolerations:
        - key: node-role.kubernetes.io/infra
          operator: Equal
          value: reserved
          effect: NoSchedule
      nodeSelector:
        node-role.kubernetes.io/infra: ""
      containers:
        - name: test
          image: busybox
          command: ["sleep", "3600"]
EOF

# Pod should schedule on infra nodes only
kubectl --kubeconfig=hcp.yaml get pods -o wide
# Should show pod on infra node
```

---

## Safe NodePool Removal

### Scenario: Remove Infra Pool

**Important:** Never just delete a NodePool with running pods!

#### Step 1: Cordon the Pool

```bash
# Prevent new pods from scheduling
kubectl --kubeconfig=hcp.yaml cordon \
  -l node-role.kubernetes.io/infra=""

# Existing pods stay running
```

#### Step 2: Drain the Nodes

```bash
# Move workloads off nodes (with grace period)
kubectl --kubeconfig=hcp.yaml drain \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --grace-period=30 \
  -l node-role.kubernetes.io/infra=""

# Wait for drain to complete (1-5 minutes)
```

#### Step 3: Delete NodePool in Git

```bash
# Create removal operation
cat > operations/05-remove-nodepool.yaml <<'EOF'
# This file is intentionally empty
# It represents the state after nodepool deletion
# To complete removal, delete infra nodepool manifest
EOF

# Or simply remove from kustomization
# Edit kustomization.yaml, remove nodepool reference

git add operations/05-remove-nodepool.yaml
git commit -m "Remove infrastructure NodePool and drain nodes"
git push origin main
```

#### Step 4: Verify Removal

```bash
# NodePool should disappear
watch -n 10 'kubectl get nodepool -n clusters'

# Machines should be deleted
watch -n 10 'kubectl get machines -A | grep infra'

# After machines fully deleted:
kubectl --kubeconfig=hcp.yaml get nodes -l node-role.kubernetes.io/infra=""
# Should return empty
```

---

## Monitoring Scaling Operations

### Watch Cluster Scaling

```bash
# Terminal 1: Watch HostedCluster status
watch -n 5 'kubectl get hostedcluster -n clusters example-hcp'

# Terminal 2: Watch NodePool status
watch -n 5 'kubectl get nodepool -n clusters'

# Terminal 3: Watch machines
watch -n 10 'kubectl get machines -A'

# Terminal 4: Watch nodes in HCP
watch -n 5 'kubectl --kubeconfig=hcp.yaml get nodes -o wide'
```

### Check Node Capacity

```bash
# Current usage
kubectl --kubeconfig=hcp.yaml top nodes

# Current allocatable
kubectl --kubeconfig=hcp.yaml describe nodes | grep -A 5 "Allocatable"

# Pending pods
kubectl --kubeconfig=hcp.yaml get pods -A --field-selector=status.phase=Pending
```

### Monitor Autoscaler

```bash
# Autoscaler logs
kubectl logs -n clusters-example-hcp \
  deployment/cluster-autoscaler -f

# Watch for:
# "Pod doesn't fit on any node"
# "scale up:" messages
# "node group min size reached" warnings
```

---

## Best Practices

1. **Scale in small steps** - Don't 2→10; do 2→3→4→5
2. **Monitor continuously** - Watch each step complete
3. **Test scaling down** - Ensure pods drain cleanly
4. **Document in Git** - Every change tracked
5. **Have capacity plan** - Know max reasonable size
6. **Use Pod Disruption Budgets** - Protect important workloads
7. **Autoscale with caution** - Set max reasonable limit
8. **Review costs** - More nodes = higher costs

---

## Cost Considerations

### Calculate Node Cost

```
Per node cost:
- Compute: depends on platform
  - KubeVirt: underlying cluster resources
  - AWS: instance type cost
  - Azure: VM cost

Example AWS (us-east-1):
- m5.large (2 vCPU, 8 GB): $0.096/hour
- 2 nodes: $0.192/hour = ~$140/month
- 5 nodes: $0.480/hour = ~$350/month

Example Vertical Scaling:
- 2c/8Gi → 4c/16Gi
- Roughly double the cost per node
- 2 nodes 4c/16Gi = ~$280/month
```

### Autoscaling Impact

```
Cost varies with demand:
- Off-hours: 2 nodes running = low cost
- Peak hours: 8 nodes running = high cost
- Average: maybe 4-5 nodes = medium cost
- Automatic adjustment matches demand
```

---

## Troubleshooting Scaling

### Nodes Not Becoming Ready

See [08-troubleshooting.md](./08-troubleshooting.md#nodes-not-ready)

### Autoscaler Not Working

```bash
# Check autoscaler running
kubectl get deployment -n clusters-example-hcp cluster-autoscaler

# Check for pending pods
kubectl --kubeconfig=hcp.yaml get pods -A --field-selector=status.phase=Pending

# Check autoscaler logs
kubectl logs -n clusters-example-hcp \
  deployment/cluster-autoscaler -f | grep -i "scale up\|pending"
```

### Pod Eviction Issues During Drain

```bash
# Use Pod Disruption Budgets
kubectl --kubeconfig=hcp.yaml apply -f - <<EOF
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: app-pdb
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: myapp
EOF

# Now drain respects this SLA
```

---

## Next Steps

- [07-managing-upgrades.md](./07-managing-upgrades.md) - Scenario 4: Upgrade operations
- [08-troubleshooting.md](./08-troubleshooting.md) - Troubleshooting guide

---

**Last Updated:** April 2, 2026
