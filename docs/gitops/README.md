# GitOps HCP Implementation Guide

## What is This?

This comprehensive guide covers **GitOps-driven management of HyperShift Hosted Control Planes (HCPs)** with **Red Hat Advanced Cluster Management (ACM)**. Rather than managing clusters imperatively, you declare desired state in Git and let Argo CD synchronize your infrastructure automatically.

**Key Concept:** Your Git repository becomes the single source of truth for cluster lifecycle, from initial provisioning through scaling, upgrades, and day-2 operations.

### Who Should Read This?

- **Platform Engineers** managing HyperShift environments
- **Site Reliability Engineers** implementing cluster-as-code workflows
- **Infrastructure Teams** adopting GitOps practices
- **Operators** seeking to reduce manual cluster management

### What You'll Learn

This guide progresses through four real-world scenarios:

1. **Scenario 1: Provisioning** - Create a complete HCP with GitOps
2. **Scenario 2: Auto-Import Patterns** - How ACM discovers and manages HCPs
3. **Scenario 3: Scaling** - Horizontal, vertical, and multi-pool operations
4. **Scenario 4: Upgrades** - Progressive version updates via Git

---

## Prerequisites

### Required Knowledge

- OpenShift/Kubernetes fundamentals (pods, deployments, namespaces)
- Git and GitHub/GitLab workflows
- Basic YAML and Kubernetes manifests
- Container concepts and image registries

### Required Infrastructure

| Component | Minimum Version | Role |
|-----------|-----------------|------|
| OpenShift Hub Cluster | 4.14+ | Hosts HyperShift operator & Argo CD |
| HyperShift Operator | 4.14+ | Manages hosted control planes |
| Argo CD | 2.6+ | Synchronizes Git to cluster |
| ACM/MCE | 2.5+ | Manages cluster lifecycle & auto-import |
| Git Repository | Any | Source of truth (GitHub, GitLab, etc.) |

### Required Credentials

- SSH key for Git repository access (or token-based auth)
- Pull secret for OpenShift images (registry.redhat.io)
- Cloud provider credentials (AWS, Azure, etc. - for worker nodes)
- kubeconfig with admin access to hub cluster

### Recommended Tools

- `kubectl` (1.27+) for cluster inspection
- `oc` (OpenShift CLI) for cluster management
- `git` for version control operations
- `argocd` CLI for Argo CD operations (optional)

### Time Investment

- **Full walkthrough of all 4 scenarios:** 3-4 hours
- **Scenario 1 only (quick start):** 30-40 minutes
- **Each scenario independently:** 45-90 minutes

---

## Quick Start: Run Scenario 1 in 5 Minutes

Want to see GitOps HCP in action immediately? Here's the fastest path:

### 1. Get the Examples

```bash
git clone https://github.com/stolostron/hypershift-addon-operator.git
cd hypershift-addon-operator/examples/gitops-kubevirt/01-provision
```

### 2. Customize for Your Environment

```bash
# Edit base/hostedcluster.yaml
# - Change baseDomain to your domain
# - Set namespace if needed
# - Update pull-secret reference

# Edit base/nodepool.yaml  
# - Adjust replicas if needed
# - Update image if needed

# Edit argo-application.yaml
# - Change repoURL to your fork
# - Set target revision (main, release-4.19, etc.)
```

### 3. Apply the Argo Application

```bash
# Creates the GitOps sync definition
kubectl apply -f argo-application.yaml

# Watch Argo sync the infrastructure
argocd app wait gitops-hcp-scenario1
```

### 4. Monitor Cluster Creation

```bash
# In a new terminal, watch cluster come up
watch -n 5 kubectl get hostedcluster -A

# When Progressing=True, check node readiness
kubectl get nodes -n <hosted-cluster-namespace>
```

### 5. Verify Success

```bash
# Should show 2 running nodes
kubectl get nodes -A

# Should show successful kubeconfig secret
kubectl get secret -n <namespace> admin-kubeconfig

# Optional: Access the HCP
oc get secret -n <namespace> admin-kubeconfig -o json | \
  jq -r '.data.kubeconfig' | base64 -d > hcp-kubeconfig
kubectl --kubeconfig=hcp-kubeconfig get nodes
```

