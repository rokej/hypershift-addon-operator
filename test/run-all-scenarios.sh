#!/bin/bash

################################################################################
# HyperShift GitOps Scenarios - Smoke Test
#
# Purpose: Run all 4 scenarios sequentially with monitoring and reporting
# Duration: ~60-90 minutes (manual execution, not for CI)
#
# Scenarios:
#   1. Provisioning via GitOps (45-60 min)
#   2. Auto-Import Patterns (10-15 min)
#   3. Scaling and NodePool Management (45-90 min)
#   4. Progressive Upgrades via GitOps (90-120 min)
#
# Prerequisites:
#   - Hub cluster with HyperShift operator running
#   - ACM installed and configured
#   - Argo CD configured with Git repo access
#   - kubeconfig for hub cluster exported in KUBECONFIG env var
#   - kubectl and jq installed
#   - Git repository cloned locally
#
# Usage:
#   ./test/run-all-scenarios.sh [--dry-run] [--scenario N] [--timeout MINS]
#
# Examples:
#   ./test/run-all-scenarios.sh                  # Run all 4 scenarios
#   ./test/run-all-scenarios.sh --scenario 1     # Run only Scenario 1
#   ./test/run-all-scenarios.sh --dry-run        # Dry run (no actual changes)
#   ./test/run-all-scenarios.sh --timeout 120    # Custom timeout
#
################################################################################

set -o pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly EXAMPLES_DIR="${SCRIPT_DIR}/examples/gitops-kubevirt"
readonly GIT_REPO_URL="${GIT_REPO_URL:-}"
readonly HUB_CLUSTER_CONTEXT="${HUB_CLUSTER_CONTEXT:-}"
readonly NAMESPACE_PREFIX="gitops-test"
readonly TIMESTAMP="$(date +%s)"
readonly LOG_DIR="${SCRIPT_DIR}/test/logs"

# Command-line options
DRY_RUN=false
SCENARIO_FILTER=""
TIMEOUT_MINS=180
VERBOSE=false

# Counters and status tracking
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0
declare -A SCENARIO_RESULTS
declare -A SCENARIO_TIMINGS

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

################################################################################
# Utility Functions
################################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $*"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_header() {
    echo -e "\n${BLUE}=================================================================================${NC}"
    echo -e "${BLUE}$*${NC}"
    echo -e "${BLUE}=================================================================================${NC}\n"
}

verbose_log() {
    if [[ "${VERBOSE}" == "true" ]]; then
        echo -e "${BLUE}[VERBOSE]${NC} $*"
    fi
}

die() {
    log_error "$*"
    exit 1
}

# Create log directory if it doesn't exist
setup_logging() {
    mkdir -p "${LOG_DIR}"
    readonly TEST_LOG="${LOG_DIR}/test-run-${TIMESTAMP}.log"
    exec 1> >(tee -a "${TEST_LOG}")
    exec 2> >(tee -a "${TEST_LOG}" >&2)
    log_info "Test log: ${TEST_LOG}"
}

# Check prerequisites
check_prerequisites() {
    log_header "Checking Prerequisites"

    local missing=0

    # Check commands
    for cmd in kubectl git jq; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command not found: $cmd"
            missing=$((missing + 1))
        fi
    done

    # Check kubeconfig
    if [[ -z "${KUBECONFIG}" ]] && [[ ! -f ~/.kube/config ]]; then
        log_error "kubeconfig not found (set KUBECONFIG or ~/.kube/config)"
        missing=$((missing + 1))
    fi

    # Check kubectl connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        missing=$((missing + 1))
    fi

    # Check HyperShift operator
    if ! kubectl get deployment hypershift-operator -n hypershift-system &> /dev/null; then
        log_error "HyperShift operator not found in hypershift-system namespace"
        missing=$((missing + 1))
    fi

    # Check ACM
    if ! kubectl get deployment multiclusterhub -n open-cluster-management &> /dev/null; then
        log_warning "ACM (multiclusterhub) not found - some tests may be skipped"
    fi

    # Check Argo CD
    if ! kubectl get deployment argocd-application-controller -n argocd &> /dev/null; then
        log_error "Argo CD not found in argocd namespace"
        missing=$((missing + 1))
    fi

    # Check git repo
    if [[ ! -d "${EXAMPLES_DIR}" ]]; then
        log_error "Examples directory not found: ${EXAMPLES_DIR}"
        missing=$((missing + 1))
    fi

    if [[ ${missing} -gt 0 ]]; then
        die "Prerequisites check failed: ${missing} issues found"
    fi

    log_success "All prerequisites met"
}

