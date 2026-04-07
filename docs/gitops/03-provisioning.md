# Scenario 1: Provisioning via GitOps

## Overview

Scenario 1 demonstrates how to provision a complete HyperShift Hosted Control Plane using declarative Git-based manifests synchronized by Argo CD.

**Key Concepts:**
- Declaring infrastructure as code in Git
- Single-source-of-truth workflow
- Automated reconciliation by HyperShift operator
- ACM auto-import and cluster discovery

**Duration:** 45-60 minutes  
**Files:** Located in `examples/gitops-kubevirt/01-provision/`

---

## Conceptual Flow

```
┌─────────────────────────────────────────────────────────────┐
│ Step 1: Manifest in Git                                     │
│ ├── HostedCluster: Desired HCP configuration                │
│ ├── NodePool: Worker node specification                     │
│ └── Argo Application: Sync definition                       │
└─────────────────────────────────────────────────────────────┘
                           │
                           │ Argo detects
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ Step 2: Argo CD Syncs to Hub                                │
│ └── kubectl apply: manifests → cluster                      │
└─────────────────────────────────────────────────────────────┘
                           │
                           │ Kubernetes admission
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ Step 3: HyperShift Operator Reconciles                      │
│ ├── Validates HostedCluster/NodePool                        │
│ ├── Creates hosted namespace                                │
│ ├── Deploys control plane Pods                              │
│ └── Creates NodePool machines                               │
└─────────────────────────────────────────────────────────────┘
                           │
                           │ API server responds
                           │ Nodes boot
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ Step 4: Cluster Operational                                 │
│ ├── ManagedCluster appears in ACM                           │
│ ├── Kubeconfig available for access                         │
│ └── Ready for workload deployment                           │
└─────────────────────────────────────────────────────────────┘
```

---

## Core Manifest: HostedCluster

This is what you declare to create a cluster:

```yaml
apiVersion: hypershift.openshift.io/v1beta1
kind: HostedCluster
metadata:
  name: example-hcp
  namespace: clusters
spec:
  # Release image - determines OpenShift version
  release:
    image: quay.io/openshift-release-dev/ocp-release:4.17.0-x86_64

  # Network configuration
  networking:
    networkType: OVNKubernetes
    clusterNetwork:
      - cidr: "10.128.0.0/14"
    serviceNetwork:
      - cidr: "172.30.0.0/16"
    machineNetwork:
      - cidr: "192.168.126.0/24"

  # Base domain for API, app routes
  baseDomain: example.com

  # Control plane availability (SingleReplica or HighlyAvailable)
  controlPlaneAvailabilityPolicy: SingleReplica

  # Platform - where nodes will run (KubeVirt, AWS, Azure, etc.)
  platform:
    type: KubeVirt
    kubevirt:
      credentials:
        infraSecretRef:
          name: kubevirt-credentials
      generateSSH: true
      memory: 4Gi
      cores: 2
      rootVolume:
        accessModes: [ "ReadWriteOnce" ]
        storageClass: local

  # Credentials for image pull and SSH
  pullSecret:
    name: pull-secret
  sshKey:
    name: ssh-key

  # Service publishing strategy
  services:
    - service: APIServer
      servicePublishingStrategy:
        type: LoadBalancer
    - service: OAuthServer
      servicePublishingStrategy:
        type: Route
    - service: OIDC
      servicePublishingStrategy:
        type: Route
    - service: Konnectivity
      servicePublishingStrategy:
        type: Route
    - service: Ignition
      servicePublishingStrategy:
        type: Route

  # DNS
  dns:
    baseDomain: example.com

  # Optional: enable etcd encryption
  secretEncryption:
    type: aescbc
    aescbc:
      activeKey:
        name: etcd-encryption-key

  # Optional: resource quotas
  resourceQuota:
    enabled: true

  # Optional: node port ranges
  nodePort:
    address: "0.0.0.0"
```

### Understanding Each Section

#### Release (OpenShift Version)

```yaml
spec:
  release:
    image: quay.io/openshift-release-dev/ocp-release:4.17.0-x86_64
```

- Determines cluster version (4.14, 4.15, 4.16, 4.17, etc.)
- Must match current/recent releases
- HyperShift downloads and caches image
- Update this to upgrade cluster version

#### Networking

