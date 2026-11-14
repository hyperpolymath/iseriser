// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Integration tests for wokelangiser — validates the full pipeline from
// manifest loading through code generation, covering consent gates,
// WCAG accessibility checks, and i18n string extraction.

use tempfile::TempDir;
use wokelangiser::abi::{
    ComplianceReport, ConsentCategory, ConsentGate, ConsentState, Finding, Locale, Severity,
    WCAGLevel,
};
use wokelangiser::manifest;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Create a temporary directory with a valid wokelangiser.toml manifest.
fn setup_manifest_dir(manifest_content: &str) -> TempDir {
    let dir = tempfile::tempdir().expect("Failed to create temp dir");
    std::fs::write(dir.path().join("wokelangiser.toml"), manifest_content)
        .expect("Failed to write manifest");
    dir
}

/// The standard test manifest with all features enabled.
const TEST_MANIFEST: &str = r#"
[project]
name = "compliant-app"

[consent]
gdpr = true
ccpa = true
default-state = "opt-out"
categories = ["analytics", "marketing", "functional"]

[accessibility]
wcag-level = "AA"
check-contrast = true
check-alt-text = true
check-aria = true
min-contrast-ratio = 4.5

[i18n]
default-locale = "en-GB"
supported-locales = ["en-GB", "fr-FR", "de-DE", "es-ES"]
extract-strings = true

[report]
format = "text"
"#;

// ---------------------------------------------------------------------------
// test_init_creates_manifest
// ---------------------------------------------------------------------------

#[test]
fn test_init_creates_manifest() {
    let dir = tempfile::tempdir().expect("Failed to create temp dir");
    let dir_path = dir.path().to_str().unwrap();

    // Init should create a wokelangiser.toml file.
    manifest::init_manifest(dir_path).expect("init_manifest should succeed");

    let manifest_path = dir.path().join("wokelangiser.toml");
    assert!(
        manifest_path.exists(),
        "wokelangiser.toml should be created"
    );

    // The created manifest should be parseable and valid.
    let m = manifest::load_manifest(manifest_path.to_str().unwrap())
        .expect("created manifest should be loadable");
    manifest::validate(&m).expect("created manifest should be valid");

    // Init should fail if manifest already exists.
    let result = manifest::init_manifest(dir_path);
    assert!(
        result.is_err(),
        "init should fail if manifest already exists"
    );
}

// ---------------------------------------------------------------------------
// test_generate_produces_consent_gates
// ---------------------------------------------------------------------------

#[test]
fn test_generate_produces_consent_gates() {
    let dir = setup_manifest_dir(TEST_MANIFEST);
    let output_dir = dir.path().join("output");

    // Create a sample HTML file with analytics tracking.
    let src_dir = dir.path();
    std::fs::write(
        src_dir.join("index.html"),
        r#"<html>
<head><script>gtag('config', 'GA-12345');</script></head>
<body>
<img src="logo.png">
<p>Welcome to our site</p>
<button></button>
</body>
</html>"#,
    )
    .unwrap();

    // Update the manifest to point to our temp dir as source root.
    let manifest_content = TEST_MANIFEST.replace(
        "name = \"compliant-app\"",
        &format!(
            "name = \"compliant-app\"\nsource_root = \"{}\"",
            src_dir.to_str().unwrap().replace('\\', "\\\\")
        ),
    );
    std::fs::write(dir.path().join("wokelangiser.toml"), &manifest_content).unwrap();

    let m =
        manifest::load_manifest(dir.path().join("wokelangiser.toml").to_str().unwrap()).unwrap();
    manifest::validate(&m).unwrap();

    wokelangiser::codegen::generate_all(&m, output_dir.to_str().unwrap())
        .expect("generate_all should succeed");

    // Check that consent gate files were generated.
    assert!(
        output_dir
            .join("consent")
            .join("consent_manager.js")
            .exists(),
        "consent_manager.js should be generated"
    );
    assert!(
        output_dir.join("consent").join("gates.js").exists(),
        "gates.js should be generated"
    );
    assert!(
        output_dir.join("consent").join("banner.html").exists(),
        "banner.html should be generated"
    );

    // The consent manager should contain the configured categories.
    let manager_content =
        std::fs::read_to_string(output_dir.join("consent").join("consent_manager.js")).unwrap();
    assert!(manager_content.contains("\"analytics\""));
    assert!(manager_content.contains("\"marketing\""));
    assert!(manager_content.contains("\"functional\""));
    assert!(manager_content.contains("opted_out")); // default state
}