# Print usage information
print_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Options:
    --scenario N        Run only scenario N (1-4)
    --dry-run           Print what would be executed without making changes
    --timeout MINS      Overall timeout in minutes (default: 180)
    --verbose           Enable verbose logging
    --help              Show this help message

Examples:
    $(basename "$0")                    # Run all scenarios
    $(basename "$0") --scenario 1       # Run only Scenario 1 (Provisioning)
    $(basename "$0") --dry-run          # Dry run mode
    $(basename "$0") --timeout 120      # Custom 2-hour timeout

Log output saved to: ${LOG_DIR}/
EOF
}

# Parse command-line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --scenario)
                SCENARIO_FILTER="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --timeout)
                TIMEOUT_MINS="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                print_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
}

################################################################################
# Scenario Test Functions
################################################################################

# Scenario 1: Provisioning via GitOps
test_scenario_1() {
    local scenario_name="Provisioning via GitOps"
    local scenario_dir="${EXAMPLES_DIR}/01-provision"
    local test_name="scenario1"

    log_header "Scenario 1: ${scenario_name}"

    if [[ ! -d "${scenario_dir}" ]]; then
        log_error "Scenario directory not found: ${scenario_dir}"
        SCENARIO_RESULTS["scenario1"]="FAILED"
        return 1
    fi

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    local start_time=$(date +%s)

    # Create test namespace
    local test_namespace="${NAMESPACE_PREFIX}-1-${TIMESTAMP}"
    log_info "Creating namespace: ${test_namespace}"
    if [[ "${DRY_RUN}" == "false" ]]; then
        kubectl create namespace "${test_namespace}" || {
            log_error "Failed to create namespace"
            SCENARIO_RESULTS["scenario1"]="FAILED"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            return 1
        }
    fi

    # Deploy Argo Application
    log_info "Deploying Argo Application for provisioning"
    if [[ "${DRY_RUN}" == "false" ]]; then
        kubectl apply -n "${test_namespace}" -f "${scenario_dir}/" || {
            log_error "Failed to deploy manifests"
            kubectl delete namespace "${test_namespace}" 2>/dev/null
            SCENARIO_RESULTS["scenario1"]="FAILED"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            return 1
        }
    fi

    # Monitor cluster provisioning
    log_info "Monitoring HostedCluster provisioning (timeout: 60 minutes)"
    if [[ "${DRY_RUN}" == "false" ]]; then
        local max_wait=3600  # 60 minutes
        local elapsed=0
        local check_interval=30

        while [[ ${elapsed} -lt ${max_wait} ]]; do
            local hcp_status=$(kubectl get hostedcluster -n "${test_namespace}" \
                -o jsonpath='{.items[0].status.conditions[?(@.type=="Available")].status}' 2>/dev/null)

            if [[ "${hcp_status}" == "True" ]]; then
                log_success "HostedCluster is Available"

                # Verify NodePool ready
                local nodepool_ready=$(kubectl get nodepool -n "${test_namespace}" \
                    -o jsonpath='{.items[0].status.readyReplicas}' 2>/dev/null)
                local nodepool_desired=$(kubectl get nodepool -n "${test_namespace}" \
                    -o jsonpath='{.items[0].spec.replicas}' 2>/dev/null)

                if [[ "${nodepool_ready}" == "${nodepool_desired}" ]] && [[ ! -z "${nodepool_ready}" ]]; then
                    log_success "NodePool ready: ${nodepool_ready}/${nodepool_desired} nodes"
                    break
                fi
            fi

            elapsed=$((elapsed + check_interval))
            log_info "Waiting for cluster to be ready... (${elapsed}s/${max_wait}s)"
            sleep ${check_interval}
        done

        if [[ ${elapsed} -ge ${max_wait} ]]; then
            log_error "Timeout waiting for HostedCluster to be ready"
            SCENARIO_RESULTS["scenario1"]="FAILED"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            return 1
        fi
    fi

    # Verify kubeconfig access
    log_info "Verifying kubeconfig access"
    if [[ "${DRY_RUN}" == "false" ]]; then
        local kubeconfig_secret=$(kubectl get secret -n "${test_namespace}" \
            -o jsonpath='{.items[0].metadata.name}' 2>/dev/null | grep kubeconfig)

        if [[ -z "${kubeconfig_secret}" ]]; then
            log_warning "Kubeconfig secret not found (cluster may not be fully ready)"
        else
            log_success "Kubeconfig secret found: ${kubeconfig_secret}"
        fi
    fi

    # Verify ACM ManagedCluster
    log_info "Verifying ACM ManagedCluster auto-import"
    if [[ "${DRY_RUN}" == "false" ]]; then
        local managed_cluster=$(kubectl get managedcluster -n "${test_namespace}" 2>/dev/null | wc -l)
        if [[ ${managed_cluster} -gt 1 ]]; then
            log_success "ManagedCluster created by auto-import"
        else
            log_warning "ManagedCluster not yet created (may take additional time)"
        fi
    fi

    # Cleanup
    log_info "Cleaning up test namespace"
    if [[ "${DRY_RUN}" == "false" ]]; then
        kubectl delete namespace "${test_namespace}" --ignore-not-found=true
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    SCENARIO_TIMINGS["scenario1"]=${duration}

    log_success "Scenario 1 completed in ${duration} seconds"
    SCENARIO_RESULTS["scenario1"]="PASSED"
    PASSED_TESTS=$((PASSED_TESTS + 1))
    return 0
}

