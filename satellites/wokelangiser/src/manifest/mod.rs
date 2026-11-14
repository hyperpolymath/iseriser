// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Manifest module for wokelangiser — parses and validates wokelangiser.toml
// configuration files that describe consent requirements, accessibility levels,
// internationalisation settings, and reporting preferences.

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::path::Path;

// ---------------------------------------------------------------------------
// Manifest structure (mirrors wokelangiser.toml)
// ---------------------------------------------------------------------------

/// Top-level manifest representing a wokelangiser.toml configuration file.
/// Configures consent, accessibility, internationalisation, and reporting
/// for a target project.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Manifest {
    /// Project metadata.
    pub project: ProjectConfig,
    /// Consent and privacy configuration (GDPR, CCPA).
    #[serde(default)]
    pub consent: ConsentConfig,
    /// WCAG accessibility configuration.
    #[serde(default)]
    pub accessibility: AccessibilityConfig,
    /// Internationalisation (i18n) configuration.
    #[serde(default)]
    pub i18n: I18nConfig,
    /// Report output configuration.
    #[serde(default)]
    pub report: ReportConfig,
}

/// Project-level metadata.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectConfig {
    /// Name of the project being analysed.
    pub name: String,
    /// Root directory of the project source (defaults to ".").
    #[serde(default = "default_source_root")]
    pub source_root: String,
}

fn default_source_root() -> String {
    ".".to_string()
}

/// Consent and privacy regulation configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConsentConfig {
    /// Whether GDPR compliance is required.
    #[serde(default)]
    pub gdpr: bool,
    /// Whether CCPA compliance is required.
    #[serde(default)]
    pub ccpa: bool,
    /// Default consent state for new users: "opt-in" or "opt-out".
    /// Under GDPR, this MUST be "opt-out" (no pre-ticked boxes).
    #[serde(rename = "default-state", default = "default_consent_state")]
    pub default_state: String,
    /// Categories of data collection requiring separate consent.
    #[serde(default = "default_categories")]
    pub categories: Vec<String>,
}

fn default_consent_state() -> String {
    "opt-out".to_string()
}

fn default_categories() -> Vec<String> {
    vec![
        "analytics".to_string(),
        "marketing".to_string(),
        "functional".to_string(),
    ]
}

impl Default for ConsentConfig {
    fn default() -> Self {
        ConsentConfig {
            gdpr: false,
            ccpa: false,
            default_state: default_consent_state(),
            categories: default_categories(),
        }
    }
}

/// WCAG 2.2 accessibility checking configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AccessibilityConfig {
    /// Target WCAG conformance level: "A", "AA", or "AAA".
    #[serde(rename = "wcag-level", default = "default_wcag_level")]
    pub wcag_level: String,
    /// Whether to check foreground/background colour contrast ratios.
    #[serde(rename = "check-contrast", default = "default_true")]
    pub check_contrast: bool,
    /// Whether to check for missing alt text on images.
    #[serde(rename = "check-alt-text", default = "default_true")]
    pub check_alt_text: bool,
    /// Whether to check for missing ARIA labels on interactive elements.
    #[serde(rename = "check-aria", default = "default_true")]
    pub check_aria: bool,
    /// Minimum contrast ratio override (defaults to WCAG level requirement).
    #[serde(rename = "min-contrast-ratio", default)]
    pub min_contrast_ratio: Option<f64>,
}

fn default_wcag_level() -> String {
    "AA".to_string()
}

fn default_true() -> bool {
    true
}

impl Default for AccessibilityConfig {
    fn default() -> Self {
        AccessibilityConfig {
            wcag_level: default_wcag_level(),
            check_contrast: true,
            check_alt_text: true,
            check_aria: true,
            min_contrast_ratio: None,
        }
    }
}

/// Internationalisation configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct I18nConfig {
    /// Default locale (BCP 47 tag, e.g. "en-GB").
    #[serde(rename = "default-locale", default = "default_locale")]
    pub default_locale: String,
    /// List of supported locales.
    #[serde(rename = "supported-locales", default = "default_supported_locales")]
    pub supported_locales: Vec<String>,
    /// Whether to extract translatable strings from source files.
    #[serde(rename = "extract-strings", default = "default_true")]
    pub extract_strings: bool,
}

fn default_locale() -> String {
    "en-GB".to_string()
}