**Total time: 5-10 minutes** (varies by infrastructure readiness)

---

## Complete Documentation Navigation

This guide is organized into two parts:

### PART 1: Provisioning HCPs with GitOps

**Start here if you're new to GitOps HCP provisioning:**

- **[01-architecture.md](./01-architecture.md)** - Complete system architecture
  - How Git, Argo, HyperShift, and ACM work together
  - Responsibility matrix (who creates/manages what)
  - GitOps-to-ACM handoff explained
  - When and why to use different patterns

- **[02-getting-started.md](./02-getting-started.md)** - First-time setup
  - Infrastructure preparation checklist
  - Account and credential setup
  - First deployment walkthrough
  - Expected timelines and troubleshooting

- **[03-provisioning.md](./03-provisioning.md)** - Provisioning Deep Dive
  - Complete provisioning process
  - Customization points and best practices
  - Verification procedures
  - Common issues and fixes

### PART 2: Managing HCPs with ACM

**After provisioning, explore how ACM manages your hosted clusters:**

- **[04-acm-integration-overview.md](./04-acm-integration-overview.md)** - ACM Integration Overview
  - What ACM provides for hosted clusters
  - How auto-import works (high-level)
  - Key ACM resources explained
  - Roadmap to Part 2 scenarios

- **[05-auto-import-deep-dive.md](./05-auto-import-deep-dive.md)** - Auto-Import Deep Dive
  - Minute-by-minute import timeline
  - Three import patterns (Full-Auto, Disabled, Hybrid)
  - Complete YAML examples with annotations
  - Verification procedures
  - Troubleshooting import failures

- **[06-managing-scale-operations.md](./06-managing-scale-operations.md)** - Scaling with ACM
  - Horizontal and vertical scaling
  - How ManagedClusterInfo updates during scaling
  - ACM console observability
  - Troubleshooting scale issues

- **[07-managing-upgrades.md](./07-managing-upgrades.md)** - Upgrades with ACM
  - Control plane and node upgrades
  - Version tracking in ACM
  - Policy enforcement during upgrades
  - Rollback procedures

- **[08-troubleshooting.md](./08-troubleshooting.md)** - Troubleshooting Guide
  - Part A: GitOps & Argo issues
  - Part B: ACM auto-import issues (detailed diagnostics)
  - Part C: Day-2 ACM issues
  - Quick reference for common issues

---

## FAQ

### General Questions

**Q: Do I need to understand Argo CD in detail?**  
A: No. This guide assumes basic Argo knowledge (apply manifests, sync). The examples show common patterns without requiring Argo expertise.

**Q: Can I use this with my own Git repository?**  
A: Yes! The examples reference GitHub, but they work with any Git provider. Update the `repoURL` in the Argo Application manifest.

**Q: Is this only for KubeVirt?**  
A: The examples use KubeVirt, but the GitOps patterns apply to AWS, Azure, or any HyperShift-supported platform. Only platform-specific fields change.

**Q: How does this compare to cluster-api or traditional IaC?**  
A: GitOps adds declarative, Git-based management with Argo sync. Cluster-api is also supported; this shows the Argo workflow specifically.

**Q: Can I mix GitOps and imperative commands?**  
A: Yes, but carefully. The guide shows patterns to manage drift and maintain Git as source-of-truth.

---

### Scenario Selection

**Q: Do I need to do Scenario 1 first?**  
A: Yes. Scenario 1 provisions the base cluster. Scenarios 2-4 build on it.

**Q: Can I skip Scenario 2?**  
A: Yes, but understanding auto-import helps with cluster lifecycle. It's the shortest read.