```yaml
spec:
  networking:
    networkType: OVNKubernetes          # Overly Verbose Networking
    clusterNetwork:
      - cidr: "10.128.0.0/14"          # Pod network
    serviceNetwork:
      - cidr: "172.30.0.0/16"          # Service network
    machineNetwork:
      - cidr: "192.168.126.0/24"       # Machine/node network
```

- **clusterNetwork:** Where Pods run (10.128.0.0/14 = 10.128.0.0 to 10.191.255.255)
- **serviceNetwork:** Where Services are exposed
- **machineNetwork:** Where nodes (VMs) get addresses
- All three must not overlap

#### Platform

```yaml
spec:
  platform:
    type: KubeVirt                      # or AWS, Azure, Agent
    kubevirt:
      credentials:
        infraSecretRef:
          name: kubevirt-credentials   # Must exist in hub cluster
      memory: 4Gi                       # Per-node memory
      cores: 2                          # Per-node CPU cores
```

Customize per platform:
- **KubeVirt:** Credentials reference, memory/CPU
- **AWS:** Region, zone, machine types
- **Azure:** Resource group, subscription ID
- **Agent:** None (nodes provided externally)

#### Credentials

```yaml
spec:
  pullSecret:
    name: pull-secret                   # Must be pre-created in hub
  sshKey:
    name: ssh-key                       # Must be pre-created in hub
```

