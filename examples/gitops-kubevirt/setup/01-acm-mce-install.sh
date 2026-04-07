#!/bin/bash
set -euo pipefail

echo "=== Installing ACM/MCE with HyperShift Addon ==="

# Create namespace for MCE
echo "Creating multicluster-engine namespace..."
oc create namespace multicluster-engine --dry-run=client -o yaml | oc apply -f -

# Create OperatorGroup
echo "Creating OperatorGroup..."
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: multicluster-engine-operatorgroup
  namespace: multicluster-engine
spec:
  targetNamespaces:
  - multicluster-engine
EOF

# Subscribe to MCE operator
echo "Creating Subscription for MCE operator..."
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: multicluster-engine
  namespace: multicluster-engine
spec:
  channel: stable-2.7
  name: multicluster-engine
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF

# Wait for operator to be ready
echo "Waiting for MCE operator to be ready..."
timeout 300 bash -c 'until oc get csv -n multicluster-engine | grep -q "multicluster-engine.*Succeeded"; do sleep 10; done'

echo "MCE operator installed successfully!"

# Create MultiClusterEngine instance with HyperShift addon
echo "Creating MultiClusterEngine instance..."
cat <<EOF | oc apply -f -
apiVersion: multicluster.openshift.io/v1
kind: MultiClusterEngine
metadata:
  name: multiclusterengine
spec:
  targetNamespace: multicluster-engine
  overrides:
    components:
    - name: hypershift
      enabled: true
    - name: hypershift-local-hosting
      enabled: true
EOF

# Wait for MCE to be ready
echo "Waiting for MultiClusterEngine to be available..."
timeout 600 bash -c 'until oc get mce multiclusterengine -o jsonpath="{.status.phase}" 2>/dev/null | grep -q "Available"; do echo "Waiting..."; sleep 15; done'

echo "MultiClusterEngine is available!"

# Verify HyperShift operator is running
echo "Verifying HyperShift operator..."
oc get deployment -n hypershift operator
oc wait --for=condition=Available --timeout=300s deployment/operator -n hypershift

# Create clusters namespace
echo "Creating clusters namespace..."
oc create namespace clusters --dry-run=client -o yaml | oc apply -f -

echo ""
echo "=== ACM/MCE Installation Complete ==="
echo ""
echo "Installed components:"
echo "  - MCE Operator: $(oc get csv -n multicluster-engine -o jsonpath='{.items[?(@.metadata.name~"multicluster-engine")].metadata.name}')"
echo "  - HyperShift Operator: $(oc get deployment -n hypershift operator -o jsonpath='{.metadata.name}')"
echo ""
echo "Next step: Run 02-argo-install.sh"
