#!/bin/bash
set -euo pipefail

echo "=== Configuring KubeVirt for HyperShift ==="

# Check if KubeVirt is already installed
if oc get namespace openshift-cnv 2>/dev/null; then
  echo "OpenShift Virtualization (KubeVirt) is already installed"
else
  echo "OpenShift Virtualization is not installed. Installing..."

  # Create namespace
  oc create namespace openshift-cnv --dry-run=client -o yaml | oc apply -f -

  # Create OperatorGroup
  cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: kubevirt-hyperconverged-group
  namespace: openshift-cnv
spec:
  targetNamespaces:
  - openshift-cnv
EOF

  # Subscribe to OpenShift Virtualization
  cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: hco-operatorhub
  namespace: openshift-cnv
spec:
  channel: stable
  name: kubevirt-hyperconverged
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF

  # Wait for operator
  echo "Waiting for OpenShift Virtualization operator..."
  timeout 300 bash -c 'until oc get csv -n openshift-cnv | grep -q "kubevirt-hyperconverged-operator.*Succeeded"; do sleep 10; done'

  # Create HyperConverged instance
  cat <<EOF | oc apply -f -
apiVersion: hco.kubevirt.io/v1beta1
kind: HyperConverged
metadata:
  name: kubevirt-hyperconverged
  namespace: openshift-cnv
spec: {}
EOF

  echo "Waiting for HyperConverged to be ready..."
  timeout 600 bash -c 'until oc get hyperconverged -n openshift-cnv kubevirt-hyperconverged -o jsonpath="{.status.conditions[?(@.type==\"Available\")].status}" 2>/dev/null | grep -q "True"; do echo "Waiting..."; sleep 15; done'
fi

# Verify compute resources
echo ""
echo "Checking compute resources..."
TOTAL_CPU=$(oc get nodes -o jsonpath='{range .items[*]}{.status.capacity.cpu}{"\n"}{end}' | awk '{s+=$1} END {print s}')
TOTAL_MEMORY_KB=$(oc get nodes -o jsonpath='{range .items[*]}{.status.capacity.memory}{"\n"}{end}' | sed 's/Ki$//' | awk '{s+=$1} END {print s}')
TOTAL_MEMORY_GB=$((TOTAL_MEMORY_KB / 1024 / 1024))

echo "Total CPUs: ${TOTAL_CPU}"
echo "Total Memory: ${TOTAL_MEMORY_GB} GB"

if [ "$TOTAL_CPU" -lt 32 ]; then
  echo "WARNING: Less than 32 CPUs available. You may not have enough resources for HCP."
fi

if [ "$TOTAL_MEMORY_GB" -lt 64 ]; then
  echo "WARNING: Less than 64 GB memory available. You may not have enough resources for HCP."
fi

# Check for storage class
echo ""
echo "Checking for storage classes..."
DEFAULT_SC=$(oc get sc -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}')

if [ -z "$DEFAULT_SC" ]; then
  echo "WARNING: No default storage class found. You may need to create one."
  echo "Available storage classes:"
  oc get sc
else
  echo "Default storage class: ${DEFAULT_SC}"
fi

echo ""
echo "=== KubeVirt Setup Complete ==="
echo ""
echo "Next step: Run 04-secrets-template.yaml to create secrets"
