# Scenario 4: Progressive Upgrades - Validation Checklist

This checklist validates each upgrade operation in Scenario 4.

## Prerequisites

- [ ] Scenario 1 (Provisioning) completed successfully
- [ ] Base cluster running at 4.16.1 (AVAILABLE=True, READY=2/2)
- [ ] Argo CD Application synced and healthy
- [ ] Can access hosted cluster kubeconfig
- [ ] Have sufficient cluster capacity for upgrades

## Base State Validation (4.16.1)

Before starting upgrades, verify the base state:

### 1. HostedCluster Status

- [ ] **Verify HostedCluster exists and is available:**
  ```bash
  oc get hostedcluster -n clusters example-hcp
  ```
  Expected: AVAILABLE=True, VERSION shows 4.16.1

- [ ] **Check availability condition:**
  ```bash
  oc get hostedcluster -n clusters example-hcp -o jsonpath='{.status.conditions[?(@.type=="Available")]}'
  ```
  Expected: status=True

- [ ] **Verify release image:**
  ```bash
  oc get hostedcluster -n clusters example-hcp -o jsonpath='{.spec.release.image}'
  ```
  Expected: Contains "4.16.1"

### 2. NodePool Status

- [ ] **Verify NodePool exists with correct version:**
  ```bash
  oc get nodepool -n clusters example-hcp-workers
  ```
  Expected: READY=2/2, UPDATED=2, AVAILABLE=2

- [ ] **Verify release image:**
  ```bash
  oc get nodepool -n clusters example-hcp-workers -o jsonpath='{.spec.release.image}'
  ```
  Expected: Contains "4.16.1"

### 3. Nodes Status

- [ ] **Verify 2 worker nodes at 4.16.1:**
  ```bash
  export KUBECONFIG=/tmp/example-hcp-kubeconfig
  oc get nodes -o wide
  ```
  Expected: 2 nodes in Ready state with 4.16.1 version

### 4. Cluster Operators Health

- [ ] **Verify all cluster operators are available:**
  ```bash
  oc get clusteroperators | grep -v "True.*False.*False"
  ```
  Expected: No rows (all operators AVAILABLE=True)

### 5. API and Services

- [ ] **Test API availability:**
  ```bash
  oc whoami
  ```
  Expected: Shows current user (API is responsive)

- [ ] **Check service endpoints:**
  ```bash
  oc get service -n clusters-example-hcp kube-apiserver
  ```
  Expected: Service has EXTERNAL-IP or CLUSTER-IP

---

## Upgrade 1: Control Plane (4.16.1 → 4.17.0)

**Duration:** ~15-30 minutes

### 1. Pre-Upgrade Checks

- [ ] **Create backup of etcd (optional but recommended):**
  ```bash
  # Get control plane namespace
  oc get pods -n clusters-example-hcp | grep etcd
  ```

- [ ] **Record starting time:**
  ```bash
  date
  # Note: Time for reference
  ```

### 2. Apply Control Plane Upgrade

- [ ] **Update the image to 4.17.0:**
  ```bash
  oc apply -f upgrades/01-control-plane-upgrade.yaml
  ```
  Or via Git: edit base/hostedcluster.yaml, change image to 4.17.0

- [ ] **Verify change applied:**
  ```bash
  oc get hostedcluster -n clusters example-hcp -o jsonpath='{.spec.release.image}'
  ```
  Expected: Contains "4.17.0"

### 3. Monitor Control Plane Update

- [ ] **Start continuous monitoring:**
  ```bash
  ./monitoring/check-upgrade-status.sh
  ```

- [ ] **Watch HostedCluster status:**
  ```bash
  oc get hostedcluster -n clusters example-hcp -w
  ```
  Expected:
  - AVAILABLE changes (may go False briefly)
  - PROGRESSING becomes True (upgrade in progress)
  - After 15-30 min: AVAILABLE returns to True, PROGRESSING to False

- [ ] **Monitor control plane pods:**
  ```bash
  oc get pods -n clusters-example-hcp -w
  ```
  Expected:
  - etcd pods restart
  - API server pods restart (service may be briefly unavailable)
  - Controller pods restart
  - All return to Running state

### 4. Check Upgrade Progress

Monitor upgrade phases (check progress every 2-3 minutes):

- [ ] **Phase 1: etcd backup (0-5 min)**
  - Control plane pods starting restart
  - PROGRESSING=True
  
- [ ] **Phase 2: etcd update (5-15 min)**
  - etcd pods restarting
  - May see temporary unavailability

- [ ] **Phase 3: Controller restart (15-20 min)**
  - API server and controllers restarting
  - API may be briefly unavailable

