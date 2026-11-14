// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Integration tests for eclexiaiser — verifies end-to-end behaviour of manifest
// parsing, validation, code generation, instrumentation, and report generation.

use eclexiaiser::abi::{
    CarbonBudget, CarbonConfig, CarbonProvider, ComplianceStatus, EnergyBudget, FunctionBudget,
    ReportConfig, ReportFormat, SustainabilityReport,
};
use eclexiaiser::manifest::{Manifest, ProjectConfig};
use tempfile::TempDir;

/// Helper: build a complete manifest for testing.
fn green_service_manifest() -> Manifest {
    Manifest {
        project: ProjectConfig {
            name: "green-service".to_string(),
        },
        functions: vec![
            FunctionBudget {
                name: "process_batch".to_string(),
                source: "src/batch.rs".to_string(),
                energy_budget_mj: Some(50.0),
                carbon_budget_mg: Some(10.0),
            },
            FunctionBudget {
                name: "render_page".to_string(),
                source: "src/web.rs".to_string(),
                energy_budget_mj: Some(5.0),
                carbon_budget_mg: None,
            },
        ],
        carbon: CarbonConfig {
            provider: CarbonProvider::Static,
            region: "GB".to_string(),
            static_intensity: 200.0,
        },
        report: ReportConfig {
            format: ReportFormat::Text,
            include_recommendations: true,
        },
    }
}

/// Test 1: Full manifest parse-validate-generate pipeline.
///
/// Verifies that a valid TOML manifest can be parsed, validated, and used to
/// generate all artifacts (instrumentation code, constraints, report) without error.
#[test]
fn test_full_generation_pipeline() {
    let toml_content = r#"
[project]
name = "green-service"

[[functions]]
name = "process_batch"
source = "src/batch.rs"
energy-budget-mj = 50.0
carbon-budget-mg = 10.0

[[functions]]
name = "render_page"
source = "src/web.rs"
energy-budget-mj = 5.0

[carbon]
provider = "static"
region = "GB"
static-intensity = 200.0

[report]
format = "text"
include-recommendations = true
"#;

    let manifest = eclexiaiser::parse_manifest(toml_content).expect("Should parse valid manifest");
    eclexiaiser::validate(&manifest).expect("Should validate successfully");

    // Generate to a temp directory.
    let tmp = TempDir::new().expect("Should create temp dir");
    let output_dir = tmp.path().to_str().unwrap();

    eclexiaiser::codegen::generate_all(&manifest, output_dir)
        .expect("Should generate all artifacts");

    // Verify generated files exist.
    assert!(
        tmp.path().join("eclexia_instrument.rs").exists(),
        "Instrumentation code should be generated"
    );
    assert!(
        tmp.path().join("eclexia_constraints.ecl").exists(),
        "Constraints file should be generated"
    );
    assert!(
        tmp.path().join("sustainability_report.txt").exists(),
        "Report should be generated"
    );
}

/// Test 2: Manifest validation rejects invalid configurations.
///
/// Verifies that the validator catches empty project names, missing functions,
/// negative budgets, and other semantic errors.
#[test]
fn test_manifest_validation_rejects_invalid() {
    // Empty project name.
    let mut m = green_service_manifest();
    m.project.name = "".to_string();
    assert!(
        eclexiaiser::validate(&m).is_err(),
        "Should reject empty project name"
    );

    // No functions.
    let mut m = green_service_manifest();
    m.functions.clear();
    assert!(
        eclexiaiser::validate(&m).is_err(),
        "Should reject manifest with no functions"
    );

    // Negative energy budget.
    let mut m = green_service_manifest();
    m.functions[0].energy_budget_mj = Some(-1.0);
    assert!(
        eclexiaiser::validate(&m).is_err(),
        "Should reject negative energy budget"
    );

    // Static provider with zero intensity.
    let mut m = green_service_manifest();
    m.carbon.static_intensity = 0.0;
    assert!(
        eclexiaiser::validate(&m).is_err(),
        "Should reject zero static intensity"
    );
}