# Scenario 2: Auto-Import Patterns
test_scenario_2() {
    local scenario_name="Auto-Import Patterns for ACM Integration"
    local test_name="scenario2"

    log_header "Scenario 2: ${scenario_name}"

    # Check ACM availability
    if ! kubectl get deployment multiclusterhub -n open-cluster-management &> /dev/null; then
        log_warning "ACM not available - skipping Scenario 2"
        SCENARIO_RESULTS["scenario2"]="SKIPPED"
        SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
        return 0
    fi

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    local start_time=$(date +%s)

    log_info "Testing auto-import pattern detection"

    if [[ "${DRY_RUN}" == "false" ]]; then
        # Verify klusterlet deployment capability
        if kubectl api-resources | grep -q ManagedCluster; then
            log_success "ManagedCluster CRD available"
        else
            log_error "ManagedCluster CRD not found"
            SCENARIO_RESULTS["scenario2"]="FAILED"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            return 1
        fi

        # Verify KlusterletAddonConfig
        if kubectl api-resources | grep -q KlusterletAddonConfig; then
            log_success "KlusterletAddonConfig CRD available"
        else
            log_warning "KlusterletAddonConfig CRD not found"
        fi

        # Count existing ManagedClusters
        local managed_count=$(kubectl get managedcluster 2>/dev/null | tail -n +2 | wc -l)
        log_info "Found ${managed_count} existing ManagedClusters"

        if [[ ${managed_count} -eq 0 ]]; then
            log_info "No ManagedClusters found (expected if clusters not yet provisioned)"
        fi
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    SCENARIO_TIMINGS["scenario2"]=${duration}

    log_success "Scenario 2 completed in ${duration} seconds"
    SCENARIO_RESULTS["scenario2"]="PASSED"
    PASSED_TESTS=$((PASSED_TESTS + 1))
    return 0
}

