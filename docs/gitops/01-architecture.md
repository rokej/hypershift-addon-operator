# Architecture: GitOps HCP with ACM

## System Overview

This document explains the complete architecture of GitOps-driven HyperShift Hosted Control Planes with ACM auto-import.

### Architecture Diagram

```
┌────────────────────────────────────────────────────────────────────┐
│ Developer Workstation                                              │
└────────────────────────────────────────────────────────────────────┘
                           │
                           │ git push
                           │
                           ▼
┌────────────────────────────────────────────────────────────────────┐
│ Git Repository (GitHub/GitLab)                                     │
│ ├── examples/gitops-kubevirt/01-provision/                         │
│ │   ├── base/hostedcluster.yaml                                    │
│ │   ├── base/nodepool.yaml                                         │
│ │   └── argo-application.yaml                                      │
│ └── examples/gitops-kubevirt/03-scaling/                           │
│     └── operations/01-scale-up.yaml                                │
└────────────────────────────────────────────────────────────────────┘
                           │
                    (webhook/polling)
                           │
                           ▼
┌────────────────────────────────────────────────────────────────────┐
│ Hub Cluster (OpenShift 4.14+)                                      │
│ ┌──────────────────────────────────────────────────────────────┐   │
│ │ Argo CD (argocd namespace)                                   │   │
│ │ ├── Watches Git repository                                   │   │
│ │ ├── Syncs manifests to cluster                               │   │
│ │ └── Reports Application status                               │   │
│ └──────────────────────────────────────────────────────────────┘   │
│                           │ applies                                │
│                           ▼                                        │
│ ┌──────────────────────────────────────────────────────────────┐   │
│ │ HyperShift Operator (hypershift-system namespace)            │   │
│ │ ├── Watches HostedCluster resources                          │   │
│ │ ├── Creates control plane Pods                               │   │
│ │ ├── Manages service publishing (LoadBalancer/Route)          │   │
│ │ └── Deploys klusterlet (ACM agent)                           │   │
│ └──────────────────────────────────────────────────────────────┘   │
│                           │                                        │
│ ┌──────────────────────────────────────────────────────────────┐   │
│ │ ACM/MCE (open-cluster-management namespace)                  │   │
│ │ ├── Detects new ManagedClusters                              │   │
│ │ ├── Applies cluster policies                                 │   │
│ │ └── Provides cluster console access                          │   │
│ └──────────────────────────────────────────────────────────────┘   │
│                           │                                        │
│ ┌──────────────────────────────────────────────────────────────┐   │
│ │ Hosted Control Planes (hosted-* namespaces)                  │   │
│ │ ├── API Server, etcd, Controllers                            │   │
│ │ ├── Pull secret, SSH key Secrets                             │   │
│ │ └── Admin kubeconfig Secret                                  │   │
│ └──────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────┘
                           │
                           │ kubeconfig
                           │
                           ▼
┌────────────────────────────────────────────────────────────────────┐
│ Hosted Cluster (Separate Infrastructure)                           │
│ ├── Worker Nodes (KubeVirt VMs, AWS EC2, Azure VMs, etc.)          │
│ ├── kubelet, kube-proxy, CNI                                       │
│ └── klusterlet Pod (connects back to Hub for ACM management)       │
└────────────────────────────────────────────────────────────────────┘
```

### Flow Steps

1. **Developer commits to Git** - Updates Argo Application manifest
2. **Argo CD detects change** - Polls repository or receives webhook
3. **Argo syncs to Hub cluster** - `kubectl apply` of manifests
4. **HyperShift operator reconciles** - Creates/updates hosted control plane
5. **Klusterlet deployed** - HyperShift deploys ACM agent pod
6. **ACM auto-detects** - ManagedCluster created automatically
7. **Worker nodes boot** - SSH key from secret, kubeconfig available
8. **Cluster joins ACM** - Full cluster management enabled

---

## Responsibility Matrix

This table clarifies who creates and manages what:

| Resource | Created By | Managed By | Notes |
|----------|-----------|------------|-------|
| Git Repository | Developer | Developer | Single source of truth |
| Argo Application | Developer (via Git) | Argo CD | Defines sync behavior |
| HostedCluster | Argo CD (applies manifest) | HyperShift Operator | Describes desired HCP state |
| NodePool | Argo CD (applies manifest) | HyperShift Operator | Describes worker nodes |
| Control Plane Pods | HyperShift Operator | HyperShift Operator + Kubernetes | etcd, API server, controllers |
| Service (API endpoint) | HyperShift Operator | Kubernetes/Cloud provider | LoadBalancer or Route |
| klusterlet Pod | HyperShift Operator | HyperShift Operator | ACM agent in HCP |
| ManagedCluster | ACM (auto-detect) | ACM | Cluster representation in ACM |
| Worker Nodes | HyperShift Operator | Cloud provider/IaaS | EC2, VMs, etc. |
| Pull Secret | Developer (pre-create) | Referenced by HostedCluster | Lives on Hub cluster |
| SSH Key | Developer (pre-create) | Referenced by NodePool | Lives on Hub cluster |
| Admin kubeconfig | HyperShift Operator | HyperShift Operator | Auto-generated, secret |
| Cluster policies | Developer (via Git) | ACM | Applied after auto-import |