Both secrets must exist on Hub cluster. See [02-getting-started.md](./02-getting-started.md#secrets-setup).

#### Services

```yaml
spec:
  services:
    - service: APIServer
      servicePublishingStrategy:
        type: LoadBalancer              # Expose via LoadBalancer
    - service: OAuthServer
      servicePublishingStrategy:
        type: Route                     # Expose via Route
```

Options:
- **LoadBalancer:** External IP, slow, stable
- **Route:** OpenShift-specific, internal by default
- **ClusterIP:** Hub-internal only

---

## Core Manifest: NodePool

Worker node specification:

```yaml
apiVersion: hypershift.openshift.io/v1beta1
kind: NodePool
metadata:
  name: worker
  namespace: clusters
spec:
  # Must match HostedCluster name
  clusterName: example-hcp

  # Release image (can differ from control plane)
  release:
    image: quay.io/openshift-release-dev/ocp-release:4.17.0-x86_64

  # Replicas - how many worker nodes to create
  replicas: 2

  # Update strategy
  management:
    autoRepair: true
    upgradeType: InPlace               # or Replace for faster upgrade

  # Platform-specific config
  platform:
    type: KubeVirt
    kubevirt:
      rootVolume:
        accessModes: [ "ReadWriteOnce" ]
        storageClass: local
      cores: 2
      memory: 8Gi

  # Node template
  nodeDrainTimeout: 0s
  nodeVolumeDetachTimeout: 0s

  # Optional: initial node configuration
  config:
    - name: 99-kubevirt-kernel-tuning
      kind: MachineConfig
      apiVersion: machineconfiguration.openshift.io/v1
      spec:
        config:
          ignition:
            version: 3.2.0
          storage:
            files:
              - path: /etc/sysctl.d/99-kubevirt.conf
                mode: 0644
                contents:
                  source: data:,net.ipv4.tcp_timestamps%3D0
```

### Understanding NodePool Fields

#### Replicas

```yaml
spec:
  replicas: 2
```

- Initial number of worker nodes
- Can be changed to scale up/down
- Should not exceed cluster capacity

#### Management

```yaml
spec:
  management:
    autoRepair: true                    # Auto-heal failed nodes
    upgradeType: InPlace                # or Replace (see Scenario 4)
```

- **autoRepair:** Automatically recreate failed nodes
- **upgradeType:** How to update nodes during cluster upgrades

#### Platform

```yaml
spec:
  platform:
    type: KubeVirt
    kubevirt:
      cores: 2
      memory: 8Gi
      rootVolume:
        storageClass: local
```

Must match platform types available on infrastructure.

---

## Drift Management

GitOps maintains Git as source of truth through "drift detection":

### What is Drift?

```
Git State:   2 replicas
Cluster:     3 replicas (someone did `kubectl scale`)

Argo detects mismatch = drift
```

### Argo Sync Strategies

| Strategy | Behavior | Use Case |
|----------|----------|----------|
| **Auto Sync** | Continuously apply Git state | Production (safe) |
| **Manual Sync** | Wait for approval before applying | Testing, dev |
| **Selective Sync** | Choose specific resources to sync | Complex changes |

### Configuring in Argo Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gitops-hcp-scenario1
spec:
  syncPolicy:
    automated:
      prune: true                       # Remove cluster-only objects
      selfHeal: true                    # Sync on drift detection
    syncOptions:
      - CreateNamespace=true
```

### Handling Drift Carefully

**Safe approach:**

```bash
# 1. Always change Git first
git checkout -b scale-nodes
# Edit base/nodepool.yaml: change replicas
git commit -m "Scale to 3 nodes"
git push origin scale-nodes

# 2. Create PR for review
# (Someone approves change)

# 3. Merge to main
git checkout main
git merge scale-nodes

# 4. Argo automatically syncs
# No manual kubectl commands needed
```

**Dangerous approach (avoid):**

```bash
# DON'T do this:
kubectl patch nodepool worker -p '{"spec":{"replicas":3}}'
# Now Git doesn't match cluster
# Argo will either:
#   - Revert your change (if autoSync enabled)
#   - Show OutOfSync status (if manual)
# This causes confusion and accidents
```

---

## Customization Points

### 1. Base Domain

The domain where your cluster's API will be accessible:

```yaml
baseDomain: example.com
# Results in:
# - API: api.example-hcp.example.com
# - Apps: *.apps.example-hcp.example.com
```

Customize:
```yaml
baseDomain: my-company.com            # Your domain
baseDomain: prod.my-company.com       # Environment-scoped
baseDomain: us-east-1.my-company.com  # Region-scoped
```

### 2. Release Image

Choose OpenShift version:

```yaml
release:
  image: quay.io/openshift-release-dev/ocp-release:4.17.0-x86_64
```

Supported versions:
- 4.14.x (stable)
- 4.15.x (stable)
- 4.16.x (stable)
- 4.17.x (latest)

### 3. Node Count and Size

Horizontal and vertical scaling:

```yaml
# In NodePool:
spec:
  replicas: 2              # Horizontal: add/remove nodes

# In platform:
spec:
  platform:
    kubevirt:
      cores: 2             # Vertical: CPU per node
      memory: 8Gi          # Vertical: RAM per node
```

### 4. Network Ranges

IMPORTANT: Ranges must not overlap and match infrastructure:

```yaml
networking:
  clusterNetwork:
    - cidr: "10.128.0.0/14"    # 4000+ IPs for Pods
  serviceNetwork:
    - cidr: "172.30.0.0/16"    # 65k IPs for Services
  machineNetwork:
    - cidr: "192.168.126.0/24"  # 256 IPs for nodes
```

Validate before deploying:
```bash
# Ensure no overlaps
# 10.128.0.0/14 overlaps with:
#   - 10.128.0.0 to 10.191.255.255
# 172.30.0.0/16 = 172.30.0.0 to 172.30.255.255
# 192.168.126.0/24 = 192.168.126.0 to 192.168.126.255

# No overlap = good!
```

### 5. Service Publishing

How to access the cluster's API:

```yaml
# LoadBalancer (external, slow)
- service: APIServer
  servicePublishingStrategy:
    type: LoadBalancer

# Route (internal, fast, OCP-specific)
- service: APIServer
  servicePublishingStrategy:
    type: Route

# NodePort (for advanced networking)
- service: APIServer
  servicePublishingStrategy:
    type: NodePort
```

---

## Multi-Cluster Patterns

### Pattern 1: Multiple Independent Clusters

```
Git Repository:
├── 01-provision/
│   └── base/
│       ├── hostedcluster.yaml    (example-hcp-1)
│       └── nodepool.yaml
├── 02-provision/
│   └── base/
│       ├── hostedcluster.yaml    (example-hcp-2)
│       └── nodepool.yaml

Argo Applications:
├── gitops-hcp-scenario1-a    (points to 01-provision/)
└── gitops-hcp-scenario1-b    (points to 02-provision/)
```

Each cluster in separate directory, separate Application.

### Pattern 2: Environment-Based Overlays

```
Git Repository:
└── clusters/
    ├── base/
    │   ├── hostedcluster.yaml
    │   └── nodepool.yaml
    ├── overlays/
    │   ├── dev/
    │   │   ├── kustomization.yaml
    │   │   └── nodepool-patch.yaml    (1 replica)
    │   ├── staging/
    │   │   ├── kustomization.yaml
    │   │   └── nodepool-patch.yaml    (2 replicas)
    │   └── prod/
    │       ├── kustomization.yaml
    │       └── nodepool-patch.yaml    (5 replicas)

Argo Applications:
├── gitops-hcp-dev       (path: clusters/overlays/dev)
├── gitops-hcp-staging   (path: clusters/overlays/staging)
└── gitops-hcp-prod      (path: clusters/overlays/prod)
```

Same base, different overlays for each environment.

### Pattern 3: Helm-Based

```
Git Repository:
└── charts/
    └── hostedcluster/
        ├── Chart.yaml
        ├── values.yaml
        ├── templates/
        │   ├── hostedcluster.yaml
        │   └── nodepool.yaml
        └── environments/
            ├── dev/values.yaml
            ├── staging/values.yaml
            └── prod/values.yaml

Argo Application:
spec:
  source:
    repoURL: https://github.com/example/gitops
    path: charts/hostedcluster
    helm:
      valueFiles:
        - environments/prod/values.yaml
```

---

## Verification Procedure

After deploying via Argo:

### 1. Check Argo Status (Immediate)

```bash
kubectl get application -n argocd gitops-hcp-scenario1
# Should show:
# NAME                        SYNC STATUS  HEALTH STATUS
# gitops-hcp-scenario1        Synced       Healthy
```

### 2. Check HostedCluster Status (5-10 minutes)

```bash
kubectl get hostedcluster -n clusters example-hcp -o wide
# Should show:
# NAME          AVAILABLE  PROGRESSING  AGE
# example-hcp   False      True         2m

# After ~8 minutes:
# NAME          AVAILABLE  PROGRESSING  AGE
# example-hcp   True       False        10m
```

### 3. Check Control Plane Pods (5-10 minutes)

```bash
kubectl get pods -n clusters-example-hcp -o wide
# Should see:
# - etcd-0
# - kube-apiserver-0
# - kube-controller-manager-0
# - oauth-openshift-0
# All should be Running
```

### 4. Check NodePool Status (20-40 minutes)

```bash
kubectl get nodepool -n clusters example-hcp
# Should show:
# NAME     CLUSTER       NODES  READY NODES  UPDATED NODES  UNAVAILABLE NODES
# example  example-hcp   2      2            2              0
```

### 5. Check Nodes in Hosted Cluster (30-40 minutes)

```bash
# Get kubeconfig
kubectl get secret -n clusters admin-kubeconfig -o json | \
  jq -r '.data.kubeconfig' | base64 -d > /tmp/hcp.yaml

# Check nodes
kubectl --kubeconfig=/tmp/hcp.yaml get nodes
# Should show:
# NAME    STATUS   ROLES    AGE    VERSION
# node1   Ready    worker   30m    v1.27.0
# node2   Ready    worker   30m    v1.27.0
```

### 6. Check ACM Integration (10-15 minutes)

```bash
# Check ManagedCluster created
kubectl get managedcluster example-hcp
# Should show: True in Available column

# Check cluster in console
oc login hub-cluster
oc get managedcluster
oc describe managedcluster example-hcp
```

---

## Change Control Workflow

### Workflow: Safe Cluster Updates via Git

All cluster changes follow this process:

```
1. Create Feature Branch
   git checkout -b update-nodepool

2. Make Changes
   # Edit base/nodepool.yaml
   nano base/nodepool.yaml

3. Commit to Branch
   git add base/nodepool.yaml
   git commit -m "Increase node count to 3"

4. Push & Create PR
   git push origin update-nodepool
   # Open PR on GitHub

5. Review & Approval
   # Team members review
   # Approved? Proceed to merge

6. Merge to Main
   git checkout main
   git merge update-nodepool

7. Argo Detects Change
   # In 3-5 minutes

8. Cluster Updated
   # Argo applies new manifest
   # HyperShift reconciles
   # Nodes scale up

9. Verify Success
   kubectl get nodepool
   # Should show 3 ready nodes
```

**Advantages:**
- Full audit trail of who changed what
- Code review ensures quality
- Easy to rollback (`git revert`)
- Accident prevention

---

## Troubleshooting Provisioning

### HostedCluster Stuck "Progressing"

```bash
# Check detailed status
kubectl get hostedcluster -n clusters example-hcp -o json | \
  jq '.status.conditions[] | select(.type=="Available")'

# Look at operator logs
kubectl logs -n hypershift-system deployment/hypershift-operator -f | \
  grep example-hcp

# Common causes:
# 1. Pull secret invalid
#    kubectl get secret -n clusters pull-secret
#    Verify .dockerconfigjson is valid

# 2. Release image not accessible
#    kubectl logs -n clusters-example-hcp pod/etcd-0
#    Look for image pull errors

# 3. Base domain DNS not resolving
#    nslookup api.example-hcp.example.com
#    Should return IP

# 4. Insufficient cluster resources
#    kubectl top nodes
#    kubectl top pods -A
```

### Nodes Not Becoming Ready

```bash
# Check node status
kubectl --kubeconfig=/tmp/hcp.yaml describe node node1

# Look for:
# - NotReady reason (DiskPressure, MemoryPressure, NetworkUnavailable)
# - Conditions with False status

# Check kubelet logs (if SSH accessible)
ssh user@node-ip journalctl -u kubelet -n 50

# Check ignition errors (cloud-init)
ssh user@node-ip cat /var/log/cloud-init-output.log

# Common fixes:
# 1. Update SSH key in NodePool manifest
# 2. Ensure storage provisioning working
# 3. Check node network connectivity
# 4. Verify CNI deployment (should be automatic)
```

### ManagedCluster Not Created

```bash
# Check if klusterlet deployed
kubectl get deployment -n open-cluster-management-agent

# Check klusterlet pod logs
kubectl logs -n open-cluster-management-agent <pod> -f

# Check HCP has admin kubeconfig
kubectl get secret -n clusters admin-kubeconfig

# Manually trigger klusterlet deployment
kubectl rollout restart deployment/hypershift-operator \
  -n hypershift-system

# Wait and check again
sleep 30
kubectl get managedcluster example-hcp
```

---

## Best Practices

1. **Always use Git for changes** - Never use `kubectl patch` directly
2. **Test on dev first** - Deploy to dev cluster before prod
3. **Use namespaces** - Isolate clusters by namespace
4. **Monitor Argo** - Watch for OutOfSync status
5. **Keep manifests simple** - Avoid complex overlays initially
6. **Document customizations** - Comment on non-obvious changes
7. **Version everything** - Tag releases in Git
8. **Audit logs** - Review cluster events regularly

---

## What Happens Next: ACM Takes Over

After your cluster is provisioned via GitOps and the control plane becomes Available, ACM automatically discovers and imports it for management.

### The Auto-Import Process

Within 10-15 minutes of the control plane becoming Available, the following happens automatically:

1. **ManagedCluster Creation** - ACM's hypershift-addon-agent creates a ManagedCluster resource
2. **Klusterlet Deployment** - ACM's cluster-import-controller deploys the klusterlet agent to the Hub
3. **Cluster Registration** - Klusterlet connects to the hosted cluster and registers it with ACM
4. **Management Enabled** - Full ACM capabilities become available

### What You Get

Once auto-import completes, you can:
- **Apply policies** to enforce configuration compliance
- **View cluster health** in the ACM console
- **Deploy applications** across multiple clusters
- **Monitor metrics** from a unified dashboard

### Verify Auto-Import

Check that your cluster was successfully imported:

```bash
# Check ManagedCluster exists
kubectl get managedcluster <cluster-name>

# Verify cluster is Available
kubectl get managedcluster <cluster-name> \
  -o jsonpath='{.status.conditions[?(@.type=="ManagedClusterConditionAvailable")].status}'
# Expected: True

# Check klusterlet is running
kubectl get pods -n klusterlet-<cluster-name>
```

### Next Steps

Now that you understand provisioning, dive into ACM management:

- **[04-acm-integration-overview.md](./04-acm-integration-overview.md)** - Understand what ACM provides for hosted clusters
- **[05-auto-import-deep-dive.md](./05-auto-import-deep-dive.md)** - Deep dive into auto-import mechanics and troubleshooting
- **[08-troubleshooting.md](./08-troubleshooting.md)** - Troubleshoot import issues if auto-import fails

Your cluster is now ready for ACM-based management, policy enforcement, and multi-cluster operations.

---

## Next Steps

- [06-managing-scale-operations.md](./06-managing-scale-operations.md) - Scenario 3: Scale the cluster
- [07-managing-upgrades.md](./07-managing-upgrades.md) - Scenario 4: Upgrade the cluster
- [08-troubleshooting.md](./08-troubleshooting.md) - Debug specific issues

---

**Last Updated:** April 10, 2026