- [ ] **Phase 4: Completion (20-30 min)**
  - All pods returning to Running
  - PROGRESSING transitioning to False
  - AVAILABLE returning to True

### 5. Verify Control Plane Upgrade Complete

- [ ] **HostedCluster shows 4.17.0:**
  ```bash
  oc get hostedcluster -n clusters example-hcp -o jsonpath='{.spec.release.image}'
  ```
  Expected: 4.17.0-x86_64

- [ ] **All conditions healthy:**
  ```bash
  oc get hostedcluster -n clusters example-hcp -o jsonpath='{.status.conditions}' | jq '.'
  ```
  Expected:
  - Available: True
  - Progressing: False
  - Degraded: False (or not present)

- [ ] **All control plane pods running:**
  ```bash
  oc get pods -n clusters-example-hcp | grep -v Running
  ```
  Expected: No rows (all pods Running)

### 6. Verify Hosted Cluster Still Accessible

- [ ] **Cluster version check:**
  ```bash
  export KUBECONFIG=/tmp/example-hcp-kubeconfig
  oc get clusterversion
  ```
  Expected: Shows 4.16.1 (nodes not upgraded yet)

- [ ] **Nodes still at 4.16.1:**
  ```bash
  oc get nodes -o wide
  ```
  Expected: 2 nodes, still 4.16.1 version

- [ ] **Cluster operators still healthy:**
  ```bash
  oc get clusteroperators | grep -v "True.*False.*False"
  ```
  Expected: No rows

### 7. Verify Control Plane and Node Skew

- [ ] **Check version skew is within policy:**
  Control plane: 4.17.0
  Nodes: 4.16.1
  Skew: 1 version (OK, within N-1 policy)

---

## Upgrade 2: NodePool with Replace Strategy

**Duration:** ~15-30 minutes for 2 nodes

### 1. Pre-Upgrade Checks

- [ ] **Verify sufficient capacity:**
  ```bash
  export KUBECONFIG=/tmp/example-hcp-kubeconfig
  oc top nodes
  ```
  Ensure remaining node can hold all pods temporarily

- [ ] **Check for critical apps without PDB:**
  ```bash
  oc get pods -A | grep -E "critical|important"
  oc get pdb -A
  ```
  Ensure critical apps have PDBs

- [ ] **Record current pod distribution:**
  ```bash
  oc get pods -A -o wide
  ```

### 2. Apply NodePool Upgrade - Replace

- [ ] **Apply the Replace strategy upgrade:**
  ```bash
  oc apply -f upgrades/02-nodepool-upgrade-replace.yaml
  ```
  Or via Git: edit base/nodepool.yaml, set image to 4.17.0, upgradeType=Replace

- [ ] **Verify change applied:**
  ```bash
  oc get nodepool -n clusters example-hcp-workers -o jsonpath='{.spec.release.image}'
  ```
  Expected: Contains "4.17.0"

### 3. Monitor Node Replacement

- [ ] **Start continuous monitoring:**
  ```bash
  ./monitoring/check-upgrade-status.sh
  ```

- [ ] **Watch NodePool status:**
  ```bash
  oc get nodepool -n clusters example-hcp-workers -w
  ```
  Expected progression:
  - READY decreases (old nodes marked unschedulable)
  - UPDATED increases (new nodes created with 4.17.0)
  - READY increases (new nodes join and become ready)

- [ ] **Monitor individual nodes:**
  ```bash
  export KUBECONFIG=/tmp/example-hcp-kubeconfig
  oc get nodes -w
  ```
  Expected:
  - Some nodes NotReady (being drained)
  - New nodes appear as NotReady
  - New nodes transition to Ready

### 4. Track Pod Evictions

- [ ] **Monitor pod rescheduling (every 2 minutes):**
  ```bash
  oc get pods -A -o wide
  ```
  Expected:
  - Pods evicted from NotReady nodes
  - Pods migrating to new nodes
  - Temporary pending pods (if capacity constrained)

- [ ] **Check for stuck pods:**
  ```bash
  oc get pods -A --field-selector=status.phase=Pending
  ```
  Expected: Minimal or no pending pods (temporary is OK)

- [ ] **Check for pod disruptions:**
  ```bash
  oc get events -n clusters --sort-by='.lastTimestamp' | tail -20
  ```
  Expected: Events showing pod evictions and reschedules

### 5. Wait for Replacement to Complete

Expected timeline:
- Node 1 replacement: 10-15 minutes
- Node 2 replacement: 10-15 minutes
- Total: 15-30 minutes

Monitor and wait until all nodes Ready.