### Key Insight: Separation of Concerns

```
Developer responsibility:
  ├── Git manifests (what you want)
  ├── Pre-created credentials (secrets)
  └── Policy definitions

Argo CD responsibility:
  └── Sync Git to cluster

HyperShift Operator responsibility:
  ├── Translate manifest to running infrastructure
  ├── Manage control plane lifecycle
  └── Deploy klusterlet for ACM

ACM responsibility:
  ├── Detect ManagedCluster
  ├── Apply policies
  └── Provide cluster dashboard
```

---

## You Declare vs. ACM Creates

Understanding what you control and what's automatic:

### You Declare (in Git)

```yaml
apiVersion: hypershift.openshift.io/v1beta1
kind: HostedCluster
metadata:
  name: example-hcp
  namespace: clusters
spec:
  baseDomain: example.com
  controlPlaneAvailabilityPolicy: SingleReplica
  platform:
    type: KubeVirt
    kubevirt:
      credentials:
        infraSecretRef:
          name: kubevirt-credentials
  networking:
    networkType: OVNKubernetes
    clusterNetwork:
      - cidr: "10.128.0.0/14"
    serviceNetwork:
      - cidr: "172.30.0.0/16"
    machineNetwork:
      - cidr: "192.168.126.0/24"
  pullSecret:
    name: pull-secret
  sshKey:
    name: ssh-key
```

### ACM Automatically Creates

```yaml
# When HCP is Created...

apiVersion: cluster.open-cluster-management.io/v1
kind: ManagedCluster
metadata:
  name: example-hcp
  labels:
    cloud: auto
    vendor: OpenShift
spec:
  hubAcceptsClient: true
  leaseDurationSeconds: 60

# When klusterlet deploys...
apiVersion: agent.open-cluster-management.io/v1
kind: KlusterletAddonConfig
metadata:
  name: example-hcp
  namespace: example-hcp
spec:
  clusterName: example-hcp
  clusterNamespace: example-hcp
  clusterLabels:
    cloud: auto
    vendor: OpenShift
  applicationManager:
    enabled: true
  policyController:
    enabled: true
  searchCollector:
    enabled: true
  certPolicyController:
    enabled: true
  iamPolicyController:
    enabled: true
```

**Result:** You manage Git, HyperShift handles operations, ACM handles lifecycle.

---

## Auto-Import Lifecycle

This is the detailed timeline of how ACM discovers a new hosted cluster:

### Phase 1: Cluster Creation (Minutes 0-10)

```
Time  Event
────  ────────────────────────────────────────────────
T+0s  Developer: git push with new HostedCluster manifest
      Argo CD: Polls repository (default every 3 minutes)
      
T+3m  Argo CD: Detects new HostedCluster
      Argo CD: Applies manifest to Hub cluster (kubectl apply)
      
T+3m  HyperShift Operator: Reconciles HostedCluster
      HyperShift: Creates hosted-<name> namespace
      HyperShift: Pulls release image (can take 1-2 minutes)
      
T+5m  HyperShift: Starts control plane Pods
      - etcd: initializes data
      - API server: starts listening
      - Controllers: begin reconciliation
      
T+8m  HyperShift: Control plane is Progressing=True
      HyperShift: Deployment checks (API responding, etc.)
```

### Phase 2: ACM Detection (Minutes 10-15)

```
Time  Event
────  ────────────────────────────────────────────────
T+8m  HyperShift Operator: Deploys klusterlet Pod
      - Pod requests kubeconfig to join Hub
      - Waits for kubeconfig Secret creation
      
T+10m HyperShift: Creates admin kubeconfig Secret
      
T+10m klusterlet Pod: Reads kubeconfig
      klusterlet: Connects to Hub cluster as agent
      klusterlet: Registers with ACM
      
T+12m ACM Hub Controller: Detects new registration
      ACM: Creates ManagedCluster object
      ACM: Labels with cluster metadata
      ACM: Sets status to "Available"
      
T+15m ACM console: Cluster visible in "All Clusters"
      ACM: Can apply policies and governance
```

### Phase 3: Worker Nodes Boot (Minutes 15-40)

