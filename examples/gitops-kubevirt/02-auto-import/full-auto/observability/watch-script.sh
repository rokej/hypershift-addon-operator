#!/bin/bash
set -euo pipefail

# Auto-Import Watch Script for Full-Auto Pattern
# This script monitors the auto-import process and displays key events
# Usage: ./watch-script.sh [cluster-name]

CLUSTER_NAME="${1:-example-hcp-auto}"
NAMESPACE="clusters"
POLL_INTERVAL=5
TIMEOUT=600

echo "=========================================="
echo "Auto-Import Watch Script"
echo "=========================================="
echo "Cluster: ${CLUSTER_NAME}"
echo "Namespace: ${NAMESPACE}"
echo "Poll Interval: ${POLL_INTERVAL}s"
echo "Timeout: ${TIMEOUT}s"
echo ""
echo "This script monitors:"
echo "  1. HostedCluster creation and readiness"
echo "  2. ManagedCluster auto-creation"
echo "  3. Control plane availability"
echo "  4. NodePool readiness"
echo ""
echo "=========================================="
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print status
print_status() {
  local component=$1
  local status=$2
  local color=$3

  printf "${color}[%-30s]${NC} %s\n" "$component" "$status"
}

# Function to check HostedCluster status
check_hostedcluster() {
  local hc=$(oc get hostedcluster -n "${NAMESPACE}" "${CLUSTER_NAME}" 2>/dev/null || echo "")

  if [ -z "$hc" ]; then
    print_status "HostedCluster" "Not created" "$RED"
    return 1
  fi

  local available=$(oc get hostedcluster -n "${NAMESPACE}" "${CLUSTER_NAME}" -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "Unknown")
  local version=$(oc get hostedcluster -n "${NAMESPACE}" "${CLUSTER_NAME}" -o jsonpath='{.spec.release.image}' | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' || echo "Unknown")

  if [ "$available" = "True" ]; then
    print_status "HostedCluster" "Available (v${version})" "$GREEN"
  elif [ "$available" = "False" ]; then
    print_status "HostedCluster" "Not Available (v${version})" "$RED"
  else
    print_status "HostedCluster" "Progressing (v${version})" "$YELLOW"
  fi
}

# Function to check ManagedCluster auto-import
check_managedcluster() {
  local mc=$(oc get managedcluster "${CLUSTER_NAME}" 2>/dev/null || echo "")

  if [ -z "$mc" ]; then
    print_status "ManagedCluster" "Not auto-created yet" "$YELLOW"
    return 1
  fi

  local available=$(oc get managedcluster "${CLUSTER_NAME}" -o jsonpath='{.status.conditions[?(@.type=="ManagedClusterConditionAvailable")].status}' 2>/dev/null || echo "Unknown")

  if [ "$available" = "True" ]; then
    print_status "ManagedCluster" "Available (AUTO-IMPORTED)" "$GREEN"
  elif [ "$available" = "False" ]; then
    print_status "ManagedCluster" "Not Available" "$RED"
  else
    print_status "ManagedCluster" "Joining" "$YELLOW"
  fi
}

# Function to check control plane namespace
check_control_plane() {
  local cp_ns="clusters-${CLUSTER_NAME}"
  local ns=$(oc get namespace "${cp_ns}" 2>/dev/null || echo "")

  if [ -z "$ns" ]; then
    print_status "Control Plane NS" "Not created" "$RED"
    return 1
  fi

  local running=$(oc get pods -n "${cp_ns}" --field-selector=status.phase=Running 2>/dev/null | tail -n +2 | wc -l || echo "0")
  local total=$(oc get pods -n "${cp_ns}" 2>/dev/null | tail -n +2 | wc -l || echo "0")

  print_status "Control Plane Pods" "${running}/${total} Running" "$BLUE"
}

# Function to check NodePool status
check_nodepool() {
  local np="${CLUSTER_NAME}-workers"
  local nodepool=$(oc get nodepool -n "${NAMESPACE}" "${np}" 2>/dev/null || echo "")

  if [ -z "$nodepool" ]; then
    print_status "NodePool" "Not created" "$RED"
    return 1
  fi

  local replicas=$(oc get nodepool -n "${NAMESPACE}" "${np}" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "?")
  local ready=$(oc get nodepool -n "${NAMESPACE}" "${np}" -o jsonpath='{.status.ready}' 2>/dev/null || echo "0")

  if [ "$ready" = "$replicas" ]; then
    print_status "NodePool" "${ready}/${replicas} Ready" "$GREEN"
  else
    print_status "NodePool" "${ready}/${replicas} Ready" "$YELLOW"
  fi
}

# Function to check klusterlet addon
check_klusterlet() {
  local mw=$(oc get manifestwork -n "${CLUSTER_NAME}" -l app=klusterlet 2>/dev/null | tail -n +2 | wc -l || echo "0")

  if [ "$mw" -gt 0 ]; then
    print_status "Klusterlet" "Deployed" "$GREEN"
  else
    print_status "Klusterlet" "Not deployed" "$YELLOW"
  fi
}

# Main watch loop
start_time=$(date +%s)

while true; do
  current_time=$(date +%s)
  elapsed=$((current_time - start_time))

  # Clear screen and show header
  clear

  echo "=========================================="
  echo "Auto-Import Watch - $(date '+%Y-%m-%d %H:%M:%S')"
  echo "Elapsed: ${elapsed}s / Timeout: ${TIMEOUT}s"
  echo "=========================================="
  echo ""

  # Check all components
  check_hostedcluster
  check_managedcluster
  check_control_plane
  check_nodepool
  check_klusterlet

  echo ""
  echo "=========================================="

  # Check if we've reached timeout
  if [ $elapsed -ge $TIMEOUT ]; then
    print_status "Status" "Timeout reached" "$RED"
    echo ""
    echo "Deployment took longer than expected."
    echo "Check cluster status manually:"
    echo ""
    echo "  oc get hostedcluster -n ${NAMESPACE} ${CLUSTER_NAME}"
    echo "  oc get managedcluster ${CLUSTER_NAME}"
    echo "  oc logs -n ${NAMESPACE} deployment/hypershift-operator"
    echo ""
    exit 1
  fi

  # Check if deployment is complete
  if check_hostedcluster &>/dev/null && check_managedcluster &>/dev/null && check_nodepool &>/dev/null; then
    local hc_available=$(oc get hostedcluster -n "${NAMESPACE}" "${CLUSTER_NAME}" -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "")
    local mc_available=$(oc get managedcluster "${CLUSTER_NAME}" -o jsonpath='{.status.conditions[?(@.type=="ManagedClusterConditionAvailable")].status}' 2>/dev/null || echo "")
    local np_ready=$(oc get nodepool -n "${NAMESPACE}" "${CLUSTER_NAME}-workers" -o jsonpath='{.status.ready}' 2>/dev/null || echo "0")
    local np_replicas=$(oc get nodepool -n "${NAMESPACE}" "${CLUSTER_NAME}-workers" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")

    if [ "$hc_available" = "True" ] && [ "$mc_available" = "True" ] && [ "$np_ready" = "$np_replicas" ]; then
      echo ""
      print_status "Status" "COMPLETE!" "$GREEN"
      echo ""
      echo "Auto-import completed successfully!"
      echo ""
      echo "Next steps:"
      echo "  1. Get kubeconfig:"
      echo "     oc get secret -n ${NAMESPACE} ${CLUSTER_NAME}-admin-kubeconfig -o jsonpath='{.data.kubeconfig}' | base64 -d > /tmp/${CLUSTER_NAME}-kubeconfig"
      echo ""
      echo "  2. Access hosted cluster:"
      echo "     export KUBECONFIG=/tmp/${CLUSTER_NAME}-kubeconfig"
      echo "     oc get nodes"
      echo ""
      exit 0
    fi
  fi

  # Wait before next poll
  sleep "${POLL_INTERVAL}"
done
