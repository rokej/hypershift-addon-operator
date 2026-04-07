#!/bin/bash
set -euo pipefail

FAILED=0

echo "=== Verifying GitOps HCP Setup ==="
echo ""

# Function to check and report
check() {
  local name=$1
  local command=$2

  echo -n "Checking ${name}... "
  if eval "$command" &>/dev/null; then
    echo "✓ OK"
  else
    echo "✗ FAILED"
    ((FAILED++))
  fi
}

# Check MCE operator
check "MCE Operator" "oc get csv -n multicluster-engine | grep -q 'multicluster-engine.*Succeeded'"

# Check MCE instance
check "MultiClusterEngine Available" "oc get mce multiclusterengine -o jsonpath='{.status.phase}' | grep -q 'Available'"

# Check HyperShift operator
check "HyperShift Operator" "oc get deployment -n hypershift operator -o jsonpath='{.status.availableReplicas}' | grep -q '[1-9]'"

# Check OpenShift GitOps operator
check "OpenShift GitOps Operator" "oc get csv -n openshift-operators | grep -q 'openshift-gitops-operator.*Succeeded'"

# Check ArgoCD instance
check "ArgoCD Instance" "oc get argocd -n openshift-gitops openshift-gitops -o jsonpath='{.status.phase}' | grep -q 'Available'"

# Check KubeVirt
check "KubeVirt Operator" "oc get csv -n openshift-cnv | grep -q 'kubevirt-hyperconverged-operator.*Succeeded'"
check "HyperConverged Available" "oc get hyperconverged -n openshift-cnv kubevirt-hyperconverged -o jsonpath='{.status.conditions[?(@.type==\"Available\")].status}' | grep -q 'True'"

# Check clusters namespace
check "Clusters Namespace" "oc get namespace clusters"

# Check for secrets
echo ""
echo "Checking for required secrets in 'clusters' namespace:"
check "  pull-secret" "oc get secret -n clusters pull-secret"
check "  ssh-key" "oc get secret -n clusters ssh-key"

# Check RBAC
check "ArgoCD HyperShift RBAC" "oc get clusterrolebinding | grep -q argocd-hypershift-admin"

# Check storage
echo ""
echo "Storage configuration:"
DEFAULT_SC=$(oc get sc -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}' || echo "")
if [ -n "$DEFAULT_SC" ]; then
  echo "  Default StorageClass: ${DEFAULT_SC} ✓"
else
  echo "  Default StorageClass: NOT FOUND ✗"
  ((FAILED++))
fi

# Summary
echo ""
echo "==================================="
if [ $FAILED -eq 0 ]; then
  echo "✓ All checks passed!"
  echo "Your environment is ready for GitOps HCP examples."
  echo ""
  echo "Next step: Go to ../01-provision/ and follow the README"
  exit 0
else
  echo "✗ ${FAILED} check(s) failed"
  echo "Please review the failed items above and re-run the appropriate setup scripts."
  exit 1
fi
