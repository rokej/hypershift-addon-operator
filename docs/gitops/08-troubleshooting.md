# Troubleshooting: Common Issues and Solutions

This guide helps you diagnose and resolve common issues encountered when deploying and operating HyperShift clusters via GitOps.

---

## Quick Symptom Index

| Symptom | See Section |
|---------|-------------|
| Cluster stuck "Progressing" | [Cluster Issues](#cluster-issues) |
| Nodes won't become Ready | [Node Issues](#node-issues) |
| ManagedCluster never appears | [ACM Issues](#acm-issues) |
| Argo showing OutOfSync | [Argo Issues](#argo-issues) |
| API server timeout | [Connectivity Issues](#connectivity-issues) |
| Pull secret errors | [Credential Issues](#credential-issues) |
| Machine provisioning stuck | [Infrastructure Issues](#infrastructure-issues) |
| Upgrade failing | [Upgrade Issues](#upgrade-issues) |

---

## Cluster Issues

### HostedCluster Stuck "Progressing"

**Symptom:**
```bash
kubectl get hostedcluster
NAME          AVAILABLE  PROGRESSING
example-hcp   False      True
```

After 20+ minutes, still not Available.

**Diagnosis:**

```bash
# 1. Check detailed conditions
kubectl get hostedcluster example-hcp -n clusters -o json | \
  jq '.status.conditions'

# 2. Check specific condition
kubectl get hostedcluster example-hcp -n clusters -o json | \
  jq '.status.conditions[] | select(.type=="Available")'

# 3. Check operator logs for errors
kubectl logs -n hypershift-system deployment/hypershift-operator -f | \
  grep example-hcp | head -50

# 4. Check control plane Pods
kubectl get pods -n clusters-example-hcp -o wide

# 5. Check Pod logs
kubectl logs -n clusters-example-hcp etcd-0 -f | head -100
kubectl logs -n clusters-example-hcp kube-apiserver-0 -f | head -100
```

**Common Causes & Fixes:**

#### Cause 1: Pull Secret Invalid or Missing

**Symptom:** etcd pod shows `ImagePullBackOff`

**Check:**
```bash
kubectl get secret -n clusters pull-secret
# If not found, create it:
kubectl create secret generic pull-secret \
  --from-file=.dockerconfigjson=/path/to/pull-secret.json \
  --type=kubernetes.io/dockerconfigjson \
  -n clusters

# Verify content is valid
kubectl get secret pull-secret -n clusters -o json | \
  jq '.data.".dockerconfigjson"' | base64 -d | jq '.' | head -20
```

**Fix:**
```bash
# Delete and recreate secret
kubectl delete secret pull-secret -n clusters
kubectl create secret generic pull-secret \
  --from-file=.dockerconfigjson=/path/to/corrected/pull-secret.json \
  --type=kubernetes.io/dockerconfigjson \
  -n clusters

# Redeploy HostedCluster
kubectl patch hostedcluster example-hcp -n clusters --type=merge \
  -p '{"spec":{"release":{"image":"quay.io/openshift-release-dev/ocp-release:4.17.0-x86_64"}}}'
```

#### Cause 2: Release Image Not Accessible

**Symptom:** Pods stuck on "Waiting" with pull errors

**Check:**
```bash
# Try to access image directly
docker pull quay.io/openshift-release-dev/ocp-release:4.17.0-x86_64

# Or via kubectl
kubectl run --rm -it test --image=quay.io/openshift-release-dev/ocp-release:4.17.0-x86_64 -- /bin/true

# Check registry reachability
curl -I https://quay.io
```

**Fix:**
```bash
# Ensure image exists (check release notes)
# Update to available version:
kubectl patch hostedcluster example-hcp -n clusters --type=merge \
  -p '{"spec":{"release":{"image":"quay.io/openshift-release-dev/ocp-release:4.17.1-x86_64"}}}'
```

#### Cause 3: Base Domain DNS Not Resolving

**Symptom:** API server can't bind to hostname

**Check:**
```bash
# Verify DNS resolution
nslookup api.example-hcp.example.com
dig +short api.example-hcp.example.com

# Check hub cluster can reach
kubectl run --rm -it test --image=busybox -- nslookup api.example-hcp.example.com
```

**Fix:**
```bash
# Add DNS record for your domain
# Point api.example-hcp.example.com to your LoadBalancer IP

# Get LoadBalancer IP
kubectl get service -n clusters-example-hcp | grep LoadBalancer
# Or check Service details:
kubectl get service -n clusters-example-hcp -o json | \
  jq '.items[0].status.loadBalancer.ingress[0].ip'

# Add A record to your DNS provider
# Once DNS resolves, cluster will become Available
```

#### Cause 4: Insufficient Hub Cluster Resources

**Symptom:** Pods stay Pending despite no errors

**Check:**
```bash
# Check node capacity
kubectl top nodes

# Check node allocatable
kubectl describe nodes | grep -A 10 "Allocatable"

# Check for resource requests/limits
kubectl get pods -n clusters-example-hcp -o json | \
  jq '.items[].spec.containers[].resources'
```

**Fix:**
```bash
# Option 1: Scale down other workloads
kubectl scale deployment -n other-namespace myapp --replicas=0

# Option 2: Add nodes to Hub cluster
# (Infrastructure-dependent)

# Option 3: Reduce HCP resource requests
# Edit hostedcluster.yaml, reduce CPU/memory
```

### HostedCluster API Server Timeout

**Symptom:**
```bash
kubectl --kubeconfig=hcp.yaml cluster-info
The connection to the server was refused
```

**Diagnosis:**

```bash
# 1. Check if API server pod running
kubectl get pod -n clusters-example-hcp kube-apiserver-0

# 2. Check pod logs
kubectl logs -n clusters-example-hcp kube-apiserver-0 -f

# 3. Check service has endpoints
kubectl get endpoints -n clusters-example-hcp

# 4. Check LoadBalancer status
kubectl get svc -n clusters-example-hcp APIServer -o wide

# 5. Try accessing service directly
kubectl exec -it pod/busybox -n default -- \
  curl -k https://kube-apiserver.clusters-example-hcp.svc:6443/api/v1
```

**Common Causes & Fixes:**

#### Cause: API Server Pod Crashing

**Check:**
```bash
kubectl logs -n clusters-example-hcp kube-apiserver-0 --previous
# Look for panic, segfault, or fatal errors
```

**Fix:**
```bash
# API server will auto-restart
# Monitor for stabilization
watch -n 5 'kubectl get pod -n clusters-example-hcp kube-apiserver-0'

# If still failing:
# Check etcd is healthy
kubectl logs -n clusters-example-hcp etcd-0 | head -50
# Check disk space
kubectl exec -it etcd-0 -n clusters-example-hcp -- df -h

# Last resort: recreate HostedCluster
# This requires complete re-provisioning
```

---

## Node Issues

### Nodes Not Becoming Ready

**Symptom:**
```bash
kubectl --kubeconfig=hcp.yaml get nodes
NAME    STATUS     ROLES
node1   NotReady   worker
node2   NotReady   worker
```

After 10+ minutes.

**Diagnosis:**

```bash
# 1. Check node conditions
kubectl --kubeconfig=hcp.yaml describe node node1

# 2. Check for common issues
kubectl --kubeconfig=hcp.yaml get nodes -o json | \
  jq '.items[].status.conditions[] | select(.status=="False")'

# 3. Check kubelet version
kubectl --kubeconfig=hcp.yaml get nodes -o json | \
  jq '.items[].status.nodeInfo.kubeletVersion'

# 4. Check node readiness probes
kubectl --kubeconfig=hcp.yaml get nodes -o json | \
  jq '.items[].status'
```

**Common Causes & Fixes:**

#### Cause 1: NetworkUnavailable

**Symptom:**
```bash
Condition: NetworkUnavailable=True
Reason: WeaveNotReady (or your CNI plugin)
```

**Check:**
```bash
# Check CNI plugin deployed
kubectl --kubeconfig=hcp.yaml get pods -n openshift-ovn-kubernetes

# Check network issues
kubectl --kubeconfig=hcp.yaml logs -n openshift-ovn-kubernetes deployment/ovn-controller
```

**Fix:**
```bash
# CNI should deploy automatically
# Wait longer (CNI takes 2-5 minutes to initialize)
sleep 300
kubectl --kubeconfig=hcp.yaml get nodes

# If still failing:
# Check node can reach other nodes
kubectl --kubeconfig=hcp.yaml exec -it pod/busybox -- \
  ping node2-ip

# Check firewall/network policies between nodes
```

#### Cause 2: DiskPressure or MemoryPressure

**Symptom:**
```bash
Condition: DiskPressure=True or MemoryPressure=True
Reason: KubeletHasDiskPressure or KubeletHasMemoryPressure
```

**Check:**
```bash
# Check disk on node
kubectl --kubeconfig=hcp.yaml exec -it busybox -- df -h

# Check memory on node
kubectl --kubeconfig=hcp.yaml exec -it busybox -- free -h

# Check pod logs for memory leaks
kubectl --kubeconfig=hcp.yaml top pods -A | sort -k4 -nr | head -20
```

**Fix:**
```bash
# Identify pod consuming resources
# Delete or scale down:
kubectl --kubeconfig=hcp.yaml delete pod <name> -n <namespace>

# Or increase node resources:
# Edit NodePool to give more memory/disk
nano base/nodepool.yaml
# Change memory: 8Gi → 16Gi
# Commit and push (this will recreate nodes)
```

#### Cause 3: Kubelet Not Starting

**Symptom:**
```bash
Node conditions all False
kubeletVersion: unknown
```

**Check:**
```bash
# SSH to node and check kubelet status (if possible)
ssh user@node-ip sudo systemctl status kubelet

# Or check boot logs
kubectl --kubeconfig=hcp.yaml debug node/node1
# Inside: chroot /host
# cat /var/log/cloud-init-output.log
```

**Fix:**
```bash
# Node needs to be recreated
# Delete the Machine object on Hub
kubectl get machines -A | grep node1
kubectl delete machine <name> -n <namespace>

# Machine controller will recreate
# Monitor: watch -n 5 'kubectl get machines -A'
```

#### Cause 4: SSH Key Not Accepted

**Symptom:**
```bash
Cannot SSH to node
ssh: Permission denied (publickey)
```

**Check:**
```bash
# Verify secret exists on Hub
kubectl get secret -n clusters ssh-key
kubectl get secret -n clusters ssh-key -o json | \
  jq '.data."ssh-publickey"' | base64 -d
```

**Fix:**
```bash
# Recreate secret with correct key
kubectl delete secret -n clusters ssh-key

# Create with correct public key
kubectl create secret generic ssh-key \
  --from-file=ssh-publickey=/path/to/correct/key.pub \
  -n clusters

# Nodes will need to be recreated to pick up new key
# Edit NodePool to trigger node rolling
```

---

## ACM Issues

### ManagedCluster Not Created

**Symptom:**
```bash
kubectl get managedcluster
No resources found
```

After 20+ minutes.

**Diagnosis:**

```bash
# 1. Check control plane is Available
kubectl get hostedcluster example-hcp -n clusters
# Must show: AVAILABLE=True

# 2. Check kubeconfig secret exists
kubectl get secret -n clusters admin-kubeconfig
# Must exist and have data

# 3. Check klusterlet deployment exists
kubectl get deployment -n open-cluster-management-agent -A

# 4. Check klusterlet logs
kubectl logs -n open-cluster-management-agent <pod> -f

# 5. Check Hub can reach cluster's API
kubectl exec -it busybox -n hypershift-system -- \
  curl -k https://api.example-hcp.example.com:6443/api/v1
```

**Common Causes & Fixes:**

#### Cause 1: Control Plane Not Ready

**Fix:**
```bash
# Wait for HostedCluster to become Available
watch -n 10 'kubectl get hostedcluster example-hcp -n clusters'

# Once Available=True, klusterlet will deploy
sleep 300
kubectl get managedcluster
```

#### Cause 2: Kubeconfig Secret Missing

**Check:**
```bash
kubectl get secret -n clusters admin-kubeconfig -o json | jq '.data.kubeconfig' | wc -c
# Should be large number (not 4)
```

**Fix:**
```bash
# If secret exists but empty, wait longer
# HyperShift creates kubeconfig after API ready
watch -n 10 'kubectl get secret -n clusters admin-kubeconfig'

# If secret missing after 20 min, check operator logs
kubectl logs -n hypershift-system deployment/hypershift-operator | grep -i kubeconfig
```

#### Cause 3: Network Connectivity Issue

**Check:**
```bash
# From Hub, try to reach cluster's API
kubectl run -it test --image=busybox --restart=Never -- \
  wget -q -O- https://api.example-hcp.example.com:6443/api/v1

# Check DNS
nslookup api.example-hcp.example.com
```

**Fix:**
```bash
# Ensure DNS resolves to cluster's API LoadBalancer
# Ensure firewall allows access from Hub to cluster API

# Get cluster's API endpoint
kubectl get service -n clusters-example-hcp APIServer -o wide
# Check LoadBalancer IP is correct
```

#### Cause 4: Hub RBAC Restrictions

**Check:**
```bash
# Check if klusterlet ServiceAccount has permissions
kubectl auth can-i create managedclusters --as=system:serviceaccount:open-cluster-management-agent:klusterlet

# Check RBAC role exists
kubectl get clusterrole klusterlet
```

**Fix:**
```bash
# Ensure klusterlet RBAC properly configured
# This usually comes with MCE/ACM installation
kubectl get clusterrolebinding | grep klusterlet

# If missing, reinstall ACM/MCE or apply RBAC manifests
```

---

## Argo Issues

### Application OutOfSync

**Symptom:**
```bash
kubectl get application -n argocd gitops-hcp-scenario1
SYNC STATUS  HEALTH STATUS
OutOfSync    Degraded
```

**Diagnosis:**

```bash
# 1. Check differences
argocd app diff gitops-hcp-scenario1

# 2. Check detailed status
kubectl describe application -n argocd gitops-hcp-scenario1

# 3. Check Argo controller logs
kubectl logs -n argocd deployment/argocd-application-controller -f

# 4. Check if Git repo still accessible
argocd repo list

# 5. Check if manifests valid
kubectl apply -f . --dry-run=client
```

**Common Causes & Fixes:**

#### Cause 1: Manual Cluster Changes (Drift)

**Example:** Someone did `kubectl patch nodepool worker -p '{"spec":{"replicas":5}}'`

**Diagnosis:**
```bash
# See what's different
argocd app diff gitops-hcp-scenario1

# Shows cluster has 5 replicas but Git has 2
```

**Fix:**
```bash
# Option 1: Revert manual change (let Argo win)
kubectl patch nodepool worker -n clusters \
  -p '{"spec":{"replicas":2}}'

# Argo will show synced
kubectl get application -n argocd gitops-hcp-scenario1
# Should show: Synced, Healthy

# Option 2: Update Git to match cluster (let cluster win)
# Edit base/nodepool.yaml to match cluster state
# Commit and push
# Then Argo shows Synced
```

#### Cause 2: Repository URL Changed

**Diagnosis:**
```bash
# Check repository configuration
kubectl get secret -n argocd gitops-hcp-scenario1-repo-* -o json | \
  jq '.data.url'
```

**Fix:**
```bash
# Update repository reference
argocd repo remove <old-url>
argocd repo add <new-url> --ssh-private-key-path ~/.ssh/key

# Or update Application manifest
kubectl patch application -n argocd gitops-hcp-scenario1 \
  -p '{"spec":{"source":{"repoURL":"<new-url>"}}}'
```

#### Cause 3: YAML Syntax Error

**Diagnosis:**
```bash
# Check application events
kubectl describe application -n argocd gitops-hcp-scenario1 | tail -20

# Check controller logs
kubectl logs -n argocd deployment/argocd-application-controller | grep gitops-hcp
```

**Fix:**
```bash
# Validate YAML
kubectl apply -f . --dry-run=client

# Fix issues in Git
git checkout -b fix-yaml
# Edit problematic manifests
git commit -m "Fix YAML syntax"
git push origin fix-yaml

# Once merged, Argo will resync
```

---

## Connectivity Issues

### Cannot Access Cluster API

**Symptom:**
```bash
kubectl --kubeconfig=hcp.yaml cluster-info
The connection to the server was refused - did you mean to hit a different hostname?
```

**Diagnosis:**

```bash
# 1. Check kubeconfig has correct server
grep server hcp.yaml

# 2. Test network connectivity
ping api.example-hcp.example.com

# 3. Test port connectivity
nc -zv api.example-hcp.example.com 6443

# 4. Test with curl
curl -k https://api.example-hcp.example.com:6443

# 5. Check Hub cluster can reach
kubectl run -it test --image=busybox --restart=Never -- \
  curl -k https://api.example-hcp.example.com:6443/api/v1
```

**Common Causes & Fixes:**

#### Cause 1: DNS Not Resolving

**Fix:**
```bash
# Ensure DNS record exists
# Add A record: api.example-hcp.example.com → LoadBalancer IP

# Test resolution
nslookup api.example-hcp.example.com
# Should return IP address

# If local DNS issues:
# Try different DNS server
nslookup -server 8.8.8.8 api.example-hcp.example.com
```

#### Cause 2: Firewall Blocking

**Fix:**
```bash
# Check if port 6443 open
nc -zv api.example-hcp.example.com 6443

# Check security groups (AWS, Azure)
# Ensure ingress rule for port 6443 from your IP

# Check network policies (k8s)
kubectl get networkpolicies -A
```

#### Cause 3: LoadBalancer Not Provisioned

**Check:**
```bash
kubectl get svc -n clusters-example-hcp APIServer -o json | \
  jq '.status.loadBalancer'
```

**Fix:**
```bash
# Wait for LoadBalancer IP assignment
watch -n 10 'kubectl get svc -n clusters-example-hcp APIServer -o wide'

# If stuck in Pending:
# Check cloud provider integration (depends on platform)
# Check sufficient IPs available
# Check cloud provider API errors in logs
```

---

## Credential Issues

### Pull Secret Authentication Failure

**Symptom:**
```bash
Pod error: ImagePullBackOff
Failed to pull image: authentication required
```

**Diagnosis:**

```bash
# 1. Check secret exists
kubectl get secret -n clusters pull-secret

# 2. Verify secret format
kubectl get secret pull-secret -n clusters -o json | \
  jq '.data.".dockerconfigjson"' | base64 -d | jq '.' | head

# 3. Check pull-secret content
cat /path/to/pull-secret.json | jq '.auths' | jq 'keys'
# Should have: quay.io, registry.redhat.io, etc.

# 4. Verify pull-secret is mounted
kubectl get pod -n clusters-example-hcp etcd-0 -o json | \
  jq '.spec.imagePullSecrets'
```

**Common Causes & Fixes:**

#### Cause 1: Expired Pull Secret

**Fix:**
```bash
# Download fresh pull-secret from console.redhat.com
# Delete old secret
kubectl delete secret -n clusters pull-secret

# Create new one
kubectl create secret generic pull-secret \
  --from-file=.dockerconfigjson=~/Downloads/pull-secret.json \
  --type=kubernetes.io/dockerconfigjson \
  -n clusters

# HCP will automatically redeploy with new secret
```

#### Cause 2: Secret in Wrong Namespace

**Fix:**
```bash
# Secret must be in same namespace as HostedCluster
# If HostedCluster is in 'clusters' namespace:
kubectl get secret pull-secret -n clusters

# If not there, copy it:
kubectl get secret pull-secret -n default -o yaml | \
  sed 's/namespace: default/namespace: clusters/' | \
  kubectl apply -f -
```

---

## Infrastructure Issues

### Machine Provisioning Stuck

**Symptom:**
```bash
kubectl get machines -A
NAME              STATE           TYPE
worker1           Provisioning    t3.large
```

After 30+ minutes, still Provisioning.

**Diagnosis:**

```bash
# 1. Check machine status
kubectl get machines -A -o wide

# 2. Check machine conditions
kubectl describe machine <name> -n clusters

# 3. Check machine controller logs
kubectl logs -n hypershift-system deployment/hypershift-operator -f | \
  grep machine

# 4. Check cloud provider status (AWS, Azure, etc.)
# For AWS: check EC2 dashboard for instances
# For Azure: check VMs in portal
# For KubeVirt: check VMs on infrastructure cluster
```

**Common Causes & Fixes:**

#### Cause 1: Cloud Provider Quota Exceeded

**Symptom:**
```
Machine status: "ProvisioningFailed"
Reason: "QuotaExceeded"
```

**Fix:**
```bash
# Check quota on cloud provider
# AWS: check EC2 instance limit
# Azure: check VM quota in subscription
# KubeVirt: check storage quota

# Request quota increase from provider
# Or reduce cluster size (fewer nodes)
```

#### Cause 2: Invalid Credentials

**Symptom:**
```
Machine status: "ProvisioningFailed"
Reason: "AuthenticationFailed"
```

**Fix:**
```bash
# Verify credentials secret exists
kubectl get secret -n clusters kubevirt-credentials
# (or aws-credentials, azure-credentials, etc.)

# Recreate if needed:
kubectl create secret generic kubevirt-credentials \
  --from-file=kubeconfig=/path/to/kubeconfig \
  -n clusters --dry-run=client -o yaml | kubectl apply -f -

# Trigger machine recreation
kubectl delete machine <name> -n clusters
# Machine controller will create new machine
```

#### Cause 3: Storage Unavailable

**Symptom:**
```
Machine stuck in "Provisioning"
PVC stuck "Pending"
```

**Check:**
```bash
# Check storage class
kubectl get storageclass

# Check PVCs
kubectl get pvc -n clusters
```

**Fix:**
```bash
# Ensure storage class exists
# For KubeVirt: ensure 'local' or other class available
kubectl get storageclass local

# If missing, create it:
kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
EOF

# Retry machine creation
kubectl delete machine <name> -n clusters
```

---

## Upgrade Issues

### Control Plane Stuck Upgrading

**Symptom:**
```bash
kubectl get hostedcluster example-hcp
AVAILABLE  PROGRESSING
True       True
```

After 30 minutes, still upgrading.

**Diagnosis:**

```bash
# 1. Check cluster operators
kubectl --kubeconfig=hcp.yaml get clusteroperators

# 2. Check specific operator status
kubectl --kubeconfig=hcp.yaml describe clusteroperator <operator-name>

# 3. Check control plane Pods
kubectl get pods -n clusters-example-hcp

# 4. Check migration status (for database schema changes)
kubectl --kubeconfig=hcp.yaml get pods -n openshift-etcd | grep migration

# 5. Check for blocking issues
kubectl --kubeconfig=hcp.yaml get events -A | grep -i fail
```

**Common Causes & Fixes:**

#### Cause 1: Database Migration Stuck

**Symptom:**
```bash
Pod: etcd-migration
Status: Running
Duration: >20 minutes
```

**Fix:**
```bash
# This is normal for large clusters
# Migration can take 30-60 minutes
# Monitor progress:
kubectl logs -n clusters-example-hcp etcd-migration -f

# If truly stuck:
# Check disk space
kubectl exec -it etcd-0 -n clusters-example-hcp -- df -h

# Check etcd health
kubectl exec -it etcd-0 -n clusters-example-hcp -- etcdctl member list
```

#### Cause 2: Image Pull Timeout

**Symptom:**
```bash
Pod: kube-apiserver-0
Status: ImagePullBackOff
```

**Fix:**
```bash
# Check Pod logs
kubectl logs -n clusters-example-hcp kube-apiserver-0

# Likely pull secret issue - see Credential Issues section
# Or image not accessible - try different image version
```

---

## Log Locations

Quick reference for where to find logs:

| Component | Log Location | Command |
|-----------|--------------|---------|
| HyperShift operator | Pod logs | `kubectl logs -n hypershift-system deployment/hypershift-operator -f` |
| HostedCluster control plane | Pod logs | `kubectl logs -n clusters-<name> <pod> -f` |
| Machine controller | Pod logs | `kubectl logs -n hypershift-system deployment/hypershift-operator` |
| Argo CD | Pod logs | `kubectl logs -n argocd deployment/argocd-application-controller -f` |
| klusterlet (on Hub) | Pod logs | `kubectl logs -n open-cluster-management-agent <pod> -f` |
| kubelet (on node) | SSH logs | `ssh user@node-ip journalctl -u kubelet -n 50` |
| cloud-init (on node) | SSH logs | `ssh user@node-ip cat /var/log/cloud-init-output.log` |
| etcd (in HCP) | Pod logs | `kubectl logs -n clusters-<name> etcd-0 -f` |

---

## Observability Commands

Quick diagnosis commands by scenario:

### Scenario 1: Provisioning

```bash
# Quick health check
echo "=== HostedCluster ===" && \
  kubectl get hostedcluster -n clusters example-hcp && \
echo "=== Control Plane ===" && \
  kubectl get pods -n clusters-example-hcp && \
echo "=== Nodes ===" && \
  kubectl --kubeconfig=hcp.yaml get nodes
```

### Scenario 3: Scaling

```bash
# Monitor scaling
echo "=== NodePool ===" && \
  kubectl get nodepool -n clusters && \
echo "=== Machines ===" && \
  kubectl get machines -A && \
echo "=== Nodes ===" && \
  kubectl --kubeconfig=hcp.yaml get nodes -o wide
```

### Scenario 4: Upgrades

```bash
# Monitor upgrade
echo "=== HostedCluster ===" && \
  kubectl get hostedcluster -n clusters example-hcp && \
echo "=== Cluster Operators ===" && \
  kubectl --kubeconfig=hcp.yaml get clusteroperators && \
echo "=== Nodes ===" && \
  kubectl --kubeconfig=hcp.yaml get nodes
```

---

## Getting Help

If issues persist:

1. **Collect logs:**
   ```bash
   # Save all relevant logs
   kubectl logs -n hypershift-system deployment/hypershift-operator > operator.log
   kubectl logs -n clusters-example-hcp -A > hcp-logs.log
   kubectl get events -n clusters -o wide > events.log
   tar czf debug-info.tar.gz *.log
   ```

2. **Open issue with:**
   - Symptom description
   - Relevant logs (above)
   - Commands run
   - Expected vs actual behavior

3. **References:**
   - HyperShift docs: [hypershift-docs.netlify.app](https://hypershift-docs.netlify.app/)
   - Red Hat support: [support.redhat.com](https://support.redhat.com)
   - Community: [openshift/hypershift GitHub](https://github.com/openshift/hypershift)

---

**Last Updated:** April 2, 2026