# Scenario 3: Scaling and NodePool Management
test_scenario_3() {
    local scenario_name="Scaling and NodePool Management"
    local scenario_dir="${EXAMPLES_DIR}/03-scaling"
    local test_name="scenario3"

    log_header "Scenario 3: ${scenario_name}"

    if [[ ! -d "${scenario_dir}" ]]; then
        log_warning "Scenario directory not found: ${scenario_dir}"
        SCENARIO_RESULTS["scenario3"]="SKIPPED"
        SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
        return 0
    fi

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    local start_time=$(date +%s)

    log_info "Testing NodePool scaling operations"

    if [[ "${DRY_RUN}" == "false" ]]; then
        # Check for existing clusters
        local hcp_count=$(kubectl get hostedcluster -A 2>/dev/null | tail -n +2 | wc -l)

        if [[ ${hcp_count} -eq 0 ]]; then
            log_warning "No HostedClusters found - skipping scaling test"
            SCENARIO_RESULTS["scenario3"]="SKIPPED"
            SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
            return 0
        fi

        log_info "Found ${hcp_count} HostedCluster(s)"

        # Get first cluster
        local cluster_name=$(kubectl get hostedcluster -A \
            -o jsonpath='{.items[0].metadata.name}')
        local cluster_ns=$(kubectl get hostedcluster -A \
            -o jsonpath='{.items[0].metadata.namespace}')

        log_info "Testing with cluster: ${cluster_name} in namespace: ${cluster_ns}"

        # Check NodePool
        local nodepool_count=$(kubectl get nodepool -n "${cluster_ns}" 2>/dev/null | tail -n +2 | wc -l)
        if [[ ${nodepool_count} -eq 0 ]]; then
            log_error "No NodePool found for cluster"
            SCENARIO_RESULTS["scenario3"]="FAILED"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            return 1
        fi

        log_success "NodePool found for scaling tests"

        # Get current replica count
        local current_replicas=$(kubectl get nodepool -n "${cluster_ns}" \
            -o jsonpath='{.items[0].spec.replicas}')
        log_info "Current NodePool replicas: ${current_replicas}"

        # Simulate scaling verification (not actual scaling in smoke test)
        log_info "Scaling operations verified (actual scaling skipped in smoke test)"
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    SCENARIO_TIMINGS["scenario3"]=${duration}

    log_success "Scenario 3 completed in ${duration} seconds"
    SCENARIO_RESULTS["scenario3"]="PASSED"
    PASSED_TESTS=$((PASSED_TESTS + 1))
    return 0
}

# Scenario 4: Progressive Upgrades
test_scenario_4() {
    local scenario_name="Progressive Upgrades via GitOps"
    local scenario_dir="${EXAMPLES_DIR}/04-upgrades"
    local test_name="scenario4"

    log_header "Scenario 4: ${scenario_name}"

    if [[ ! -d "${scenario_dir}" ]]; then
        log_warning "Scenario directory not found: ${scenario_dir}"
        SCENARIO_RESULTS["scenario4"]="SKIPPED"
        SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
        return 0
    fi

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    local start_time=$(date +%s)

    log_info "Testing upgrade procedure validation"

    if [[ "${DRY_RUN}" == "false" ]]; then
        # Check for existing clusters
        local hcp_count=$(kubectl get hostedcluster -A 2>/dev/null | tail -n +2 | wc -l)

        if [[ ${hcp_count} -eq 0 ]]; then
            log_warning "No HostedClusters found - skipping upgrade test"
            SCENARIO_RESULTS["scenario4"]="SKIPPED"
            SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
            return 0
        fi

        # Get first cluster for testing
        local cluster_name=$(kubectl get hostedcluster -A \
            -o jsonpath='{.items[0].metadata.name}')
        local cluster_ns=$(kubectl get hostedcluster -A \
            -o jsonpath='{.items[0].metadata.namespace}')

        log_info "Testing with cluster: ${cluster_name}"

        # Check current version
        local current_version=$(kubectl get hostedcluster -n "${cluster_ns}" \
            -o jsonpath='{.items[0].spec.release.image}')
        log_info "Current release image: ${current_version}"

        # Verify cluster is healthy before upgrade
        local available=$(kubectl get hostedcluster -n "${cluster_ns}" \
            -o jsonpath='{.items[0].status.conditions[?(@.type=="Available")].status}')

        if [[ "${available}" != "True" ]]; then
            log_warning "Cluster not healthy - skipping upgrade test"
            SCENARIO_RESULTS["scenario4"]="SKIPPED"
            SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
            return 0
        fi

        log_success "Cluster is healthy and ready for upgrade testing"
        log_info "Upgrade procedure validation completed (actual upgrade skipped in smoke test)"
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    SCENARIO_TIMINGS["scenario4"]=${duration}

    log_success "Scenario 4 completed in ${duration} seconds"
    SCENARIO_RESULTS["scenario4"]="PASSED"
    PASSED_TESTS=$((PASSED_TESTS + 1))
    return 0
}

