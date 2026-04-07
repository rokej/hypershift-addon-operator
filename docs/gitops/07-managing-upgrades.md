# Scenario 4: Progressive Upgrades via GitOps

## Overview

Scenario 4 demonstrates upgrading hosted clusters through GitOps. Updates happen declaratively (via Git changes) and progressively (control plane first, then nodes).

**Key Concepts:**
- Version skew policy (N-1 compatibility)
- Control plane vs. node upgrade coordination
- Replace vs. InPlace upgrade strategies
- Rollback procedures
- Production upgrade workflow

**Duration:** 90-120 minutes  
**Location:** `examples/gitops-kubevirt/04-upgrades/`

---

## Upgrade Path Overview

OpenShift requires careful upgrade sequencing:

### Standard Upgrade Path

```
HostedCluster (control plane): 4.16.1 → 4.17.0
                               ↓ (5-10 minutes)
NodePool: 4.16.1 → 4.17.0
          ↓ (30-90 minutes depending on strategy)
All components at 4.17.0
```

### Version Skew Policy (N-1)

OpenShift maintains backward compatibility within one minor version:

```
Valid combinations:
├─ 4.16 control plane + 4.16 nodes ✓
├─ 4.16 control plane + 4.15 nodes ✓ (N-1)
├─ 4.17 control plane + 4.17 nodes ✓
├─ 4.17 control plane + 4.16 nodes ✓ (N-1)
└─ 4.17 control plane + 4.15 nodes ✗ (N-2)
```

**Implication:** Control plane can be 1 version ahead of nodes.

### Unsupported Paths

```
❌ Skipping minor versions:  4.15 → 4.17 (must do 4.15 → 4.16 → 4.17)
❌ Downgrading versions:      4.17 → 4.16 (not supported)
❌ Nodes ahead of CP:         CP 4.16 + Nodes 4.17 (not allowed)
```

---

## Upgrade Strategies

Two primary strategies for node upgrades:

### Strategy 1: Replace

Create new machines, drain old machines, delete old machines.

```
Timeline:
T+0m   2 nodes (4.16.1)
T+2m   2 existing + 1 new (provisioning, 4.17.0)
T+15m  2 existing (draining) + 1 new (4.17.0)
T+20m  1 existing + 1 new (continuing)
T+35m  2 new (4.17.0, all upgraded)
```

**Characteristics:**
- Fast per-node (5-10 minutes each)
- Requires excess capacity (need room for new nodes during transition)
- Good for small clusters or batch upgrades

**Use when:**
- You have capacity for 2x nodes temporarily
- Cluster is small (2-5 nodes)
- Want fastest upgrade

### Strategy 2: InPlace

Upgrade kubelet on existing machines without replacing VMs.

```
Timeline:
T+0m   2 nodes (4.16.1)
T+2m   1 node draining, 1 node 4.17.0 running
T+20m  1 node draining, 1 node 4.17.0
T+40m  2 nodes 4.17.0
```

**Characteristics:**
- Slower per-node (10-20 minutes each)
- No excess capacity needed
- Minimal resource disruption