// ---------------------------------------------------------------------------
// test_wcag_contrast_check
// ---------------------------------------------------------------------------

#[test]
fn test_wcag_contrast_check() {
    use wokelangiser::codegen::accessibility::{
        contrast_ratio, meets_contrast_requirement, parse_hex_colour,
    };

    // Black on white: maximum contrast (21:1).
    let ratio = contrast_ratio(0, 0, 0, 255, 255, 255);
    assert!(
        ratio > 20.0 && ratio < 22.0,
        "Black/white contrast should be ~21:1, got {}",
        ratio
    );
    assert!(meets_contrast_requirement(ratio, WCAGLevel::AAA, false));

    // Grey (#777) on white: approximately 4.48:1 — fails AA normal, passes AA large.
    let (r, g, b) = parse_hex_colour("#777777").unwrap();
    let ratio_grey = contrast_ratio(r, g, b, 255, 255, 255);
    assert!(
        !meets_contrast_requirement(ratio_grey, WCAGLevel::AA, false),
        "#777 on white should fail AA normal text (ratio: {})",
        ratio_grey
    );
    assert!(
        meets_contrast_requirement(ratio_grey, WCAGLevel::AA, true),
        "#777 on white should pass AA large text (ratio: {})",
        ratio_grey
    );

    // Very low contrast: light grey (#CCC) on white.
    let (r2, g2, b2) = parse_hex_colour("#CCCCCC").unwrap();
    let ratio_low = contrast_ratio(r2, g2, b2, 255, 255, 255);
    assert!(
        !meets_contrast_requirement(ratio_low, WCAGLevel::A, false),
        "#CCC on white should fail even Level A (ratio: {})",
        ratio_low
    );
}

// ---------------------------------------------------------------------------
// test_i18n_string_extraction
// ---------------------------------------------------------------------------

#[test]
fn test_i18n_string_extraction() {
    let dir = setup_manifest_dir(TEST_MANIFEST);

    // Create an HTML file with translatable content.
    std::fs::write(
        dir.path().join("page.html"),
        r#"<html>
<body>
  <h1>Welcome to Our Application</h1>
  <p>Please log in to continue</p>
  <input placeholder="Enter your email" />
  <button>Submit</button>
</body>
</html>"#,
    )
    .unwrap();

    // Point source_root at the temp directory.
    let manifest_content = format!(
        r#"
[project]
name = "i18n-test"
source_root = "{}"

[consent]
gdpr = false
ccpa = false
default-state = "opt-out"
categories = ["functional"]

[accessibility]
wcag-level = "AA"

[i18n]
default-locale = "en-GB"
supported-locales = ["en-GB", "fr-FR"]
extract-strings = true

[report]
format = "text"
"#,
        dir.path().to_str().unwrap().replace('\\', "\\\\")
    );
    std::fs::write(dir.path().join("wokelangiser.toml"), &manifest_content).unwrap();

    let m =
        manifest::load_manifest(dir.path().join("wokelangiser.toml").to_str().unwrap()).unwrap();

    let strings = wokelangiser::codegen::parser::extract_i18n_strings(&m).unwrap();
    assert!(
        !strings.is_empty(),
        "Should extract translatable strings from HTML"
    );

    // Check that specific strings were found.
    let values: Vec<&str> = strings.iter().map(|s| s.default_value.as_str()).collect();
    assert!(
        values.iter().any(|v| v.contains("Welcome")),
        "Should find 'Welcome to Our Application'. Found: {:?}",
        values
    );

    // Test locale file generation.
    let output_dir = dir.path().join("output");
    let locale_files = wokelangiser::codegen::i18n::generate_locale_files(
        &m,
        &strings,
        output_dir.to_str().unwrap(),
    )
    .unwrap();
    assert_eq!(locale_files.len(), 2); // en-GB + fr-FR

    // en-GB should have values, fr-FR should have empty values.
    let en_file = &locale_files[0];
    assert_eq!(en_file.locale.tag, "en-GB");
    assert!(!en_file.translations.is_empty());
    assert!(
        en_file.translations.iter().any(|(_, v)| !v.is_empty()),
        "en-GB should have non-empty translations"
    );

    let fr_file = &locale_files[1];
    assert_eq!(fr_file.locale.tag, "fr-FR");
    assert!(
        fr_file.translations.iter().all(|(_, v)| v.is_empty()),
        "fr-FR should have all empty translations (template)"
    );
}