### 6. Verify Replace Upgrade Complete

- [ ] **All nodes ready:**
  ```bash
  oc get nodepool -n clusters example-hcp-workers
  ```
  Expected: READY=2/2, UPDATED=2/2

- [ ] **Nodes running 4.17.0:**
  ```bash
  oc get nodes -o wide
  ```
  Expected: All nodes show 4.17.0 version

- [ ] **Cluster version updated:**
  ```bash
  oc get clusterversion
  ```
  Expected: Desired version 4.17.0

- [ ] **All operators available:**
  ```bash
  oc get clusteroperators | grep -v "True.*False.*False"
  ```
  Expected: No rows

### 7. Verify Workloads Healthy

- [ ] **No pending pods:**
  ```bash
  oc get pods -A --field-selector=status.phase=Pending
  ```
  Expected: Empty or only known system pods

- [ ] **All pod replicas running:**
  ```bash
  oc get deployments -A
  ```
  Expected: READY=DESIRED for all deployments

- [ ] **Persistent volumes attached:**
  ```bash
  oc get pvc -A
  ```
  Expected: All PVCs Bound, not Pending

---

## Upgrade 3: NodePool with InPlace Strategy

This test is optional - use if you want to test InPlace upgrade strategy.

**Prerequisites:**
- Revert base/nodepool.yaml back to 4.16.1 (if after Replace test)
- Ensure sufficient temporary capacity (2x nodes)

### 1. Pre-Upgrade Setup

- [ ] **Revert NodePool to 4.16.1 (if needed):**
  ```bash
  oc patch nodepool -n clusters example-hcp-workers \
    --type merge -p '{"spec":{"release":{"image":"quay.io/openshift-release-dev/ocp-release:4.16.1-x86_64"}}}'
  
  # Wait for nodes to return to 4.16.1
  oc get nodepool -n clusters example-hcp-workers -w
  ```

- [ ] **Verify capacity for 3 nodes (2 old + 1 new initially):**
  ```bash
  export KUBECONFIG=/tmp/example-hcp-kubeconfig
  oc top nodes
  ```

### 2. Apply InPlace Upgrade

- [ ] **Apply InPlace strategy upgrade:**
  ```bash
  oc apply -f upgrades/03-nodepool-upgrade-rolling.yaml
  ```
  Or via Git: edit base/nodepool.yaml, set upgradeType=InPlace, maxUnavailable=1, image=4.17.0

- [ ] **Verify configuration:**
  ```bash
  oc get nodepool -n clusters example-hcp-workers -o yaml | grep -A5 management
  ```
  Expected: upgradeType: InPlace, maxUnavailable: 1

### 3. Monitor Rolling Update

- [ ] **Watch NodePool status:**
  ```bash
  oc get nodepool -n clusters example-hcp-workers -w
  ```
  Expected:
  - New node appears (READY may increase temporarily)
  - Workloads migrate gradually
  - Old node removed
  - Repeat for next node

- [ ] **Monitor node count:**
  ```bash
  export KUBECONFIG=/tmp/example-hcp-kubeconfig
  oc get nodes -w
  ```
  Expected:
  - Temporarily 3 nodes (2 old + 1 new)
  - Then back to 2 nodes (when old node removed)
  - Progression: 2 → 3 → 2 → 3 → 2

### 4. Track Workload Migration

- [ ] **Observe pod movement (every 2 minutes):**
  ```bash
  oc get pods -A -o wide | head -20
  ```
  Expected:
  - Pods gradually moving from old to new nodes
  - No massive evictions (gradual migration)

- [ ] **Monitor pod disruptions:**
  ```bash
  oc get events -n clusters --sort-by='.lastTimestamp' | tail -10
  ```
  Expected: Fewer evictions than Replace strategy

### 5. Wait for InPlace Upgrade Complete

Expected timeline:
- Per node: 10-20 minutes
- 2 nodes: 20-40 minutes

Monitor until READY=2/2, UPDATED=2/2.

### 6. Verify InPlace Upgrade Complete

- [ ] **All nodes ready:**
  ```bash
  oc get nodepool -n clusters example-hcp-workers
  ```
  Expected: READY=2/2, UPDATED=2/2, node count = 2

- [ ] **All nodes 4.17.0:**
  ```bash
  oc get nodes -o wide
  ```
  Expected: All nodes 4.17.0

- [ ] **Cluster fully upgraded:**
  ```bash
  oc get clusterversion
  ```
  Expected: Desired=4.17.0, Available=True

- [ ] **All operators available:**
  ```bash
  oc get clusteroperators | grep -v "True.*False.*False"
  ```
  Expected: No rows

