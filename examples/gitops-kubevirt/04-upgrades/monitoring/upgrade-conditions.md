# Upgrade Status Conditions Reference

This document describes the conditions and statuses you'll see during HostedCluster and NodePool upgrades.

## HostedCluster Conditions

### Available
- **Type:** Available
- **Values:** True, False, Unknown
- **Meaning:**
  - `True`: Control plane is operational and healthy
  - `False`: Control plane has issues or is being updated
  - `Unknown`: State cannot be determined
- **During upgrade:** May toggle between True/False as components restart

### Progressing
- **Type:** Progressing
- **Values:** True, False, Unknown
- **Meaning:**
  - `True`: Control plane is currently being updated/upgraded
  - `False`: Control plane is idle, no changes in progress
  - `Unknown`: State cannot be determined
- **During upgrade:** True while update is happening, False when complete

### Degraded
- **Type:** Degraded
- **Values:** True, False, Unknown
- **Meaning:**
  - `True`: Control plane is running but some components are unhealthy
  - `False`: All components healthy
  - `Unknown`: State cannot be determined
- **During upgrade:** Should remain False; True indicates a problem

## NodePool Conditions

### Ready
- **Status field:** `.status.ready`
- **Format:** N/M (e.g., "2/2", "1/3")
- **Meaning:**
  - First number: Nodes currently ready and operational
  - Second number: Total desired nodes
  - `2/2` = All 2 nodes ready
  - `1/3` = 1 ready, 2 still initializing or upgrading
- **During upgrade:** May decrease as old nodes are replaced

### Updated
- **Status field:** `.status.updated`
- **Format:** N (e.g., "2")
- **Meaning:**
  - Number of nodes with the target release image
  - During upgrade: Increases as nodes are replaced with new image
  - When updating image: Updated count increases, Ready may stay same

### Available
- **Status field:** `.status.available`
- **Format:** N (e.g., "2")
- **Meaning:**
  - Number of nodes that are both Ready and have been available for MinReadySeconds
  - During upgrade: Increases as new nodes stabilize

### Progressing
- **Type:** Progressing (in conditions array)
- **Values:** True, False, Unknown
- **Meaning:**
  - `True`: NodePool is updating nodes (upgrade in progress)
  - `False`: NodePool is idle
  - `Unknown`: State cannot be determined
- **During upgrade:** True during replacement/rolling update, False when complete

## Upgrade Phase Conditions

### Phase 1: Idle (Before Upgrade)

**HostedCluster:**
```
Available: True
Progressing: False
Degraded: False
```

**NodePool:**
```
Ready: 2/2
Updated: 2
Available: 2
Progressing: False
```

### Phase 2: Control Plane Upgrade in Progress

**HostedCluster:**
```
Available: False (or oscillating)
Progressing: True
Degraded: False (usually)
```

What's happening:
- etcd backup being taken
- etcd rolling update
- API server restart
- Controller restart
- Scheduler update

Monitor: `oc get pods -n clusters-example-hcp -w`

### Phase 3: Control Plane Upgraded, Awaiting Node Upgrade

**HostedCluster:**
```
Available: True
Progressing: False
Degraded: False
```

**NodePool:**
```
Ready: 2/2 (old version)
Updated: 0 (or partially updated)
Available: 2
Progressing: False (or about to start)
```

Action: Now initiate node upgrade

### Phase 4: NodePool Upgrade In Progress (Replace Strategy)

**NodePool:**
```
Ready: 1/2 (decreases as old nodes removed)
Updated: 1/2 (increases as new nodes created)
Available: 1/2
Progressing: True
```

Timeline:
- Old nodes marked unschedulable
- Pods evicted (5-10 min)
- Old nodes deleted (5 min)
- New nodes created (5-10 min)
- New nodes boot and join (5-10 min)
- Repeat for next node

Example progression:
```
Time 0:  Ready: 2/2, Updated: 0/2  ← Start
Time 5:  Ready: 2/2, Updated: 0/2  ← Evicting pods
Time 10: Ready: 1/2, Updated: 1/2  ← First old node gone, new node starting
Time 20: Ready: 1/2, Updated: 1/2  ← New node booting
Time 25: Ready: 2/2, Updated: 1/2  ← First new node ready
Time 30: Ready: 2/2, Updated: 2/2  ← All updated, repeating for second node
```

### Phase 5: NodePool Upgrade In Progress (InPlace Strategy)

**NodePool:**
```
Ready: 2/2 (stays high)
Updated: 1/2 (increases slowly)
Available: 2/2 (stays high)
Progressing: True
```

Characteristics:
- Both old and new nodes running temporarily
- Ready stays at 2/2 or close
- Pods migrate to new nodes gradually
- Old nodes drained after new nodes ready

Example progression:
```
Time 0:  Ready: 2/2, Updated: 0/2  ← Start
Time 10: Ready: 3/2, Updated: 1/2  ← New node added (temporary spike)
Time 20: Ready: 2/2, Updated: 1/2  ← Old node drained and removed
Time 30: Ready: 3/2, Updated: 1/2  ← Second new node added
Time 40: Ready: 2/2, Updated: 2/2  ← Second old node drained, all done
```