```
Time  Event
────  ────────────────────────────────────────────────
T+0s  (Parallel with cluster creation)
      HyperShift Operator: Reconciles NodePool
      HyperShift: Creates machine.openshift.io resources
      
T+5m  Machine Controller: Requests VM creation
      Cloud provider: Starts provisioning (KubeVirt, EC2, etc.)
      
T+20m Machines: VMs created, booting
      DHCP: Assigns IPs
      ignition: Runs node configuration
      
T+30m Nodes: Initial setup complete
      
T+40m Nodes: Fully Ready (CNI, storage provisioner, etc.)
      Pods: Can be scheduled
      Cluster: Fully operational
```

### Observing the Timeline

```bash
# T+3m: Argo Application shows "Synced"
kubectl get application -n argocd gitops-hcp-scenario1

# T+5m: HostedCluster appears, Progressing=True
kubectl get hostedcluster -n clusters example-hcp -o json | \
  jq '.status.conditions[] | select(.type=="Progressing")'

# T+8m: API server responding
kubectl --kubeconfig=hcp-kubeconfig cluster-info

# T+12m: ManagedCluster appears
kubectl get managedcluster example-hcp

# T+40m: Nodes Ready
kubectl --kubeconfig=hcp-kubeconfig get nodes
```

---

## When to Disable Auto-Import and Why

ACM auto-import is enabled by default, but you may want to disable it in these scenarios:

### Scenario 1: Development/Testing

**Situation:** You're testing cluster creation and don't want ACM management yet.

**Solution:** Disable auto-import in HostedCluster:

```yaml
apiVersion: hypershift.openshift.io/v1beta1
kind: HostedCluster
metadata:
  name: test-hcp
  annotations:
    hypershift.openshift.io/skip-release-image-verification: "true"
spec:
  autoscaling:
    maxNodesTotal: 100
  # ... rest of spec
```

Wait, that's not the right annotation. The actual approach is:

```bash
# Don't deploy klusterlet at all - just don't reference ACM
# The cluster works without it, just without ACM management
```

Actually, HyperShift deploys klusterlet by default. To prevent ACM from creating ManagedCluster, use:

```yaml
apiVersion: hypershift.openshift.io/v1beta1
kind: HostedCluster
metadata:
  name: test-hcp
spec:
  # ... normal spec
  # Absence of special configuration = automatic klusterlet deployment
```

**Note:** There's no "disable auto-import" flag. Instead, don't add ACM configurations and skip importing if not needed.

### Scenario 2: Air-Gapped Environment

**Situation:** Your cluster can't connect to the ACM Hub.

**Solution:** Configure network policies and firewall rules. klusterlet needs outbound HTTPS to Hub.

### Scenario 3: Early Lifecycle

**Situation:** Cluster isn't fully ready for policy enforcement yet.

**Solution:** Let auto-import happen, but don't apply policies until ready:

```bash
# Delete ManagedCluster to pause management
kubectl delete managedcluster example-hcp

# When ready, re-create it
kubectl apply -f managedcluster.yaml
```

### Scenario 4: Multi-Hub Setup

**Situation:** Cluster should be managed by multiple ACM instances.

**Solution:** Deploy multiple klusterlets with different hub configurations.

### Why Disable Auto-Import?

| Reason | Impact | When |
|--------|--------|------|
| Testing | Faster iteration without ACM overhead | Dev/test clusters |
| Staging | Ready cluster, import later | Staged rollouts |
| Compliance | Cluster exists before governance applied | Audit requirements |
| Integration | Manual import with custom settings | Special scenarios |

### Best Practice

**For production:** Keep auto-import enabled. The benefits outweigh the costs:
- Automatic cluster discovery
- Built-in health monitoring
- Policy enforcement
- Disaster recovery integration

---

## Design Principles

### 1. **Git is Source of Truth**

Every cluster change goes through Git:
- New manifests → Git commit
- Configuration updates → Git branch + PR
- Rollbacks → `git revert`

**Benefit:** Audit trail, code review, history

```bash
# Example: Scaling via Git
git checkout -b scale-nodes
# Edit 03-scaling/operations/01-scale-up.yaml
git commit -m "Scale production-pool to 5 replicas"
git push origin scale-nodes
# Create PR, wait for approval
# Merge to main → Argo detects → syncs to cluster
```

### 2. **Infrastructure as Code**

Clusters are defined as code, versioned like software:

```yaml
# This is your cluster definition
apiVersion: hypershift.openshift.io/v1beta1
kind: HostedCluster
metadata:
  name: prod-hcp
  namespace: clusters
spec:
  release:
    image: quay.io/openshift-release-dev/ocp-release:4.17.0-x86_64
  platform:
    type: AWS
    aws:
      region: us-east-1
      zone: us-east-1a
```