### 7. Compare Replace vs InPlace

If you ran both tests:
- Replace was faster (15-30 min vs 20-40 min)
- InPlace had smoother experience (fewer pod evictions)
- InPlace required temporary extra capacity
- Replace had cleaner final state (complete node recreation)

---

## Upgrade 4: Rollback Example

**WARNING:** Only perform if comfortable with rollback procedures. This is risky!

### 1. Prepare for Rollback

- [ ] **Have cluster at 4.17.0 (from upgrades 1-3)**

- [ ] **Verify cluster is healthy:**
  ```bash
  oc get hostedcluster -n clusters example-hcp -o jsonpath='{.status.conditions[?(@.type=="Available")]}'
  ```
  Expected: status=True

- [ ] **Record current state:**
  ```bash
  oc get hostedcluster -n clusters example-hcp
  oc get nodepool -n clusters example-hcp-workers
  oc get nodes
  ```

### 2. Initiate Rollback (NodePool First)

- [ ] **Apply rollback manifest (NodePool only):**
  ```bash
  # Only rollback nodes first, not control plane!
  oc patch nodepool -n clusters example-hcp-workers \
    --type merge -p '{"spec":{"release":{"image":"quay.io/openshift-release-dev/ocp-release:4.16.1-x86_64"}}}'
  ```

- [ ] **Verify rollback started:**
  ```bash
  oc get nodepool -n clusters example-hcp-workers -o jsonpath='{.spec.release.image}'
  ```
  Expected: Contains "4.16.1"

### 3. Monitor Node Rollback

- [ ] **Watch NodePool status:**
  ```bash
  oc get nodepool -n clusters example-hcp-workers -w
  ```
  Expected: UPDATED decreases (4.17.0 nodes being replaced)

- [ ] **Monitor node transitions:**
  ```bash
  export KUBECONFIG=/tmp/example-hcp-kubeconfig
  oc get nodes -w
  ```
  Expected: Nodes transitioning back to 4.16.1

### 4. Wait for Node Rollback Complete

Timeline: 15-30 minutes (same as upgrade)

- [ ] **Verify all nodes at 4.16.1:**
  ```bash
  oc get nodes -o wide
  ```
  Expected: All nodes 4.16.1

- [ ] **NodePool status:**
  ```bash
  oc get nodepool -n clusters example-hcp-workers
  ```
  Expected: READY=2/2, UPDATED=2/2

### 5. Optional: Rollback Control Plane

**ONLY WITH SUPPORT GUIDANCE!**

- [ ] **If attempting control plane rollback:**
  ```bash
  oc patch hostedcluster -n clusters example-hcp \
    --type merge -p '{"spec":{"release":{"image":"quay.io/openshift-release-dev/ocp-release:4.16.1-x86_64"}}}'
  ```

- [ ] **Monitor carefully:**
  ```bash
  oc get hostedcluster -n clusters example-hcp -w
  ```

### 6. Verify Rollback Complete

- [ ] **All resources at 4.16.1:**
  ```bash
  oc get hostedcluster -n clusters example-hcp -o jsonpath='{.spec.release.image}'
  oc get nodepool -n clusters example-hcp-workers -o jsonpath='{.spec.release.image}'
  ```
  Expected: Both contain "4.16.1"

- [ ] **Cluster healthy:**
  ```bash
  oc get hostedcluster -n clusters example-hcp -o jsonpath='{.status.conditions[?(@.type=="Available")]}'
  ```
  Expected: status=True

- [ ] **All operators available:**
  ```bash
  export KUBECONFIG=/tmp/example-hcp-kubeconfig
  oc get clusteroperators | grep -v "True.*False.*False"
  ```
  Expected: No rows

---

## Summary

**Success Criteria:**
- [ ] All upgrade steps completed without cluster failure
- [ ] Cluster accessible throughout upgrades
- [ ] No data loss
- [ ] All workloads migrated successfully
- [ ] Cluster operators available after each upgrade
- [ ] Rollback procedures understood and documented

**Total Time:** 
- Control plane: 15-30 minutes
- NodePool (Replace): 15-30 minutes  
- NodePool (InPlace): 20-40 minutes
- Rollback test: 15-30 minutes
- **Total: 90-180 minutes** (depending on which tests run)

**Troubleshooting:**
See [README.md](README.md) for detailed troubleshooting and monitoring guidance.

**Monitoring:**
Use `./monitoring/check-upgrade-status.sh` for real-time status during all operations.

**Reference:**
See `./monitoring/upgrade-conditions.md` for understanding status conditions during upgrades.