### Phase 6: NodePool Upgrade Complete

**NodePool:**
```
Ready: 2/2
Updated: 2/2
Available: 2/2
Progressing: False
```

## Interpreting Status Combinations

### Healthy Idle
```
HostedCluster.Available: True
HostedCluster.Progressing: False
NodePool.Ready: N/N
```
✓ All good, cluster is operational

### Control Plane Updating
```
HostedCluster.Progressing: True
NodePool.Ready: N/N
```
✓ Normal, control plane is updating, nodes unaffected

### Node Replacement in Progress
```
HostedCluster.Available: True
NodePool.Updated: M/N where M < N
NodePool.Progressing: True
```
✓ Normal, nodes being replaced

### Unhealthy
```
HostedCluster.Available: False
HostedCluster.Progressing: False
NodePool.Ready: 0/N
```
✗ Problem! Control plane is down and not recovering

### Degraded During Update
```
HostedCluster.Degraded: True
HostedCluster.Available: True
```
⚠ Warning, cluster is running but some components unhealthy

## Common Observations During Upgrade

### Control Plane Update Duration
- Typical: 15-30 minutes
- Factors:
  - Image size (affects pull time)
  - Database size (affects etcd upgrade)
  - Number of resources
- Can be longer on slower networks

### Node Replacement Duration
Replace strategy:
- Per node: 5-10 minutes
- 2 nodes: 10-20 minutes
- 5 nodes: 25-50 minutes
- 10 nodes: 50-100 minutes

InPlace strategy:
- Per node: 10-20 minutes
- 2 nodes: 20-40 minutes
- 5 nodes: 50-100 minutes
- 10 nodes: 100-200 minutes

### Pod Rescheduling
- Pods evicted: 5-10 minutes per wave
- Rescheduling time: 2-5 minutes per pod (depends on size, resource requests)
- StatefulSets: Slower due to persistent volume reattachment
- DaemonSets: Automatic re-creation on new nodes

## Troubleshooting Status Anomalies

### Control Plane stuck Progressing=True
```
HostedCluster.Progressing: True (for > 45 min)
```

Causes:
- Image pull failure (network/credentials)
- etcd upgrade stuck
- Insufficient capacity
- PVC issues

Investigation:
```bash
# Check control plane pod logs
oc logs -n clusters-example-hcp -l app=etcd -f
oc logs -n clusters-example-hcp -l app=kube-apiserver -f
oc logs -n hypershift deployment/operator -f
```

### Nodes stuck NotReady
```
NodePool.Ready: 0/N
```

Causes:
- VM not booting
- Network connectivity
- DNS resolution
- Node initialization timeout

Investigation:
```bash
# Check VM status
oc get vm -n clusters-example-hcp -w

# Check node initialization logs
oc describe nodepool -n clusters example-hcp-workers
oc logs -n hypershift deployment/operator -f --tail=100
```

### Pods stuck Pending
During upgrade, some pods may be pending:

Expected (temporary):
- System pods rescheduling
- PVCs reattaching
- Resource contention

Not expected (investigate):
- Application pods pending > 10 minutes
- PVCs stuck Pending
- Nodes stuck NotReady

Investigation:
```bash
# Check pending pods
oc get pods -A --field-selector=status.phase=Pending

# Check pod events
oc describe pod <pod> -n <namespace>

# Check node capacity
oc top nodes
```

## Monitoring Commands

### Watch HostedCluster
```bash
oc get hostedcluster -n clusters example-hcp -w
```

### Watch NodePool
```bash
oc get nodepool -n clusters example-hcp-workers -w
```

### Watch Nodes
```bash
oc get nodes -w
```

### Detailed Condition Check
```bash
# All conditions
oc get hostedcluster -n clusters example-hcp -o yaml | grep -A50 conditions:

# Just Available
oc get hostedcluster -n clusters example-hcp -o jsonpath='{.status.conditions[?(@.type=="Available")]}'

# Just Progressing
oc get hostedcluster -n clusters example-hcp -o jsonpath='{.status.conditions[?(@.type=="Progressing")]}'
```

### Using the Monitor Script
```bash
# Run continuous monitoring
./monitoring/check-upgrade-status.sh

# Monitor specific cluster
./monitoring/check-upgrade-status.sh my-cluster my-clusters

# Change poll interval (default 5s)
POLL_INTERVAL=10 ./monitoring/check-upgrade-status.sh

# Run for specific number of iterations
MAX_ITERATIONS=120 ./monitoring/check-upgrade-status.sh  # 10 minutes (120 * 5s)
```

## Success Indicators

Upgrade is successful when:

1. HostedCluster reaches:
   ```
   Available: True
   Progressing: False
   Degraded: False
   ```

2. NodePool reaches:
   ```
   Ready: N/N
   Updated: N/N
   Available: N/N
   Progressing: False
   ```

3. All nodes are Ready:
   ```bash
   oc get nodes
   # All show STATUS: Ready
   ```

4. All cluster operators available:
   ```bash
   oc get clusteroperators
   # All show AVAILABLE: True
   ```

5. No pending pods (except optional system pods):
   ```bash
   oc get pods -A --field-selector=status.phase=Pending
   # Should be empty or only system pods
   ```
