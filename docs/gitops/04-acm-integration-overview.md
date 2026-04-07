# ACM Integration Overview

## What This Document Covers

After HyperShift provisions a hosted cluster, ACM automatically takes over management through a process called "auto-import." This document explains:

- What ACM provides for hosted clusters
- How the integration works (high-level flow)
- Key ACM resources and their purpose
- Roadmap to Part 2 scenarios

**For detailed auto-import mechanics**, see [05-auto-import-deep-dive.md](./05-auto-import-deep-dive.md).

---

## ACM's Role in HCP Lifecycle

### What ACM Provides

Once a hosted cluster is imported, ACM provides:

#### 1. Cluster Discovery (Auto-Import)

- **Automatic detection** when hosted clusters become available
- **Registration without manual intervention** - no kubectl apply needed
- **Visibility in ACM console** - see all clusters in one place
- **Inventory management** - track cluster versions, capacity, health

#### 2. Policy & Governance

- **Configuration policies** - enforce cluster configurations
- **Compliance scanning** - audit against security standards
- **Remediation** - auto-fix policy violations
- **Audit logging** - track all policy changes

#### 3. Observability & Monitoring

- **Cluster health dashboards** - unified view of all clusters
- **Metrics collection** - CPU, memory, pod counts
- **Alerting integration** - notify on cluster issues
- **Search** - find resources across all managed clusters

#### 4. Multi-Cluster Management

- **Unified cluster view** - manage 100s of clusters from one hub
- **Application deployment** - deploy apps across cluster sets
- **Placement** - intelligent workload distribution
- **Cluster sets** - group clusters for operations

---

## The Integration Flow

```
┌────────────────────────────────────────────────────────────────────────────┐
│                          Hub Cluster                                        │
│                                                                             │
│  ┌──────────────┐         ┌──────────────┐                                 │
│  │   Argo CD    │ applies │  HyperShift  │                                 │
│  │              │────────>│   Operator   │                                 │
│  └──────────────┘         └──────┬───────┘                                 │
│                                  │                                          │
│                                  │ creates                                  │
│                                  ▼                                          │
│                        ┌──────────────────┐                                 │
│                        │ Hosted Control   │                                 │
│                        │ Plane Pods       │                                 │
│                        │ (hosted-* ns)    │                                 │
│                        └────────┬─────────┘                                 │
│                                 │                                           │
│                                 │ becomes Available                         │
│                                 ▼                                           │
│                        ┌──────────────────┐                                 │
│                        │ hypershift-      │                                 │
│     ┌──────────────────│ addon-agent      │                                 │
│     │ detects HC ready │ (ACM controller) │                                 │
│     │                  └────────┬─────────┘                                 │
│     │                           │                                           │
│     │ creates                   │ creates                                   │
│     ▼                           ▼                                           │
│  ┌──────────────────┐  ┌──────────────────┐                                │
│  │ ManagedCluster   │  │ external-managed-│                                │
│  │ Resource         │  │ kubeconfig       │                                │
│  └────────┬─────────┘  │ (secret)         │                                │
│           │            └────────┬─────────┘                                 │
│           │                     │                                           │
│           │ triggers            │                                           │
│           ▼                     │                                           │
│  ┌──────────────────┐           │                                           │
│  │ cluster-import-  │           │                                           │
│  │ controller       │───────────┤                                           │
│  │ (ACM controller) │  deploys  │                                           │
│  └────────┬─────────┘           │                                           │
│           │                     │                                           │
│           │ creates             │                                           │
│           ▼                     │                                           │
│  ┌──────────────────┐           │                                           │
│  │ Klusterlet       │◄──────────┘                                           │
│  │ (klusterlet-* ns)│  uses kubeconfig                                      │
│  └────────┬─────────┘                                                       │
│           │                                                                 │
└───────────┼─────────────────────────────────────────────────────────────────┘
            │
            │ connects using external-managed-kubeconfig
            │ registers hosted cluster
            ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                      Hosted Cluster (Workers)                               │
│                                                                             │
│  ┌──────────────┐         ┌──────────────┐         ┌──────────────┐        │
│  │  Worker-0    │         │  Worker-1    │         │  Worker-N    │        │
│  └──────────────┘         └──────────────┘         └──────────────┘        │
└────────────────────────────────────────────────────────────────────────────┘
```

### Step-by-Step Process

#### Step 1: HyperShift Creates Hosted Control Plane

- GitOps (Argo CD) applies HostedCluster and NodePool manifests
- HyperShift operator creates control plane pods on the Hub
- Control plane becomes Available (API server responding)
- HostedCluster status: Available=True

**Timeline:** T+0 to T+5 minutes

#### Step 2: hypershift-addon-agent Detects Ready Cluster

- ACM controller monitors HostedClusters for Available status
- Detects the new hosted cluster is ready
- Creates ManagedCluster resource with critical annotations:
  - `import.open-cluster-management.io/klusterlet-deploy-mode: "Hosted"`
  - `cluster.open-cluster-management.io/createdVia: "hypershift"`

**Timeline:** T+5 to T+8 minutes

#### Step 3: cluster-import-controller Deploys Klusterlet

- Detects ManagedCluster with `klusterlet-deploy-mode: "Hosted"`
- Creates klusterlet-<name> namespace on Hub cluster
- Deploys klusterlet pods to Hub (NOT to hosted cluster)
- Klusterlet runs on Hub, manages remotely

**Timeline:** T+8 to T+10 minutes

#### Step 4: hypershift-addon-agent Creates Kubeconfig

