#!/bin/bash
set -euo pipefail

echo "=== Installing OpenShift GitOps (Argo CD) ==="

# Subscribe to OpenShift GitOps operator
echo "Creating Subscription for OpenShift GitOps operator..."
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-gitops-operator
  namespace: openshift-operators
spec:
  channel: latest
  name: openshift-gitops-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF

# Wait for operator to be ready
echo "Waiting for OpenShift GitOps operator to be ready..."
timeout 300 bash -c 'until oc get csv -n openshift-operators | grep -q "openshift-gitops-operator.*Succeeded"; do sleep 10; done'

echo "OpenShift GitOps operator installed successfully!"

# Wait for default ArgoCD instance
echo "Waiting for default ArgoCD instance..."
timeout 300 bash -c 'until oc get argocd -n openshift-gitops openshift-gitops 2>/dev/null; do sleep 10; done'

# Configure RBAC for HyperShift resources
echo "Configuring RBAC for ArgoCD to manage HyperShift resources..."
cat <<EOF | oc apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: argocd-hypershift-admin
rules:
- apiGroups:
  - hypershift.openshift.io
  resources:
  - "*"
  verbs:
  - "*"
- apiGroups:
  - cluster.open-cluster-management.io
  resources:
  - "*"
  verbs:
  - "*"
- apiGroups:
  - agent.open-cluster-management.io
  resources:
  - "*"
  verbs:
  - "*"
EOF

# Bind the role to ArgoCD application controller
oc adm policy add-cluster-role-to-user argocd-hypershift-admin system:serviceaccount:openshift-gitops:openshift-gitops-argocd-application-controller

# Get Argo CD route
echo "Waiting for ArgoCD route..."
timeout 60 bash -c 'until oc get route -n openshift-gitops openshift-gitops-server 2>/dev/null; do sleep 5; done'

ARGOCD_ROUTE=$(oc get route -n openshift-gitops openshift-gitops-server -o jsonpath='{.spec.host}')
ARGOCD_PASSWORD=$(oc get secret -n openshift-gitops openshift-gitops-cluster -o jsonpath='{.data.admin\.password}' | base64 -d)

echo ""
echo "=== OpenShift GitOps Installation Complete ==="
echo ""
echo "Argo CD Console: https://${ARGOCD_ROUTE}"
echo "Username: admin"
echo "Password: ${ARGOCD_PASSWORD}"
echo ""
echo "To login with argocd CLI:"
echo "  argocd login ${ARGOCD_ROUTE} --username admin --password '${ARGOCD_PASSWORD}' --insecure"
echo ""
echo "Next step: Run 03-kubevirt-setup.sh"