// ---------------------------------------------------------------------------
// test_consent_state_machine
// ---------------------------------------------------------------------------

#[test]
fn test_consent_state_machine() {
    // Test the full consent state machine lifecycle.

    // Initial state should be Pending.
    let state = ConsentState::Pending;
    assert!(
        !state.is_allowed(),
        "Pending should not allow data collection"
    );

    // User grants consent.
    let granted = state.transition(true);
    assert_eq!(granted, ConsentState::OptIn);
    assert!(granted.is_allowed(), "OptIn should allow data collection");

    // User revokes consent.
    let revoked = granted.transition(false);
    assert_eq!(revoked, ConsentState::OptOut);
    assert!(
        !revoked.is_allowed(),
        "OptOut should not allow data collection"
    );

    // User re-grants consent.
    let re_granted = revoked.transition(true);
    assert_eq!(re_granted, ConsentState::OptIn);
    assert!(re_granted.is_allowed());

    // Test that ConsentGate respects state.
    let gate = ConsentGate {
        id: "test_gate".to_string(),
        category: ConsentCategory::Analytics,
        state: ConsentState::Pending,
        description: "Test gate".to_string(),
        gdpr_required: true,
        ccpa_required: false,
    };
    assert!(
        !gate.state.is_allowed(),
        "Gate in Pending state should block"
    );

    // Simulate state transition on the gate.
    let new_state = gate.state.transition(true);
    assert!(new_state.is_allowed(), "After granting, gate should allow");
}

// ---------------------------------------------------------------------------
// test_all_wcag_levels
// ---------------------------------------------------------------------------

#[test]
fn test_all_wcag_levels() {
    use wokelangiser::codegen::accessibility::{contrast_ratio, meets_contrast_requirement};

    // Pure black (#000) on pure white (#FFF): ratio ~21:1.
    let bw_ratio = contrast_ratio(0, 0, 0, 255, 255, 255);

    // Level A: requires 3.0:1 minimum.
    assert!(meets_contrast_requirement(bw_ratio, WCAGLevel::A, false));
    assert!(meets_contrast_requirement(3.0, WCAGLevel::A, false));
    assert!(!meets_contrast_requirement(2.9, WCAGLevel::A, false));

    // Level AA: requires 4.5:1 for normal text, 3.0:1 for large text.
    assert!(meets_contrast_requirement(bw_ratio, WCAGLevel::AA, false));
    assert!(meets_contrast_requirement(4.5, WCAGLevel::AA, false));
    assert!(!meets_contrast_requirement(4.4, WCAGLevel::AA, false));
    assert!(meets_contrast_requirement(3.0, WCAGLevel::AA, true));
    assert!(!meets_contrast_requirement(2.9, WCAGLevel::AA, true));

    // Level AAA: requires 7.0:1 for normal text, 4.5:1 for large text.
    assert!(meets_contrast_requirement(bw_ratio, WCAGLevel::AAA, false));
    assert!(meets_contrast_requirement(7.0, WCAGLevel::AAA, false));
    assert!(!meets_contrast_requirement(6.9, WCAGLevel::AAA, false));
    assert!(meets_contrast_requirement(4.5, WCAGLevel::AAA, true));
    assert!(!meets_contrast_requirement(4.4, WCAGLevel::AAA, true));

    // WCAGLevel ordering: A < AA < AAA.
    assert!(WCAGLevel::A < WCAGLevel::AA);
    assert!(WCAGLevel::AA < WCAGLevel::AAA);

    // Contrast ratio thresholds increase with level.
    assert!(WCAGLevel::A.min_contrast_ratio() < WCAGLevel::AA.min_contrast_ratio());
    assert!(WCAGLevel::AA.min_contrast_ratio() < WCAGLevel::AAA.min_contrast_ratio());

    // Verify the compliance report correctly marks levels.
    let mut report = ComplianceReport::new("test", WCAGLevel::AA);
    assert!(report.passes);

    // A violation at level A (below AA target) should be an error.
    report.add_finding(Finding {
        severity: Severity::Error,
        category: "accessibility".to_string(),
        message: "Missing alt text (A level)".to_string(),
        file: Some("test.html".to_string()),
        line: Some(1),
    });
    assert!(
        !report.passes,
        "Error-level findings should fail the report"
    );

    // Verify all three WCAG levels parse correctly.
    assert_eq!(WCAGLevel::from_str("A"), Some(WCAGLevel::A));
    assert_eq!(WCAGLevel::from_str("AA"), Some(WCAGLevel::AA));
    assert_eq!(WCAGLevel::from_str("AAA"), Some(WCAGLevel::AAA));
    assert_eq!(WCAGLevel::from_str("AAAA"), None);
}