**Q: Which scenario matches my use case?**  
A: See [Scenario Selection Guide](./05-auto-import-deep-dive.md#scenario-selection) in the auto-import doc.

**Q: How long does each scenario take?**  
A: See timelines in each guide's Quick Start section. Typically:
- Scenario 1: 30-40 min
- Scenario 2: 20-30 min (conceptual)
- Scenario 3: 45-90 min
- Scenario 4: 60-120 min

---

### Technical Questions

**Q: What happens if Git and cluster diverge?**  
A: This is "configuration drift." Argo can:
- **Sync:** Apply Git state to cluster
- **Skip:** Respect cluster state (manual changes)
- **Prune:** Delete cluster objects not in Git

See [03-provisioning.md](./03-provisioning.md#drift-management) for details.

**Q: How does ACM auto-import work?**  
A: When HCP is created, HyperShift deploys the klusterlet (ACM agent). ACM detects it and creates ManagedCluster. See [01-architecture.md](./01-architecture.md#auto-import-lifecycle) for the full timeline.

**Q: Can I have multiple HCPs in one Argo Application?**  
A: Yes! Use Kustomize or Helm overlays. See [03-provisioning.md](./03-provisioning.md#multi-cluster-patterns) for examples.

**Q: What's the relationship between HyperShift operator and Argo CD?**  
A: HyperShift operator manages HCP lifecycle (create, update, delete). Argo syncs manifests to the cluster. They complement each other—Argo ensures manifests match Git, HyperShift ensures HCP matches manifests.

**Q: How do I handle secrets (ssh keys, pull secrets) in Git?**  
A: Never commit secrets to Git. Pre-create them in the cluster, then reference them in manifests. See [02-getting-started.md](./02-getting-started.md#secrets-setup) for details.

---

### Troubleshooting Questions

**Q: My cluster is stuck in "Progressing" status.**  
A: See [08-troubleshooting.md](./08-troubleshooting.md#hostedcluster-stuck-progressing) for diagnosis steps.

**Q: Nodes won't become Ready.**  
A: Check worker node VM provisioning. See [08-troubleshooting.md](./08-troubleshooting.md#nodes-not-ready) for debug commands.

**Q: ManagedCluster never appears in ACM.**  
A: The klusterlet might not be deployed. See [08-troubleshooting.md](./08-troubleshooting.md#managedcluster-not-created) for diagnostics.

**Q: Argo shows "OutOfSync" even though I didn't change anything.**  
A: Likely drift from cluster operations. See [03-provisioning.md](./03-provisioning.md#drift-management) and [08-troubleshooting.md](./08-troubleshooting.md#argo-out-of-sync) for resolution.

**Q: Where do I look for logs?**  
A: Depends on the issue. See [08-troubleshooting.md](./08-troubleshooting.md#log-locations) for a guide by component.

---

### Production Questions

**Q: Is this production-ready?**  
A: The examples are production-grade. They use current APIs, best practices, and safety checks. Always test on non-prod first.

**Q: How do I implement change control?**  
A: Use Git branches and pull requests. Every cluster change requires Git approval. See [03-provisioning.md](./03-provisioning.md#change-control) for the workflow.

**Q: How do I handle multi-region deployments?**  
A: Each region uses its own Argo Application pointing to region-specific paths in Git. See [03-provisioning.md](./03-provisioning.md#multi-region-patterns).

**Q: What's the disaster recovery story?**  
A: Git is your backup. Cluster state is reproducible from Git. See [08-troubleshooting.md](./08-troubleshooting.md#disaster-recovery) for procedures.

**Q: How do I monitor cluster health?**  
A: Use HyperShift status conditions + ACM monitoring. See [08-troubleshooting.md](./08-troubleshooting.md#observability) for commands and tools.

---

### ACM Integration Questions

**Q: What's the difference between HyperShift and ACM?**  
A: HyperShift provisions the hosted cluster (creates control plane, provisions nodes). ACM manages the cluster after creation (policies, observability, multi-cluster operations). They work together automatically through auto-import.

**Q: Do I need to manually import my hosted cluster to ACM?**  
A: No. ACM automatically detects and imports hosted clusters within 10-15 minutes. This is called "auto-import" and requires no manual intervention.

**Q: What if auto-import fails?**  
A: See [05-auto-import-deep-dive.md](./05-auto-import-deep-dive.md) Section 5 for detailed troubleshooting steps. Common issues include missing annotations, controller problems, or network connectivity.

**Q: Can I disable ACM management?**  
A: Yes. See the "Disabled" pattern in [05-auto-import-deep-dive.md](./05-auto-import-deep-dive.md). Simply delete the ManagedCluster resource and the cluster continues running without ACM management.

**Q: What annotations are critical for hosted cluster import?**  
A: Two annotations are required:
- `import.open-cluster-management.io/klusterlet-deploy-mode: "Hosted"` - Tells ACM to deploy klusterlet on Hub
- `cluster.open-cluster-management.io/createdVia: "hypershift"` - Indicates HyperShift-managed cluster

**Q: Where does the klusterlet run for hosted clusters?**  
A: Unlike standalone clusters, the klusterlet for hosted clusters runs on the Hub cluster (not on the hosted cluster itself). It connects remotely using the external-managed-kubeconfig secret.

**Q: How do I verify auto-import succeeded?**  
A: Check ManagedCluster status: `kubectl get managedcluster <name> -o jsonpath='{.status.conditions[?(@.type=="ManagedClusterConditionAvailable")].status}'` should return `True`.

**Q: What's the external-managed-kubeconfig secret?**  
A: It's a kubeconfig created by hypershift-addon-agent in the klusterlet namespace. It points to the hosted cluster's API server and allows the klusterlet to register the cluster with ACM.

---

## Key Concepts

### GitOps

**Definition:** Infrastructure and configuration defined in Git, synchronized to clusters automatically.

**In this guide:** Argo CD watches your Git repository and applies changes to your clusters. Cluster state should match Git state.

**Benefit:** Audit trail, version history, rollback capability, code review for infrastructure.

### Hosted Control Planes

**Definition:** OpenShift control plane running on a hub cluster, worker nodes provided separately.

**In this guide:** HyperShift operator manages HCPs on a hub cluster. ACM provides cluster management.

**Benefit:** Simplified cluster provisioning, efficient resource use, centralized management.

### Auto-Import

**Definition:** Automatic discovery and management of HCPs by ACM.

**In this guide:** When HCP is created, ACM automatically creates a ManagedCluster. This enables policy, governance, and cluster operations.

**Benefit:** No manual import steps, automatic cluster lifecycle management.

---

## File Organization

All examples live in `examples/gitops-kubevirt/`:

```
examples/gitops-kubevirt/
├── 01-provision/              # Scenario 1: Provisioning
├── 02-auto-import/            # Scenario 2: Auto-Import Patterns
├── 03-scaling/                # Scenario 3: Scaling
├── 04-upgrades/               # Scenario 4: Upgrades
├── setup/                     # Infrastructure setup scripts
└── PHASE3-IMPLEMENTATION-SUMMARY.md
```

Each scenario includes:
- `README.md` - Complete guide
- `VALIDATION.md` - Step-by-step verification
- `argo-application.yaml` - GitOps manifest
- `base/` - Foundation configuration
- `operations/` or `upgrades/` - Progressive changes

---

## Next Steps

1. **New to GitOps HCP?** Start with [01-architecture.md](./01-architecture.md)
2. **Setting up your first cluster?** Follow [02-getting-started.md](./02-getting-started.md)
3. **Ready to provision?** Go to [03-provisioning.md](./03-provisioning.md)
4. **Troubleshooting?** Jump to [08-troubleshooting.md](./08-troubleshooting.md)

---

## Support

- **Examples:** See `examples/gitops-kubevirt/` for working configurations
- **Upstream HyperShift:** [hypershift-docs.netlify.app](https://hypershift-docs.netlify.app/)
- **ACM Documentation:** [Red Hat Advanced Cluster Management](https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes/)
- **Argo CD:** [Argo CD Documentation](https://argo-cd.readthedocs.io/)

---

## Document Versions

| Date | Version | Changes |
|------|---------|---------|
| 2026-04-10 | 1.1 | Restructured into two-part guide emphasizing ACM integration |
| 2026-04-02 | 1.0 | Initial publication of Phase 4 documentation |

---

**Last Updated:** April 10, 2026  
**Status:** Complete  
**Ready for:** Development, Testing, Production