fn default_supported_locales() -> Vec<String> {
    vec!["en-GB".to_string()]
}

impl Default for I18nConfig {
    fn default() -> Self {
        I18nConfig {
            default_locale: default_locale(),
            supported_locales: default_supported_locales(),
            extract_strings: true,
        }
    }
}

/// Report output configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReportConfig {
    /// Report format: "text", "json", or "a2ml".
    #[serde(default = "default_report_format")]
    pub format: String,
}

fn default_report_format() -> String {
    "text".to_string()
}

impl Default for ReportConfig {
    fn default() -> Self {
        ReportConfig {
            format: default_report_format(),
        }
    }
}

// ---------------------------------------------------------------------------
// Loading, validation, and initialisation
// ---------------------------------------------------------------------------

/// Load a wokelangiser.toml manifest from the given file path.
/// Returns a parsed Manifest or an error if the file cannot be read or parsed.
pub fn load_manifest(path: &str) -> Result<Manifest> {
    let content = std::fs::read_to_string(path)
        .with_context(|| format!("Failed to read manifest: {}", path))?;
    toml::from_str(&content).with_context(|| format!("Failed to parse manifest: {}", path))
}

/// Validate a parsed manifest for internal consistency.
/// Checks that all configured values are within acceptable ranges and
/// that GDPR constraints are respected (e.g. default-state must be "opt-out"
/// when GDPR is enabled).
pub fn validate(manifest: &Manifest) -> Result<()> {
    // Project name must not be empty.
    if manifest.project.name.is_empty() {
        anyhow::bail!("project.name is required and must not be empty");
    }

    // Consent default-state must be "opt-in" or "opt-out".
    match manifest.consent.default_state.as_str() {
        "opt-in" | "opt-out" => {}
        other => anyhow::bail!(
            "consent.default-state must be 'opt-in' or 'opt-out', got '{}'",
            other
        ),
    }

    // GDPR requires opt-out as default (Article 7, Recital 32 — no pre-ticked boxes).
    if manifest.consent.gdpr && manifest.consent.default_state == "opt-in" {
        anyhow::bail!(
            "consent.default-state must be 'opt-out' when GDPR is enabled \
             (GDPR Article 7 requires affirmative consent)"
        );
    }

    // At least one consent category must be defined if consent is enabled.
    if (manifest.consent.gdpr || manifest.consent.ccpa) && manifest.consent.categories.is_empty() {
        anyhow::bail!("consent.categories must not be empty when GDPR or CCPA is enabled");
    }

    // WCAG level must be A, AA, or AAA.
    let wcag_upper = manifest.accessibility.wcag_level.to_uppercase();
    if !matches!(wcag_upper.as_str(), "A" | "AA" | "AAA") {
        anyhow::bail!(
            "accessibility.wcag-level must be 'A', 'AA', or 'AAA', got '{}'",
            manifest.accessibility.wcag_level
        );
    }

    // If a custom min-contrast-ratio is set, it must be positive.
    if let Some(ratio) = manifest.accessibility.min_contrast_ratio
        && ratio <= 0.0
    {
        anyhow::bail!(
            "accessibility.min-contrast-ratio must be positive, got {}",
            ratio
        );
    }

    // Report format must be text, json, or a2ml.
    match manifest.report.format.as_str() {
        "text" | "json" | "a2ml" => {}
        other => anyhow::bail!(
            "report.format must be 'text', 'json', or 'a2ml', got '{}'",
            other
        ),
    }

    // Default locale must be in supported locales.
    if !manifest
        .i18n
        .supported_locales
        .contains(&manifest.i18n.default_locale)
    {
        anyhow::bail!(
            "i18n.default-locale '{}' must be listed in i18n.supported-locales",
            manifest.i18n.default_locale
        );
    }

    Ok(())
}

/// The default manifest content written by `wokelangiser init`.
const DEFAULT_MANIFEST: &str = r#"# SPDX-License-Identifier: MPL-2.0
# wokelangiser.toml — consent, accessibility, and i18n configuration
# See: https://github.com/hyperpolymath/wokelangiser

[project]
name = "my-project"

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

