#!/bin/bash

#
# check-upgrade-status.sh
#
# Monitor the progress of a HostedCluster and NodePool upgrade
# Shows real-time status with color-coded output
#
# Usage:
#   ./check-upgrade-status.sh [cluster-name] [namespace]
#
# Examples:
#   ./check-upgrade-status.sh
#   ./check-upgrade-status.sh example-hcp clusters
#   ./check-upgrade-status.sh my-cluster my-clusters
#
# Output:
#   - Control plane version and status
#   - NodePool versions and progress
#   - Individual node status
#   - Overall upgrade progress
#

set -euo pipefail

# Configuration
CLUSTER_NAME="${1:-example-hcp}"
NAMESPACE="${2:-clusters}"
POLL_INTERVAL="${POLL_INTERVAL:-5}"
MAX_ITERATIONS="${MAX_ITERATIONS:-0}"  # 0 = infinite

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Helper functions
log_header() {
    echo -e "${CYAN}=== $1 ===${NC}"
}

log_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

log_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

log_error() {
    echo -e "${RED}✗ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

log_progress() {
    echo -e "${MAGENTA}→ $1${NC}"
}

# Check if a resource exists
resource_exists() {
    local api_version=$1
    local kind=$2
    local namespace=$3
    local name=$4

    if oc get "$kind" -n "$namespace" "$name" &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# Get a specific field from a resource
get_field() {
    local kind=$1
    local namespace=$2
    local name=$3
    local field=$4

    oc get "$kind" -n "$namespace" "$name" -o jsonpath="$field" 2>/dev/null || echo "N/A"
}

# Get condition status
get_condition() {
    local kind=$1
    local namespace=$2
    local name=$3
    local condition=$4

    oc get "$kind" -n "$namespace" "$name" -o jsonpath="{.status.conditions[?(@.type==\"$condition\")]}" 2>/dev/null || echo ""
}

# Format time
format_time() {
    local seconds=$1
    if [ "$seconds" -ge 3600 ]; then
        echo "$((seconds / 3600))h $((seconds % 3600 / 60))m"
    elif [ "$seconds" -ge 60 ]; then
        echo "$((seconds / 60))m $((seconds % 60))s"
    else
        echo "${seconds}s"
    fi
}

# Main monitoring function
check_control_plane() {
    log_header "Control Plane Status"

    if ! resource_exists "hypershift.openshift.io" "hostedcluster" "$NAMESPACE" "$CLUSTER_NAME"; then
        log_error "HostedCluster $CLUSTER_NAME not found in namespace $NAMESPACE"
        return 1
    fi

    local version=$(get_field hostedcluster "$NAMESPACE" "$CLUSTER_NAME" ".spec.release.image")
    local available=$(get_field hostedcluster "$NAMESPACE" "$CLUSTER_NAME" ".status.conditions[?(@.type==\"Available\")].status")
    local progressing=$(get_field hostedcluster "$NAMESPACE" "$CLUSTER_NAME" ".status.conditions[?(@.type==\"Progressing\")].status")

    log_info "Image: $version"

    if [ "$available" = "True" ]; then
        log_success "Available: True"
    elif [ "$available" = "False" ]; then
        log_error "Available: False"
    else
        log_warning "Available: $available"
    fi

    if [ "$progressing" = "True" ]; then
        log_progress "Progressing: True (upgrade in progress)"
    else
        log_success "Progressing: False (idle)"
    fi

    # Get last transition time
    local last_update=$(get_field hostedcluster "$NAMESPACE" "$CLUSTER_NAME" ".status.lastVersion.lastTransitionTime")
    if [ "$last_update" != "N/A" ]; then
        log_info "Last updated: $last_update"
    fi

    echo ""
}

check_nodepool() {
    log_header "NodePool Status"

    local nodepools=$(oc get nodepool -n "$NAMESPACE" -o jsonpath="{.items[*].metadata.name}" 2>/dev/null)

    if [ -z "$nodepools" ]; then
        log_error "No NodePools found in namespace $NAMESPACE"
        return 1
    fi

    for nodepool in $nodepools; do
        log_info "NodePool: $nodepool"

        local spec_replicas=$(get_field nodepool "$NAMESPACE" "$nodepool" ".spec.replicas")
        local ready=$(get_field nodepool "$NAMESPACE" "$nodepool" ".status.ready")
        local updated=$(get_field nodepool "$NAMESPACE" "$nodepool" ".status.updated")
        local available=$(get_field nodepool "$NAMESPACE" "$nodepool" ".status.available")
        local progressing=$(get_field nodepool "$NAMESPACE" "$nodepool" ".status.conditions[?(@.type==\"Progressing\")].status")

        local image=$(get_field nodepool "$NAMESPACE" "$nodepool" ".spec.release.image")
        log_info "  Image: $image"

        if [ "$spec_replicas" != "N/A" ]; then
            log_info "  Desired replicas: $spec_replicas"
        fi

        log_info "  Ready: $ready"
        log_info "  Updated: $updated"
        log_info "  Available: $available"

        if [ "$progressing" = "True" ]; then
            log_progress "  Progressing: True (upgrade in progress)"
        else
            log_success "  Progressing: False (idle)"
        fi

        # Check individual node status
        echo ""
        log_info "  Node Status:"

        local nodes=$(oc get nodes -o jsonpath="{.items[*].metadata.name}" 2>/dev/null)
        local node_count=0
        local ready_count=0

        for node in $nodes; do
            ((node_count++))
            local node_ready=$(oc get node "$node" -o jsonpath="{.status.conditions[?(@.type==\"Ready\")].status}" 2>/dev/null)
            local node_version=$(oc get node "$node" -o jsonpath="{.status.nodeInfo.kubeletVersion}" 2>/dev/null)

            if [ "$node_ready" = "True" ]; then
                log_success "    $node: Ready ($node_version)"
                ((ready_count++))
            else
                log_error "    $node: NotReady ($node_version)"
            fi
        done

        if [ "$node_count" -gt 0 ]; then
            log_info "  Overall: $ready_count/$node_count nodes ready"
        fi

        echo ""
    done
}

check_cluster_version() {
    log_header "ClusterVersion Status (Hosted Cluster)"

    # Get kubeconfig for hosted cluster
    local kubeconfig_secret="$CLUSTER_NAME-admin-kubeconfig"

    if ! oc get secret -n "$NAMESPACE" "$kubeconfig_secret" &> /dev/null; then
        log_warning "Kubeconfig secret not found: $kubeconfig_secret"
        log_info "Cannot check hosted cluster operators at this time"
        echo ""
        return
    fi

    # Extract kubeconfig
    local kubeconfig_file="/tmp/$CLUSTER_NAME-kubeconfig"
    oc get secret -n "$NAMESPACE" "$kubeconfig_secret" \
        -o jsonpath='{.data.kubeconfig}' | base64 -d > "$kubeconfig_file" 2>/dev/null || true

    if [ ! -f "$kubeconfig_file" ] || [ ! -s "$kubeconfig_file" ]; then
        log_warning "Could not extract kubeconfig for hosted cluster"
        echo ""
        return
    fi

    # Check cluster version in hosted cluster
    export KUBECONFIG="$kubeconfig_file"

    local cv_version=$(oc get clusterversion -o jsonpath="{.items[0].status.desired.version}" 2>/dev/null || echo "N/A")
    local cv_available=$(oc get clusterversion -o jsonpath="{.items[0].status.conditions[?(@.type==\"Available\")].status}" 2>/dev/null || echo "N/A")
    local cv_progressing=$(oc get clusterversion -o jsonpath="{.items[0].status.conditions[?(@.type==\"Progressing\")].status}" 2>/dev/null || echo "N/A")

    log_info "Desired version: $cv_version"

    if [ "$cv_available" = "True" ]; then
        log_success "Available: True"
    else
        log_warning "Available: $cv_available"
    fi

    if [ "$cv_progressing" = "True" ]; then
        log_progress "Progressing: True (cluster operator updates in progress)"
    else
        log_success "Progressing: False (all operators updated)"
    fi

    # Unset KUBECONFIG to avoid affecting subsequent operations
    unset KUBECONFIG

    echo ""
}

check_events() {
    log_header "Recent Events"

    local events=$(oc get events -n "$NAMESPACE" --sort-by='.lastTimestamp' -o custom-columns=LASTSEEN:.lastTimestamp,TYPE:.type,REASON:.reason,MESSAGE:.message 2>/dev/null | tail -5)

    if [ -z "$events" ]; then
        log_info "No recent events"
    else
        echo "$events"
    fi

    echo ""
}

# Main loop
iteration=0
while true; do
    clear
    log_header "Upgrade Status Monitor - $CLUSTER_NAME"
    log_info "Last check: $(date '+%Y-%m-%d %H:%M:%S')"
    log_info "Poll interval: ${POLL_INTERVAL}s"

    echo ""

    check_control_plane
    check_nodepool
    check_cluster_version
    check_events

    # Check termination condition
    if [ "$MAX_ITERATIONS" -gt 0 ]; then
        ((iteration++))
        if [ "$iteration" -ge "$MAX_ITERATIONS" ]; then
            log_info "Reached maximum iterations ($MAX_ITERATIONS)"
            break
        fi
    fi

    # Wait before next poll
    log_info "Waiting ${POLL_INTERVAL}s before next check... (Ctrl+C to exit)"
    sleep "$POLL_INTERVAL"
done