// ---------------------------------------------------------------------------
// Additional edge case tests
// ---------------------------------------------------------------------------

#[test]
fn test_manifest_gdpr_opt_in_rejected() {
    let manifest_content = r#"
[project]
name = "gdpr-bad"

[consent]
gdpr = true
default-state = "opt-in"
categories = ["analytics"]

[i18n]
default-locale = "en-GB"
supported-locales = ["en-GB"]
"#;
    let m: manifest::Manifest = toml::from_str(manifest_content).unwrap();
    let result = manifest::validate(&m);
    assert!(
        result.is_err(),
        "GDPR + opt-in default should fail validation"
    );
    assert!(
        result.unwrap_err().to_string().contains("opt-out"),
        "Error should mention opt-out requirement"
    );
}

#[test]
fn test_locale_region_parsing() {
    let en_gb = Locale::new("en-GB");
    assert_eq!(en_gb.language(), "en");
    assert_eq!(en_gb.region(), Some("GB"));

    let fr = Locale::new("fr");
    assert_eq!(fr.language(), "fr");
    assert_eq!(fr.region(), None);

    let zh_hans_cn = Locale::new("zh-Hans-CN");
    assert_eq!(zh_hans_cn.language(), "zh");
    // Our simple parser returns "Hans" as region — acceptable for Phase 1.
    assert_eq!(zh_hans_cn.region(), Some("Hans"));
}

#[test]
fn test_consent_category_custom() {
    let custom = ConsentCategory::from_str("telemetry");
    assert_eq!(custom, ConsentCategory::Custom("telemetry".to_string()));
    assert_eq!(custom.name(), "telemetry");

    // Standard categories are case-insensitive.
    assert_eq!(
        ConsentCategory::from_str("ANALYTICS"),
        ConsentCategory::Analytics
    );
    assert_eq!(
        ConsentCategory::from_str("Marketing"),
        ConsentCategory::Marketing
    );
}

#[test]
fn test_compliance_report_summary() {
    let mut report = ComplianceReport::new("test", WCAGLevel::AA);
    report.add_finding(Finding {
        severity: Severity::Error,
        category: "a11y".to_string(),
        message: "err1".to_string(),
        file: None,
        line: None,
    });
    report.add_finding(Finding {
        severity: Severity::Error,
        category: "a11y".to_string(),
        message: "err2".to_string(),
        file: None,
        line: None,
    });
    report.add_finding(Finding {
        severity: Severity::Warning,
        category: "a11y".to_string(),
        message: "warn1".to_string(),
        file: None,
        line: None,
    });
    report.add_finding(Finding {
        severity: Severity::Info,
        category: "a11y".to_string(),
        message: "info1".to_string(),
        file: None,
        line: None,
    });

    let (errors, warnings, infos) = report.summary();
    assert_eq!(errors, 2);
    assert_eq!(warnings, 1);
    assert_eq!(infos, 1);
    assert!(!report.passes);
}