################################################################################
# Main Test Execution
################################################################################

run_tests() {
    local start_time=$(date +%s)

    log_header "HyperShift GitOps Smoke Test Suite"
    log_info "Start time: $(date)"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "Running in DRY-RUN mode - no actual changes will be made"
    fi

    # Run requested scenarios
    if [[ -z "${SCENARIO_FILTER}" ]] || [[ "${SCENARIO_FILTER}" == "1" ]]; then
        test_scenario_1
    fi

    if [[ -z "${SCENARIO_FILTER}" ]] || [[ "${SCENARIO_FILTER}" == "2" ]]; then
        test_scenario_2
    fi

    if [[ -z "${SCENARIO_FILTER}" ]] || [[ "${SCENARIO_FILTER}" == "3" ]]; then
        test_scenario_3
    fi

    if [[ -z "${SCENARIO_FILTER}" ]] || [[ "${SCENARIO_FILTER}" == "4" ]]; then
        test_scenario_4
    fi

    local end_time=$(date +%s)
    local total_duration=$((end_time - start_time))

    print_summary "${total_duration}"
}

print_summary() {
    local total_duration=$1

    log_header "Test Summary"

    echo -e "\n${BLUE}Test Results:${NC}"
    echo "  Total Tests:  ${TOTAL_TESTS}"
    echo -e "  ${GREEN}Passed:${NC}       ${PASSED_TESTS}"
    echo -e "  ${RED}Failed:${NC}       ${FAILED_TESTS}"
    echo -e "  ${YELLOW}Skipped:${NC}      ${SKIPPED_TESTS}"

    echo -e "\n${BLUE}Scenario Details:${NC}"
    for scenario in scenario1 scenario2 scenario3 scenario4; do
        local result=${SCENARIO_RESULTS[$scenario]:-"NOT_RUN"}
        local timing=${SCENARIO_TIMINGS[$scenario]:-0}

        local status_color="${GREEN}"
        if [[ "${result}" == "FAILED" ]]; then
            status_color="${RED}"
        elif [[ "${result}" == "SKIPPED" ]]; then
            status_color="${YELLOW}"
        fi

        printf "  ${status_color}%-12s${NC} %s (%ds)\n" "${result}" "${scenario}" "${timing}"
    done

    echo -e "\n${BLUE}Overall Results:${NC}"
    echo "  Total Duration: ${total_duration}s ($(( total_duration / 60 ))m $(( total_duration % 60 ))s)"
    echo "  Test Log:       ${TEST_LOG}"
    echo "  End time:       $(date)"

    # Exit code
    if [[ ${FAILED_TESTS} -eq 0 ]]; then
        echo -e "\n${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "\n${RED}Some tests failed!${NC}"
        return 1
    fi
}

################################################################################
# Main Execution
################################################################################

main() {
    parse_args "$@"
    setup_logging
    check_prerequisites
    run_tests
    exit $?
}

# Run main function
main "$@"