/// Create a new wokelangiser.toml manifest in the given directory.
/// Fails if a manifest already exists at that location.
pub fn init_manifest(path: &str) -> Result<()> {
    let manifest_path = Path::new(path).join("wokelangiser.toml");
    if manifest_path.exists() {
        anyhow::bail!(
            "wokelangiser.toml already exists at {}",
            manifest_path.display()
        );
    }
    std::fs::write(&manifest_path, DEFAULT_MANIFEST)
        .with_context(|| format!("Failed to write manifest: {}", manifest_path.display()))?;
    println!("Created {}", manifest_path.display());
    Ok(())
}

/// Print a human-readable summary of the manifest configuration.
pub fn print_info(manifest: &Manifest) {
    println!("=== {} ===", manifest.project.name);
    println!("Source root: {}", manifest.project.source_root);
    println!();
    println!("[consent]");
    println!("  GDPR: {}", manifest.consent.gdpr);
    println!("  CCPA: {}", manifest.consent.ccpa);
    println!("  Default state: {}", manifest.consent.default_state);
    println!("  Categories: {}", manifest.consent.categories.join(", "));
    println!();
    println!("[accessibility]");
    println!("  WCAG level: {}", manifest.accessibility.wcag_level);
    println!(
        "  Check contrast: {}",
        manifest.accessibility.check_contrast
    );
    println!(
        "  Check alt text: {}",
        manifest.accessibility.check_alt_text
    );
    println!("  Check ARIA: {}", manifest.accessibility.check_aria);
    if let Some(ratio) = manifest.accessibility.min_contrast_ratio {
        println!("  Min contrast ratio: {}", ratio);
    }
    println!();
    println!("[i18n]");
    println!("  Default locale: {}", manifest.i18n.default_locale);
    println!(
        "  Supported locales: {}",
        manifest.i18n.supported_locales.join(", ")
    );
    println!("  Extract strings: {}", manifest.i18n.extract_strings);
    println!();
    println!("[report]");
    println!("  Format: {}", manifest.report.format);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    /// Helper to create a valid manifest for testing.
    fn valid_manifest() -> Manifest {
        Manifest {
            project: ProjectConfig {
                name: "test-project".to_string(),
                source_root: ".".to_string(),
            },
            consent: ConsentConfig {
                gdpr: true,
                ccpa: true,
                default_state: "opt-out".to_string(),
                categories: vec![
                    "analytics".to_string(),
                    "marketing".to_string(),
                    "functional".to_string(),
                ],
            },
            accessibility: AccessibilityConfig {
                wcag_level: "AA".to_string(),
                check_contrast: true,
                check_alt_text: true,
                check_aria: true,
                min_contrast_ratio: Some(4.5),
            },
            i18n: I18nConfig {
                default_locale: "en-GB".to_string(),
                supported_locales: vec!["en-GB".to_string(), "fr-FR".to_string()],
                extract_strings: true,
            },
            report: ReportConfig {
                format: "text".to_string(),
            },
        }
    }

    #[test]
    fn test_valid_manifest_passes_validation() {
        let m = valid_manifest();
        assert!(validate(&m).is_ok());
    }

    #[test]
    fn test_empty_project_name_fails() {
        let mut m = valid_manifest();
        m.project.name = String::new();
        assert!(validate(&m).is_err());
    }

    #[test]
    fn test_gdpr_with_opt_in_default_fails() {
        let mut m = valid_manifest();
        m.consent.gdpr = true;
        m.consent.default_state = "opt-in".to_string();
        let err = validate(&m).unwrap_err();
        assert!(err.to_string().contains("opt-out"));
    }

    #[test]
    fn test_invalid_wcag_level_fails() {
        let mut m = valid_manifest();
        m.accessibility.wcag_level = "B".to_string();
        assert!(validate(&m).is_err());
    }

    #[test]
    fn test_default_locale_not_in_supported_fails() {
        let mut m = valid_manifest();
        m.i18n.default_locale = "ja-JP".to_string();
        assert!(validate(&m).is_err());
    }

    #[test]
    fn test_parse_default_manifest() {
        let m: Manifest = toml::from_str(DEFAULT_MANIFEST).expect("default manifest should parse");
        assert_eq!(m.project.name, "my-project");
        assert!(m.consent.gdpr);
        assert_eq!(m.accessibility.wcag_level, "AA");
        assert_eq!(m.i18n.default_locale, "en-GB");
        assert!(validate(&m).is_ok());
    }
}