- Creates external-managed-kubeconfig secret in klusterlet namespace
- Secret contains kubeconfig for hosted cluster API server
- Kubeconfig allows klusterlet to connect to the hosted cluster

**Timeline:** T+10 to T+12 minutes

#### Step 5: Klusterlet Registers Cluster

- Klusterlet pod reads external-managed-kubeconfig
- Connects to hosted cluster API using the kubeconfig
- Registers hosted cluster with ACM Hub
- ManagedCluster status updates: Joined=True, then Available=True

**Timeline:** T+12 to T+15 minutes

#### Step 6: Management Enabled

- ManagedClusterInfo gets populated with cluster details
- ACM add-ons deployed (if KlusterletAddonConfig configured)
- Cluster appears in ACM console
- Policies and observability enabled

**Timeline:** T+15+ minutes

---

## Key ACM Resources

### ManagedCluster

**Represents the hosted cluster in ACM**

```yaml
apiVersion: cluster.open-cluster-management.io/v1
kind: ManagedCluster
metadata:
  name: example-hcp
  annotations:
    import.open-cluster-management.io/klusterlet-deploy-mode: "Hosted"
    cluster.open-cluster-management.io/createdVia: "hypershift"
  labels:
    cloud: auto
    vendor: auto
spec:
  hubAcceptsClient: true
```

**Key annotations:**
- `klusterlet-deploy-mode: "Hosted"` → Klusterlet runs on Hub, not on hosted cluster
- `createdVia: "hypershift"` → Indicates HyperShift-managed cluster

**Key labels:**
- `vendor: auto` → Auto-imported (vs manual import)
- `cloud: auto` → Cloud provider auto-detected

**Example:** [examples/gitops-kubevirt/01-provision/acm/managedcluster-example.yaml](../../examples/gitops-kubevirt/01-provision/acm/managedcluster-example.yaml)

### KlusterletAddonConfig

**Configures ACM add-ons for the cluster**

Enables:
- **Application manager** - Deploy apps via ACM
- **Policy controller** - Enforce configuration policies
- **Search collector** - Make resources searchable
- **Certificate policy controller** - Certificate compliance
- **IAM policy controller** - RBAC compliance

**Example:** [examples/gitops-kubevirt/01-provision/acm/klusterletaddonconfig-example.yaml](../../examples/gitops-kubevirt/01-provision/acm/klusterletaddonconfig-example.yaml)

### ManagedClusterInfo

**Populated by klusterlet with cluster details**

Contains:
- Kubernetes/OpenShift version
- Node inventory with capacity and status
- Distribution info (OCP version, available updates)
- Console and API URLs

**Example:** [examples/gitops-kubevirt/01-provision/acm/managedclusterinfo-example.yaml](../../examples/gitops-kubevirt/01-provision/acm/managedclusterinfo-example.yaml)

---

## What Makes Hosted Clusters Different

### Klusterlet Location

**Standalone clusters:**
- Klusterlet runs ON the managed cluster
- Direct in-cluster access to resources

**Hosted clusters:**
- Klusterlet runs on the Hub cluster
- Connects remotely via external-managed-kubeconfig
- More efficient (no agent overhead on hosted cluster)

### Deploy Mode Annotation

The `import.open-cluster-management.io/klusterlet-deploy-mode: "Hosted"` annotation is **critical**:

- **Present** → cluster-import-controller deploys klusterlet to Hub
- **Missing or "Default"** → Import fails (klusterlet tries to deploy to hosted cluster)

This annotation is set automatically by hypershift-addon-agent.

### External-Managed-Kubeconfig Secret

**Purpose:** Allows Hub-based klusterlet to manage the hosted cluster

**Created by:** hypershift-addon-agent  
**Location:** klusterlet-<name> namespace on Hub  
**Contains:** Kubeconfig for hosted cluster API server  

**Different from:**
- `admin-kubeconfig` - For end users to access hosted cluster
- `kubeconfig` - Internal HyperShift secret

---

## Roadmap to Part 2 Scenarios

Now that you understand the high-level integration, explore detailed scenarios:

### Scenario 1: Auto-Import Deep Dive

**[05-auto-import-deep-dive.md](./05-auto-import-deep-dive.md)**

- Minute-by-minute import timeline
- Three patterns: Full-Auto, Disabled, Hybrid
- Complete YAML examples with field explanations
- Verification procedures
- Detailed troubleshooting (4+ common issues)

### Scenario 2: Scaling with ACM

**[06-managing-scale-operations.md](./06-managing-scale-operations.md)**

- How scaling looks from ACM perspective
- ManagedClusterInfo updates during scaling
- ACM console observability
- Troubleshooting scale issues

### Scenario 3: Upgrades with ACM

**[07-managing-upgrades.md](./07-managing-upgrades.md)**

- Version tracking in ManagedCluster
- Upgrade visibility in ACM console
- Policy enforcement during upgrades
- Rollback procedures

### Scenario 4: Troubleshooting

**[08-troubleshooting.md](./08-troubleshooting.md)**

- Part A: GitOps & Argo issues
- Part B: ACM auto-import issues (comprehensive)
- Part C: Day-2 ACM issues
- Quick reference

---

## Next Steps

**Continue to [05-auto-import-deep-dive.md](./05-auto-import-deep-dive.md)** for operator-level details on the auto-import process, including:

- Observable state at each minute of the timeline
- kubectl verification commands for each phase
- Complete troubleshooting procedures
- Pattern decision tree

---

**Last Updated:** April 10, 2026  
**Status:** Complete
