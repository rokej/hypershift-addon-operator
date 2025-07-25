package metrics

import "github.com/prometheus/client_golang/prometheus"

var TotalReconcileCount = prometheus.NewCounter(prometheus.CounterOpts{
	Name: "mce_hs_addon_total_reconcile_count",
	Help: "Total number of Hypershift addon agent's reconciliations",
})

var FailedReconcileCount = prometheus.NewCounter(prometheus.CounterOpts{
	Name: "mce_hs_addon_failed_reconcile_count",
	Help: "Number of Hypershift addon agent's failed reconciliations",
})

var ReconcileRequeueCount = prometheus.NewCounter(prometheus.CounterOpts{
	Name: "mce_hs_addon_reconcile_requeue_count",
	Help: "Number of Hypershift addon agent's requeued reconciliations",
})

var AddonAgentFailedToStartBool = prometheus.NewGauge(prometheus.GaugeOpts{
	Name: "mce_hs_addon_failed_to_start_bool",
	Help: "Hypershift addon agent failed to start true (1) or false (0)",
})

var InInstallationOrUpgradeBool = prometheus.NewGauge(prometheus.GaugeOpts{
	Name: "mce_hs_addon_install_in_progress_bool",
	Help: "Hypershift operator installation in progress true (1) or false (0)",
})

var InstallationOrUpgradeFailedCount = prometheus.NewGauge(prometheus.GaugeOpts{
	Name: "mce_hs_addon_install_failure_gauge",
	Help: "Hypershift operator installation failure gauge",
})

var InstallationFailningGaugeBool = prometheus.NewGauge(prometheus.GaugeOpts{
	Name: "mce_hs_addon_install_failing_gauge_bool",
	Help: "Hypershift operator installation is failing true (1) or false (0)",
})

var PlacementScoreFailureCount = prometheus.NewCounter(prometheus.CounterOpts{
	Name: "mce_hs_addon_placement_score_failure_count",
	Help: "Hypershift addon agent placement score sync failure count",
})

var PlacementClusterClaimsFailureCount = prometheus.NewCounterVec(
	prometheus.CounterOpts{
		Name: "mce_hs_addon_cluster_claims_failure_count",
		Help: "Hypershift addon agent cluster claims update failure count",
	},
	[]string{"cluster_claim_name"},
)

var KubeconfigSecretCopyTotalCount = prometheus.NewCounter(prometheus.CounterOpts{
	Name: "mce_hs_addon_kubeconfig_secret_copy_total_count",
	Help: "Hypershift addon agent external-managed-kubeconfig total create counter",
})

var KubeconfigSecretCopyFailureCount = prometheus.NewCounter(prometheus.CounterOpts{
	Name: "mce_hs_addon_kubeconfig_secret_copy_failure_count",
	Help: "Hypershift addon agent external-managed-kubeconfig create failure counter",
})

var HubResourceSyncFailureCount = prometheus.NewCounterVec(
	prometheus.CounterOpts{
		Name: "mce_hs_addon_hub_sync_failure_count",
		Help: "Hypershift addon agent hub resource sync failure counter",
	},
	[]string{"resource_kind"},
)

func init() {
	CollectorsForRegistration = append(CollectorsForRegistration,
		TotalReconcileCount,
		FailedReconcileCount,
		ReconcileRequeueCount,
		AddonAgentFailedToStartBool,
		InInstallationOrUpgradeBool,
		InstallationOrUpgradeFailedCount,
		InstallationFailningGaugeBool,
		PlacementScoreFailureCount,
		PlacementClusterClaimsFailureCount,
		KubeconfigSecretCopyTotalCount,
		KubeconfigSecretCopyFailureCount,
		HubResourceSyncFailureCount)
}
