// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// ABI module for eclexiaiser — core types for energy budgets, carbon intensity,
// sustainability reporting, and Eclexia constraint generation.
//
// These types form the contract between manifest parsing, code instrumentation,
// and report generation. In the full ABI-FFI architecture, corresponding Idris2
// definitions in `src/abi/*.idr` would provide formal proofs of interface
// correctness, and Zig FFI in `ffi/zig/` would expose C-ABI bindings.

use serde::{Deserialize, Serialize};

/// Energy budget for a single function, expressed in millijoules (mJ).
///
/// An `EnergyBudget` constrains how much energy a single invocation of a
/// function is allowed to consume. Exceeding the budget triggers a warning
/// or error in the sustainability report.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct EnergyBudget {
    /// Maximum energy consumption per call, in millijoules.
    pub max_millijoules: f64,
}

impl EnergyBudget {
    /// Create a new energy budget with the given millijoule limit.
    ///
    /// # Panics
    /// Panics if `max_millijoules` is negative.
    pub fn new(max_millijoules: f64) -> Self {
        assert!(
            max_millijoules >= 0.0,
            "Energy budget cannot be negative: {max_millijoules}"
        );
        Self { max_millijoules }
    }

    /// Check whether a measured energy value exceeds this budget.
    pub fn is_exceeded_by(&self, measured_millijoules: f64) -> bool {
        measured_millijoules > self.max_millijoules
    }

    /// Calculate the percentage of budget used by a measurement.
    pub fn usage_percent(&self, measured_millijoules: f64) -> f64 {
        if self.max_millijoules == 0.0 {
            if measured_millijoules > 0.0 {
                return f64::INFINITY;
            }
            return 0.0;
        }
        (measured_millijoules / self.max_millijoules) * 100.0
    }
}

/// Carbon budget for a single function, expressed in milligrams of CO2 equivalent.
///
/// This constrains the carbon emissions attributable to a function call, computed
/// from energy consumption multiplied by grid carbon intensity.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CarbonBudget {
    /// Maximum CO2 emissions per call, in milligrams.
    pub max_mg_co2: f64,
}

impl CarbonBudget {
    /// Create a new carbon budget with the given mg CO2 limit.
    pub fn new(max_mg_co2: f64) -> Self {
        assert!(
            max_mg_co2 >= 0.0,
            "Carbon budget cannot be negative: {max_mg_co2}"
        );
        Self { max_mg_co2 }
    }

    /// Check whether a measured carbon value exceeds this budget.
    pub fn is_exceeded_by(&self, measured_mg_co2: f64) -> bool {
        measured_mg_co2 > self.max_mg_co2
    }
}

/// Carbon intensity provider — the source of grid carbon intensity data.
///
/// Eclexia supports multiple providers for real-time or static carbon intensity
/// values, enabling accurate carbon accounting per grid region.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum CarbonProvider {
    /// WattTime API — real-time marginal emissions data.
    Watttime,
    /// Electricity Maps API — real-time lifecycle emissions.
    ElectricityMaps,
    /// Static intensity value, useful for offline or testing scenarios.
    Static,
}

impl CarbonProvider {
    /// Return a human-readable display name for the provider.
    pub fn display_name(&self) -> &'static str {
        match self {
            CarbonProvider::Watttime => "WattTime",
            CarbonProvider::ElectricityMaps => "Electricity Maps",
            CarbonProvider::Static => "Static",
        }
    }
}

/// Carbon configuration section — provider, region, and static fallback.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CarbonConfig {
    /// Which carbon intensity provider to use.
    pub provider: CarbonProvider,
    /// Grid region code (e.g., "GB", "DE", "US-CAL-CISO").
    pub region: String,
    /// Static intensity in mg CO2 per kWh (used when provider is Static).
    #[serde(rename = "static-intensity", default)]
    pub static_intensity: f64,
}

impl CarbonConfig {
    /// Compute carbon emissions in mg CO2 from energy in millijoules.
    ///
    /// Uses the static intensity value. For real-time providers, the actual
    /// intensity would be fetched from the API at measurement time; this method
    /// serves as the fallback calculation.
    ///
    /// Formula: mg_co2 = (millijoules / 3_600_000) * (mg_co2_per_kwh)
    /// Because 1 kWh = 3,600,000,000 mJ, but intensity is in mg/kWh:
    /// mg_co2 = millijoules * intensity / 3_600_000_000
    pub fn estimate_carbon_mg(&self, millijoules: f64) -> f64 {
        millijoules * self.static_intensity / 3_600_000_000.0
    }
}

/// Report format for sustainability output.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ReportFormat {
    /// Plain text report, human-readable.
    Text,
    /// JSON report, machine-readable.
    Json,
    /// EU CSRD (Corporate Sustainability Reporting Directive) compliant format.
    Csrd,
}

/// Report configuration section.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ReportConfig {
    /// Output format for the sustainability report.
    pub format: ReportFormat,
    /// Whether to include actionable recommendations for reducing impact.
    #[serde(rename = "include-recommendations", default)]
    pub include_recommendations: bool,
}

/// A single function's energy/carbon budget configuration, as declared in the manifest.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FunctionBudget {
    /// Function name (fully qualified or short).
    pub name: String,
    /// Source file containing the function.
    pub source: String,
    /// Energy budget in millijoules per call (None = unbounded).
    #[serde(rename = "energy-budget-mj")]
    pub energy_budget_mj: Option<f64>,
    /// Carbon budget in mg CO2 per call (None = unbounded).
    #[serde(rename = "carbon-budget-mg")]
    pub carbon_budget_mg: Option<f64>,
}