/// Test 3: Energy and carbon budget compliance logic.
///
/// Verifies that EnergyBudget and CarbonBudget correctly detect exceeded budgets
/// and calculate usage percentages.
#[test]
fn test_budget_compliance_logic() {
    let energy = EnergyBudget::new(100.0);
    assert!(
        !energy.is_exceeded_by(100.0),
        "Equal to budget = not exceeded"
    );
    assert!(energy.is_exceeded_by(100.001), "Above budget = exceeded");
    assert!(
        (energy.usage_percent(75.0) - 75.0).abs() < f64::EPSILON,
        "75 of 100 = 75%"
    );

    let carbon = CarbonBudget::new(20.0);
    assert!(!carbon.is_exceeded_by(19.999));
    assert!(carbon.is_exceeded_by(20.001));

    // Compliance status thresholds.
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

/// Test 4: Sustainability report generation with simulated measurements.
///
/// Verifies that a simulated report at various usage fractions produces correct
/// compliance results and recommendation generation.
#[test]
fn test_simulated_report_compliance() {
    let m = green_service_manifest();

    // 50% usage — all compliant.
    let report = eclexiaiser::codegen::generate_report_from_simulated(&m, 0.5)
        .expect("Should generate 50% report");
    assert!(report.all_compliant, "50% usage should be compliant");
    assert_eq!(report.energy_violations(), 0);
    assert_eq!(report.carbon_violations(), 0);
    assert_eq!(report.measurements.len(), 2);

    // 150% usage — should exceed budgets.
    let report = eclexiaiser::codegen::generate_report_from_simulated(&m, 1.5)
        .expect("Should generate 150% report");
    assert!(!report.all_compliant, "150% usage should not be compliant");
    assert!(
        report.energy_violations() > 0,
        "Should have energy violations"
    );
    assert!(
        !report.recommendations.is_empty(),
        "Should generate recommendations"
    );
}

/// Test 5: Instrumentation code generation produces valid Rust syntax.
///
/// Verifies that the generated instrumentation code contains expected function
/// wrappers, budget constants, and measurement helpers.
#[test]
fn test_instrumentation_code_content() {
    let m = green_service_manifest();
    let parsed = eclexiaiser::codegen::parser::parse_function_budgets(&m.functions)
        .expect("Should parse function budgets");
    let code = eclexiaiser::codegen::instrumenter::generate_instrumentation(&m, &parsed)
        .expect("Should generate instrumentation");

    // Should contain wrapper functions.
    assert!(
        code.contains("pub fn measure_process_batch"),
        "Missing process_batch wrapper"
    );
    assert!(
        code.contains("pub fn measure_render_page"),
        "Missing render_page wrapper"
    );

    // Should contain budget constants.
    assert!(
        code.contains("PROCESS_BATCH_ENERGY_BUDGET_MJ"),
        "Missing energy budget constant"
    );
    assert!(
        code.contains("PROCESS_BATCH_CARBON_BUDGET_MG"),
        "Missing carbon budget constant"
    );

    // Should contain the energy measurement helper.
    assert!(
        code.contains("pub fn measure_energy"),
        "Missing measure_energy helper"
    );
    assert!(
        code.contains("pub fn estimate_carbon_mg"),
        "Missing estimate_carbon_mg helper"
    );

    // Should contain carbon intensity from manifest.
    assert!(code.contains("200.0"), "Missing carbon intensity value");
}

/// Test 6: Eclexia constraint file generation produces valid S-expression format.
///
/// Verifies that the generated .ecl file contains properly structured constraint
/// definitions for all budgeted functions.
#[test]
fn test_constraint_file_content() {
    let m = green_service_manifest();
    let parsed = eclexiaiser::codegen::parser::parse_function_budgets(&m.functions)
        .expect("Should parse function budgets");
    let ecl = eclexiaiser::codegen::instrumenter::generate_constraints(&m, &parsed)
        .expect("Should generate constraints");

    // Should contain carbon config.
    assert!(
        ecl.contains("(carbon-config"),
        "Missing carbon-config block"
    );
    assert!(ecl.contains("(region \"GB\")"), "Missing region");
    assert!(
        ecl.contains("(intensity-mg-per-kwh 200.0)"),
        "Missing intensity"
    );

    // Should contain function constraints.
    assert!(
        ecl.contains("(define-constraint process_batch"),
        "Missing process_batch constraint"
    );
    assert!(
        ecl.contains("(energy-bound-mj 50.0)"),
        "Missing energy bound"
    );
    assert!(
        ecl.contains("(carbon-bound-mg 10.0)"),
        "Missing carbon bound"
    );
    assert!(
        ecl.contains("(define-constraint render_page"),
        "Missing render_page constraint"
    );
    assert!(
        ecl.contains("(enforcement strict)"),
        "Missing enforcement mode"
    );
}

/// Test 7: JSON report format serialization.
///
/// Verifies that report generation in JSON format produces valid, deserializable JSON
/// containing all expected fields.
#[test]
fn test_json_report_format() {
    let mut m = green_service_manifest();
    m.report.format = ReportFormat::Json;

    let report = eclexiaiser::codegen::generate_report_from_simulated(&m, 0.7)
        .expect("Should generate report");

    let tmp = TempDir::new().expect("Should create temp dir");
    let base_path = tmp.path().join("report");
    eclexiaiser::codegen::reporter::write_report(&report, &m.report, base_path.to_str().unwrap())
        .expect("Should write JSON report");

    let json_path = tmp.path().join("report.json");
    assert!(json_path.exists(), "JSON report file should exist");

    let json_content = std::fs::read_to_string(&json_path).expect("Should read JSON");
    let deserialized: SustainabilityReport =
        serde_json::from_str(&json_content).expect("Should deserialize report JSON");
    assert_eq!(deserialized.project_name, "green-service");
    assert_eq!(deserialized.measurements.len(), 2);
    assert!(deserialized.all_compliant);
}

/// Test 8: CSRD report format contains required EU disclosure elements.
///
/// Verifies that the CSRD-format report includes ESRS E1 headers, scope 2
/// emissions data, and compliance status as required by the directive.
#[test]
fn test_csrd_report_format() {
    let mut m = green_service_manifest();
    m.report.format = ReportFormat::Csrd;

    let report = eclexiaiser::codegen::generate_report_from_simulated(&m, 1.2)
        .expect("Should generate exceeded report");

    let tmp = TempDir::new().expect("Should create temp dir");
    let base_path = tmp.path().join("csrd_report");
    eclexiaiser::codegen::reporter::write_report(&report, &m.report, base_path.to_str().unwrap())
        .expect("Should write CSRD report");

    let csrd_path = tmp.path().join("csrd_report.csrd.txt");
    assert!(csrd_path.exists(), "CSRD report file should exist");

    let content = std::fs::read_to_string(&csrd_path).expect("Should read CSRD report");
    assert!(
        content.contains("EU CSRD Sustainability Disclosure"),
        "Missing CSRD header"
    );
    assert!(content.contains("ESRS E1"), "Missing ESRS E1 reference");
    assert!(
        content.contains("SCOPE 2 EMISSIONS"),
        "Missing scope 2 section"
    );
    assert!(
        content.contains("COMPLIANCE STATUS"),
        "Missing compliance section"
    );
    assert!(
        content.contains("CORRECTIVE ACTIONS"),
        "Should have corrective actions at 120% usage"
    );
}

/// Test 9: Carbon estimation accuracy.
///
/// Verifies that the carbon estimation formula produces physically correct values
/// for known energy inputs and intensity values.
#[test]
fn test_carbon_estimation_accuracy() {
    let config = CarbonConfig {
        provider: CarbonProvider::Static,
        region: "GB".to_string(),
        static_intensity: 200.0, // 200 mg CO2 per kWh
    };

    // 1 kWh = 3,600,000,000 mJ. At 200 mg/kWh, 1 kWh => 200 mg CO2.
    let carbon_1kwh = config.estimate_carbon_mg(3_600_000_000.0);
    assert!(
        (carbon_1kwh - 200.0).abs() < 1e-6,
        "1 kWh at 200 mg/kWh should produce 200 mg CO2, got {carbon_1kwh}"
    );

    // 1 mJ at 200 mg/kWh => 200 / 3,600,000,000 mg CO2
    let carbon_1mj = config.estimate_carbon_mg(1.0);
    let expected = 200.0 / 3_600_000_000.0;
    assert!(
        (carbon_1mj - expected).abs() < 1e-15,
        "1 mJ should produce {expected} mg CO2, got {carbon_1mj}"
    );

    // Zero energy => zero carbon.
    assert_eq!(config.estimate_carbon_mg(0.0), 0.0);
}

/// Test 10: Init command creates a valid manifest template.
///
/// Verifies that the init command produces a manifest file that can be parsed
/// and validated by the eclexiaiser pipeline.
#[test]
fn test_init_creates_valid_manifest() {
    let tmp = TempDir::new().expect("Should create temp dir");
    let dir = tmp.path().to_str().unwrap();

    eclexiaiser::manifest::init_manifest(dir).expect("Should create manifest");

    let manifest_path = tmp.path().join("eclexiaiser.toml");
    assert!(manifest_path.exists(), "Manifest file should exist");

    let m = eclexiaiser::load_manifest(manifest_path.to_str().unwrap())
        .expect("Init manifest should be parseable");
    eclexiaiser::validate(&m).expect("Init manifest should be valid");
}