**Use when:**
- Cluster running near capacity
- Nodes are expensive (don't want 2x cost)
- Have time for slower upgrade

---

## Control Plane Upgrade

### Step 1: Update Release Image

```bash
# Edit HostedCluster manifest
nano base/hostedcluster.yaml
```

Change:
```yaml
spec:
  release:
    image: quay.io/openshift-release-dev/ocp-release:4.16.1-x86_64
```

To:
```yaml
spec:
  release:
    image: quay.io/openshift-release-dev/ocp-release:4.17.0-x86_64
```

### Step 2: Commit and Deploy

```bash
git checkout -b upgrade-4.16-to-4.17
git add base/hostedcluster.yaml
git commit -m "Upgrade control plane from 4.16.1 to 4.17.0"
git push origin upgrade-4.16-to-4.17

# Merge to main after approval
```

### Step 3: Monitor Control Plane Upgrade

```bash
# Watch HostedCluster status
watch -n 5 'kubectl get hostedcluster -n clusters example-hcp'

# Expected progression:
# T+0m:  Progressing=True, Available=True (starting update)
# T+3m:  Progressing=True, Available=False (upgrading)
# T+8m:  Progressing=False, Available=True (done)

# Check control plane Pods
watch -n 10 'kubectl get pods -n clusters-example-hcp'

# Expected: old Pods deleted, new Pods created
# etcd-0 (new image)
# kube-apiserver-0 (new image)
# kube-controller-manager-0 (new image)
```

### Step 4: Verify Control Plane Ready

```bash
# Get cluster kubeconfig
kubectl get secret -n clusters admin-kubeconfig -o json | \
  jq -r '.data.kubeconfig' | base64 -d > /tmp/hcp.yaml

# Test API connectivity
kubectl --kubeconfig=/tmp/hcp.yaml cluster-info

# Check API server version
kubectl --kubeconfig=/tmp/hcp.yaml version | grep Server

# Should show: 4.17.0

# Wait for cluster operators ready
watch -n 10 'kubectl --kubeconfig=/tmp/hcp.yaml get clusteroperators'

# All should show: AVAILABLE=True, PROGRESSING=False, DEGRADED=False
```

---

## Node Upgrade Strategy 1: Replace

### Step 1: Update NodePool Image

```bash
nano base/nodepool.yaml
```

Change:
```yaml
spec:
  release:
    image: quay.io/openshift-release-dev/ocp-release:4.16.1-x86_64
  management:
    upgradeType: Replace  # Explicit Replace strategy
```

To:
```yaml
spec:
  release:
    image: quay.io/openshift-release-dev/ocp-release:4.17.0-x86_64
  management:
    upgradeType: Replace  # Keep Replace strategy
```

### Step 2: Deploy

```bash
git add base/nodepool.yaml
git commit -m "Upgrade nodes (Replace strategy) from 4.16.1 to 4.17.0"
git push origin upgrade-4.16-to-4.17

# Merge after approval
```

### Step 3: Monitor Replace Upgrade

```bash
# Watch machines
watch -n 10 'kubectl get machines -A'

# Expected progression:
# T+0m:  2 machines (worker1, worker2) with 4.16.1
# T+2m:  3 machines (2 old + 1 new provisioning)
# T+15m: 2 machines (1 old draining, 1 new ready)
# T+30m: 1 machine (new ready, old terminating)
# T+35m: 2 machines (both new with 4.17.0)

# Watch nodes
watch -n 5 'kubectl --kubeconfig=/tmp/hcp.yaml get nodes -o wide'

# Expected: cordoned nodes disappear, new nodes appear

# Watch Pod migration
watch -n 5 'kubectl --kubeconfig=/tmp/hcp.yaml get pods -A | grep Evicted'

# Should see pods migrating to new nodes
```

### Step 4: Verify Replace Upgrade Complete

```bash
# All nodes at new version
kubectl --kubeconfig=/tmp/hcp.yaml get nodes

# Should show all Ready with new kernel version

# Check Node image version
kubectl --kubeconfig=/tmp/hcp.yaml get nodes -o json | \
  jq '.items[] | {name: .metadata.name, version: .status.nodeInfo.kubeletVersion}'

# Should all show v1.27.0+ (for 4.17)

# Verify no more old machines
kubectl get machines -A | grep -v worker
# Should show only new machines
```

---

## Node Upgrade Strategy 2: InPlace

### Step 1: Update Management Strategy

```bash
nano base/nodepool.yaml
```

Change to InPlace:
```yaml
spec:
  management:
    upgradeType: InPlace  # Switch to InPlace
```

And update release:
```yaml
  release:
    image: quay.io/openshift-release-dev/ocp-release:4.17.0-x86_64
```

### Step 2: Deploy

```bash
git add base/nodepool.yaml
git commit -m "Upgrade nodes (InPlace strategy) from 4.16.1 to 4.17.0"
git push origin upgrade-4.16-to-4.17
```

### Step 3: Monitor InPlace Upgrade

```bash
# Watch nodes being updated
watch -n 10 'kubectl --kubeconfig=/tmp/hcp.yaml get nodes -o wide'

# Expected progression:
# T+0m:  2 Ready (4.16.1)
# T+2m:  1 Ready + 1 Draining
# T+20m: 1 Ready (4.17.0) + 1 Draining (4.16.1)
# T+40m: 2 Ready (4.17.0)

# Each node takes 10-20 minutes for InPlace

# Watch for kubelet restarts
kubectl --kubeconfig=/tmp/hcp.yaml describe node | grep -A 5 "Kubelet"

# Watch cluster operators
watch -n 10 'kubectl --kubeconfig=/tmp/hcp.yaml get clusteroperators'
```

### Step 4: Verify InPlace Upgrade Complete

```bash
# All nodes running new version
kubectl --kubeconfig=/tmp/hcp.yaml get nodes

# Check no old image references
kubectl --kubeconfig=/tmp/hcp.yaml get nodes -o json | \
  jq '.items[] | .status.nodeInfo.kubeletVersion' | sort -u

# Should see only new version (v1.27.x)

# Verify MCO worked properly (Machine Config Operator)
kubectl get machineconfig -A | grep rendered

# Should show new rendered config
```

---

## Comparing Replace vs. InPlace

| Aspect | Replace | InPlace |
|--------|---------|---------|
| **Per-node time** | 5-10 min | 10-20 min |
| **Total time (2 nodes)** | 30-40 min | 40-60 min |
| **Capacity needed** | 2x available | 1x available |
| **Cost (temp)** | 2x during upgrade | 1x steady |
| **Workload disruption** | Pod eviction/rebalance | Gradual |
| **Best for** | Small clusters | Large clusters |
| **Risk** | Resource exhaustion | Extended timeline |

---

## Rollback Procedure

If something goes wrong, you can roll back:

### Scenario: Upgrade Failed, Need to Rollback

### Step 1: Identify Issue

```bash
# Symptoms of failed upgrade:
# - Cluster Operators stuck in Progressing=True
# - Persistent pod CrashLoopBackOff
# - API latency increase
# - Pod scheduling issues

# Example: Check for degradation
kubectl --kubeconfig=/tmp/hcp.yaml get clusteroperators | grep -v True
```

### Step 2: Decide to Rollback

```bash
# Option A: Wait longer (some upgrades take 1-2 hours)
watch -n 30 'kubectl --kubeconfig=/tmp/hcp.yaml get clusteroperators'

# Option B: Immediate rollback (if critical issue)
# Proceed to Step 3
```

### Step 3: Revert Git Changes

```bash
# Option 1: Revert specific commit
git revert <commit-hash>

# Option 2: Edit manifest back to old version
nano base/hostedcluster.yaml
# Change back: 4.17.0 → 4.16.1

nano base/nodepool.yaml
# Change back: 4.17.0 → 4.16.1

# Commit
git add base/hostedcluster.yaml base/nodepool.yaml
git commit -m "Rollback: revert to 4.16.1 due to issue"
git push origin main
```

### Step 4: Monitor Rollback

```bash
# Argo will detect change
watch -n 5 'kubectl get application -n argocd'

# HyperShift will re-reconcile
# NOTE: This is NOT truly downgrading the cluster!
# It's essentially a no-op - the cluster stays at 4.17.0

# True rollback requires:
# - Backup of 4.16.1 cluster state
# - Full restore procedure
# - Not supported by HyperShift

# What actually happens:
# - Manifest reverted to 4.16.1 reference
# - But cluster is already at 4.17.0
# - HyperShift notices mismatch
# - Requires manual intervention
```

### Understanding Rollback Limitations

**Important:** OpenShift doesn't support version downgrade.

```
4.17.0 → 4.16.1 NOT SUPPORTED

Why:
- etcd data format might be upgraded
- CRD schemas might have changed
- Database migrations not reversible

Recovery options:
1. Restore from backup (if backup taken before upgrade)
2. Re-provision cluster
3. Live with upgrade (wait for fix in next patch)
```

### Better Approach: Staged Upgrades

Avoid rollback need with careful planning:

```bash
# 1. Test on dev cluster first
# Upgrade dev 4.16.1 → 4.17.0
# Run test suite
# Wait 1-2 weeks

# 2. If successful, schedule prod upgrade
# On staging first (non-prod)
# Run production workload tests
# Wait additional period

# 3. Finally upgrade production
# During maintenance window
# With full team available
# Have documented runbook
```

---

## Pre-Upgrade Checklist

Before any upgrade, verify:

```bash
# 1. Cluster health
kubectl get hostedcluster -n clusters example-hcp
# Status: Available=True, Progressing=False

# 2. All Cluster Operators healthy
kubectl --kubeconfig=/tmp/hcp.yaml get clusteroperators
# All: AVAILABLE=True, PROGRESSING=False, DEGRADED=False

# 3. No pending upgrades
kubectl get clusterversion
# No ongoing 4.16.x → 4.17.0 already

# 4. All Pods running
kubectl --kubeconfig=/tmp/hcp.yaml get pods -A | grep -E "Pending|CrashLoop|ImagePull"
# Should return empty

# 5. Capacity available
# For Replace strategy: need 2x current node count
kubectl --kubeconfig=/tmp/hcp.yaml top nodes
# Check Hub has capacity for new nodes

# 6. Backups current (if available)
# Take snapshot of cluster state
kubectl --kubeconfig=/tmp/hcp.yaml get all -A > backup-4.16.1.yaml

# 7. Change window approved
# Upgrade during maintenance window
# Notify users

# 8. Team available
# Have support team ready during upgrade
# Estimated duration: 90-120 minutes
```

---

## Post-Upgrade Verification

After upgrade completes:

```bash
# 1. All Cluster Operators healthy
watch -n 30 'kubectl --kubeconfig=/tmp/hcp.yaml get clusteroperators'
# Max 1 hour to all healthy

# 2. All Pods running
kubectl --kubeconfig=/tmp/hcp.yaml get pods -A | grep -v Running
# Should be empty or only completed jobs

# 3. Network connectivity
kubectl --kubeconfig=/tmp/hcp.yaml get svc
kubectl --kubeconfig=/tmp/hcp.yaml get endpoints

# 4. Storage working
kubectl --kubeconfig=/tmp/hcp.yaml get pvc -A

# 5. Applications responsive
# Deploy test pod
kubectl --kubeconfig=/tmp/hcp.yaml run test --image=busybox -- sleep 3600
# Should schedule and run

# 6. Check version updated
kubectl --kubeconfig=/tmp/hcp.yaml version
# Server version should be new version

# 7. Review events for errors
kubectl --kubeconfig=/tmp/hcp.yaml get events -A | grep -E "Error|Warning" | head -20
```

---

## Production Upgrade Workflow

### Day 0: Planning

```
1. Choose upgrade window (low-traffic time)
2. Identify cluster dependencies
3. Notify users 1 week in advance
4. Prepare runbook (this doc!)
5. Assign roles: operator, observer, decision-maker
6. Ensure monitoring dashboard ready
```

### Day 1: 4:00 AM (upgrade start)

```
4:00 AM   ✓ Final health check
          ✓ Gather team in war room
          
4:05 AM   ✓ Create Git branch for upgrade
          
4:10 AM   ✓ Update control plane version in Git
          ✓ Merge PR to main
          ✓ Argo syncs (automatic)
          
4:15 AM   ✓ Monitor control plane upgrade
          ✓ Expected: 5-10 minutes
          
4:25 AM   ✓ Verify control plane ready
          ✓ API responding
          ✓ All operators progressing
          
4:30 AM   ✓ Update NodePool version
          ✓ Choose Replace vs. InPlace strategy
          ✓ Merge to main
          
4:35 AM   ✓ Monitor first node upgrade
          ✓ Watch Pod evictions
          ✓ Check no data loss
          
5:15 AM   ✓ Second node complete
          ✓ Verify both at new version
          
5:20 AM   ✓ Post-upgrade verification
          ✓ All operators healthy
          ✓ All Pods running
          ✓ All tests passing
          
5:30 AM   ✓ Notify users: upgrade complete
          ✓ Monitor for issues over next hour
          ✓ Collect metrics for post-mortem
```

### Day 1: Follow-up

```
- Monitor cluster for 24 hours
- Watch for delayed issues
- Review event logs
- Update runbook with lessons learned
```

---

## Troubleshooting Upgrades

### Issue: Control Plane Stuck Progressing

See [08-troubleshooting.md](./08-troubleshooting.md#control-plane-stuck-upgrading)

### Issue: Nodes Won't Upgrade

```bash
# Check machine controller logs
kubectl logs -n hypershift-system \
  deployment/hypershift-operator | grep upgrade

# Check node version hasn't changed
kubectl --kubeconfig=/tmp/hcp.yaml get nodes -o json | \
  jq '.items[] | {name, version: .status.nodeInfo.kubeletVersion}'

# Common causes:
# 1. Insufficient capacity (Replace needs 2x nodes)
# 2. Pods with local storage preventing drain
# 3. Pod Disruption Budget too strict
# 4. Machine controller issues

# Fixes:
# 1. Scale down workloads temporarily
# 2. Remove PDB temporarily
# 3. Force drain if safe:
kubectl --kubeconfig=/tmp/hcp.yaml drain <node> \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --force
```

---

## Best Practices

1. **Always test first** - Upgrade dev, then staging, then prod
2. **Use GitOps** - All changes tracked in Git
3. **Schedule window** - Upgrade during low-traffic time
4. **Have team ready** - Don't upgrade while on-call alone
5. **Monitor continuously** - Watch upgrade in real-time
6. **Verify health** - Check all operators after upgrade
7. **Document issues** - Record any problems encountered
8. **Staged rollout** - Upgrade one cluster at a time in production

---

## Next Steps

- [08-troubleshooting.md](./08-troubleshooting.md) - Troubleshooting guide
- Review upgrade logs and timings from this cluster
- Plan next upgrade window

---

**Last Updated:** April 2, 2026
