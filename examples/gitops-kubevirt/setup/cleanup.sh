#!/bin/bash
set -euo pipefail

echo "=== GitOps HCP Setup Cleanup ==="
echo ""
echo "This will remove:"
echo "  - MultiClusterEngine instance"
echo "  - Secrets in clusters namespace"
echo "  - clusters namespace"
echo ""
echo "This will NOT remove:"
echo "  - MCE operator"
echo "  - OpenShift GitOps operator"
echo "  - KubeVirt operator"
echo ""
read -p "Continue? (yes/no): " -r
if [[ ! $REPLY =~ ^yes$ ]]; then
  echo "Cancelled."
  exit 0
fi

echo ""
echo "Starting cleanup..."

# Delete clusters namespace (includes secrets)
if oc get namespace clusters 2>/dev/null; then
  echo "Deleting clusters namespace..."
  oc delete namespace clusters --wait=false
fi

# Delete MultiClusterEngine instance
if oc get mce multiclusterengine 2>/dev/null; then
  echo "Deleting MultiClusterEngine instance..."
  oc delete mce multiclusterengine --wait=false
fi

# Delete ArgoCD HyperShift RBAC
if oc get clusterrole argocd-hypershift-admin 2>/dev/null; then
  echo "Deleting ArgoCD HyperShift RBAC..."
  oc delete clusterrole argocd-hypershift-admin
  oc delete clusterrolebinding argocd-hypershift-admin 2>/dev/null || true
fi

echo ""
echo "Cleanup initiated. Resources are being deleted in the background."
echo ""
echo "To remove operators (optional):"
echo "  1. MCE: oc delete subscription multicluster-engine -n multicluster-engine"
echo "  2. GitOps: oc delete subscription openshift-gitops-operator -n openshift-operators"
echo "  3. KubeVirt: oc delete subscription hco-operatorhub -n openshift-cnv"