**Benefit:** Reproducible, testable, versionable

### 3. **Declarative, Not Imperative**

Describe desired state, not steps:

```bash
# ❌ Wrong (imperative)
kubectl patch hostedcluster example-hcp -p '{"spec":{"platform":{"aws":{"zone":"us-east-1b"}}}}'

# ✅ Right (declarative)
# Edit Git manifest, commit, push
# Argo syncs → HyperShift reconciles
```

**Benefit:** Reproducible, auditable, safer

### 4. **Eventual Consistency**

Argo continuously reconciles:

```
Git State ←→ Argo Reconciliation ←→ Cluster State
  (every   (polls every 3 min or    (Kubernetes
   push)    webhook trigger)         applies)
```

**Benefit:** Auto-remediation, drift detection

### 5. **Change Control**

Every change requires approval:

```
Developer commits to branch
        ↓
GitHub PR created
        ↓
Review + approval required
        ↓
Merge to main
        ↓
Argo detects change
        ↓
Cluster updated
```

**Benefit:** Prevents accidents, enforces process

### 6. **Observability**

Everything is visible and queryable:

```bash
# See cluster status
kubectl get hostedcluster
kubectl get nodes --kubeconfig=hcp-kubeconfig

# See Argo sync status
argocd app get gitops-hcp-scenario1

# See cluster in ACM
oc login hub-cluster
oc get managedcluster
```

**Benefit:** Easy troubleshooting, clear status

---

## Integration with Existing Systems

### With Your Git Workflow

1. **Branch strategy:** Each environment (dev, staging, prod) in separate branch
2. **PR reviews:** Every cluster change requires approval
3. **CI/CD:** Validate YAML before merge
4. **Secrets:** Manage via sealed-secrets or external-secrets

### With Your Monitoring

Argo CD integrates with:
- **Prometheus:** Track sync duration, success rate
- **Grafana:** Dashboard of application health
- **Alerting:** Notify when sync fails

### With Your Incident Response

- **Rollback:** `git revert` previous commit
- **Investigation:** Git history shows what changed
- **Post-mortems:** Full audit trail of cluster changes

---

## The GitOps-to-ACM Handoff

This section explains the transition from HyperShift provisioning to ACM management.

### When HyperShift Completes

HyperShift's responsibility ends when:
- ✅ Hosted control plane pods are Running
- ✅ API server is responding
- ✅ Worker nodes are being provisioned
- ✅ HostedCluster status: Available=True

At this point, the cluster is functional but not yet managed by ACM.

### What ACM Takes Over

Once the control plane is Available, ACM automatically begins management through auto-import:

1. **Discovery:** hypershift-addon-agent (ACM controller) detects the available control plane
2. **Registration:** hypershift-addon-agent creates a ManagedCluster resource with Hosted annotations
3. **Agent Deployment:** cluster-import-controller deploys klusterlet to the Hub cluster
4. **Connection:** hypershift-addon-agent creates external-managed-kubeconfig for the klusterlet
5. **Registration:** Klusterlet uses the kubeconfig to connect to the hosted cluster and register with ACM Hub
6. **Management:** Full ACM features enabled (policies, observability, multi-cluster operations)

### The Auto-Import Timeline

| Time | Component | Action |
|------|-----------|--------|
| T+0 | GitOps | HostedCluster created via Argo |
| T+5 | HyperShift | Control plane Available |
| T+8 | ACM | hypershift-addon-agent creates ManagedCluster |
| T+10 | ACM | cluster-import-controller deploys klusterlet to Hub |
| T+12 | ACM | Klusterlet registers hosted cluster |
| T+15 | ACM | ManagedCluster Available, management enabled |

### Why This Matters

The handoff from HyperShift to ACM enables:
- **Policy Enforcement:** Configuration compliance and governance
- **Observability:** Unified dashboards and monitoring
- **Multi-Cluster Operations:** Coordinated application deployment
- **Lifecycle Management:** Centralized cluster operations

### Learn More

For complete details on the auto-import process, see:
- **[04-acm-integration-overview.md](./04-acm-integration-overview.md)** - High-level ACM integration overview
- **[05-auto-import-deep-dive.md](./05-auto-import-deep-dive.md)** - Minute-by-minute auto-import timeline and troubleshooting

---

## Next Steps

- [02-getting-started.md](./02-getting-started.md) - Set up your first cluster
- [03-provisioning.md](./03-provisioning.md) - Deep dive into Scenario 1
- [05-auto-import-deep-dive.md](./05-auto-import-deep-dive.md) - Auto-import patterns

---

**Last Updated:** April 10, 2026  
**Status:** Complete