impl FunctionBudget {
    /// Build an `EnergyBudget` from this function's config, if specified.
    pub fn energy_budget(&self) -> Option<EnergyBudget> {
        self.energy_budget_mj.map(EnergyBudget::new)
    }

    /// Build a `CarbonBudget` from this function's config, if specified.
    pub fn carbon_budget(&self) -> Option<CarbonBudget> {
        self.carbon_budget_mg.map(CarbonBudget::new)
    }
}

/// Compliance status for a single function measurement against its budget.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum ComplianceStatus {
    /// Within budget (usage <= 100%).
    Compliant,
    /// Approaching budget (usage > 80% but <= 100%).
    Warning,
    /// Over budget (usage > 100%).
    Exceeded,
    /// No budget was set, so compliance is not applicable.
    Unbounded,
}

impl ComplianceStatus {
    /// Determine compliance status from a budget usage percentage.
    pub fn from_usage_percent(percent: f64) -> Self {
        if percent > 100.0 {
            ComplianceStatus::Exceeded
        } else if percent > 80.0 {
            ComplianceStatus::Warning
        } else {
            ComplianceStatus::Compliant
        }
    }

    /// Return a short label for display purposes.
    pub fn label(&self) -> &'static str {
        match self {
            ComplianceStatus::Compliant => "COMPLIANT",
            ComplianceStatus::Warning => "WARNING",
            ComplianceStatus::Exceeded => "EXCEEDED",
            ComplianceStatus::Unbounded => "UNBOUNDED",
        }
    }
}

/// A measurement result for a single function, including energy, carbon, and compliance.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FunctionMeasurement {
    /// Name of the measured function.
    pub function_name: String,
    /// Measured energy in millijoules.
    pub measured_energy_mj: f64,
    /// Estimated carbon in mg CO2.
    pub estimated_carbon_mg: f64,
    /// Energy budget compliance.
    pub energy_compliance: ComplianceStatus,
    /// Carbon budget compliance.
    pub carbon_compliance: ComplianceStatus,
}

/// A complete sustainability report for a project.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SustainabilityReport {
    /// Project name.
    pub project_name: String,
    /// Grid region used for carbon calculations.
    pub region: String,
    /// Carbon intensity provider name.
    pub provider: String,
    /// Per-function measurement results.
    pub measurements: Vec<FunctionMeasurement>,
    /// Total energy across all measured functions, in millijoules.
    pub total_energy_mj: f64,
    /// Total estimated carbon across all measured functions, in mg CO2.
    pub total_carbon_mg: f64,
    /// Overall compliance: true if all functions are compliant or warning.
    pub all_compliant: bool,
    /// Actionable recommendations (empty if not requested).
    pub recommendations: Vec<String>,
}

impl SustainabilityReport {
    /// Return the count of functions that exceeded their energy budget.
    pub fn energy_violations(&self) -> usize {
        self.measurements
            .iter()
            .filter(|m| m.energy_compliance == ComplianceStatus::Exceeded)
            .count()
    }

    /// Return the count of functions that exceeded their carbon budget.
    pub fn carbon_violations(&self) -> usize {
        self.measurements
            .iter()
            .filter(|m| m.carbon_compliance == ComplianceStatus::Exceeded)
            .count()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_energy_budget_compliance() {
        let budget = EnergyBudget::new(50.0);
        assert!(!budget.is_exceeded_by(49.9));
        assert!(!budget.is_exceeded_by(50.0));
        assert!(budget.is_exceeded_by(50.1));
        assert!((budget.usage_percent(25.0) - 50.0).abs() < f64::EPSILON);
    }

    #[test]
    fn test_carbon_budget_compliance() {
        let budget = CarbonBudget::new(10.0);
        assert!(!budget.is_exceeded_by(10.0));
        assert!(budget.is_exceeded_by(10.001));
    }

    #[test]
    fn test_carbon_estimation() {
        let config = CarbonConfig {
            provider: CarbonProvider::Static,
            region: "GB".to_string(),
            static_intensity: 200.0,
        };
        // 3,600,000,000 mJ = 1 kWh => at 200 mg/kWh => 200 mg
        // 3,600,000 mJ => 0.001 kWh => 0.2 mg
        let carbon = config.estimate_carbon_mg(3_600_000.0);
        assert!((carbon - 0.2).abs() < 1e-6);
    }

    #[test]
    fn test_compliance_status_from_percent() {
        assert_eq!(
            ComplianceStatus::from_usage_percent(50.0),
            ComplianceStatus::Compliant
        );
        assert_eq!(
            ComplianceStatus::from_usage_percent(85.0),
            ComplianceStatus::Warning
        );
        assert_eq!(
            ComplianceStatus::from_usage_percent(101.0),
            ComplianceStatus::Exceeded
        );
    }

    #[test]
    fn test_function_budget_builders() {
        let fb = FunctionBudget {
            name: "process".to_string(),
            source: "src/lib.rs".to_string(),
            energy_budget_mj: Some(50.0),
            carbon_budget_mg: None,
        };
        assert!(fb.energy_budget().is_some());
        assert!(fb.carbon_budget().is_none());
    }
}
