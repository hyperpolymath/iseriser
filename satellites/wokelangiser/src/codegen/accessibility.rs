// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Accessibility checking module for wokelangiser — checks WCAG 2.2 compliance
// including contrast ratios, alt text, ARIA labels, and generates reports
// with actionable remediation advice.

use anyhow::Result;

use crate::abi::{AccessibilityViolation, ComplianceReport, Finding, Severity, WCAGLevel};
// ViolationKind is used in tests (via `use super::*`) and in the report generation function.
#[cfg(test)]
use crate::abi::ViolationKind;
use crate::manifest::Manifest;

// ---------------------------------------------------------------------------
// Contrast ratio calculation (WCAG 2.2 §1.4.3 / §1.4.6)
// ---------------------------------------------------------------------------

/// Compute the relative luminance of an sRGB colour channel value (0–255).
/// Per WCAG 2.2 definition: linearise the sRGB value, then apply the
/// luminance coefficients.
fn linearise_channel(value: u8) -> f64 {
    let srgb = value as f64 / 255.0;
    if srgb <= 0.04045 {
        srgb / 12.92
    } else {
        ((srgb + 0.055) / 1.055).powf(2.4)
    }
}

/// Compute the relative luminance of an RGB colour per WCAG 2.2.
/// L = 0.2126 * R + 0.7152 * G + 0.0722 * B
/// where R, G, B are linearised sRGB values.
pub fn relative_luminance(r: u8, g: u8, b: u8) -> f64 {
    0.2126 * linearise_channel(r) + 0.7152 * linearise_channel(g) + 0.0722 * linearise_channel(b)
}

/// Compute the contrast ratio between two colours per WCAG 2.2.
/// The ratio is always >= 1.0, with 1.0 meaning identical colours
/// and 21.0 being the maximum (black on white).
///
/// Formula: (L1 + 0.05) / (L2 + 0.05) where L1 >= L2.
pub fn contrast_ratio(r1: u8, g1: u8, b1: u8, r2: u8, g2: u8, b2: u8) -> f64 {
    let l1 = relative_luminance(r1, g1, b1);
    let l2 = relative_luminance(r2, g2, b2);
    let (lighter, darker) = if l1 > l2 { (l1, l2) } else { (l2, l1) };
    (lighter + 0.05) / (darker + 0.05)
}

/// Check whether a contrast ratio meets the WCAG requirement for normal text
/// at the given conformance level.
///
/// Requirements:
/// - Level A:   3.0:1 (large text only, relaxed)
/// - Level AA:  4.5:1 (normal text), 3.0:1 (large text)
/// - Level AAA: 7.0:1 (normal text), 4.5:1 (large text)
pub fn meets_contrast_requirement(ratio: f64, level: WCAGLevel, is_large_text: bool) -> bool {
    let required = match (level, is_large_text) {
        (WCAGLevel::A, _) => 3.0,
        (WCAGLevel::AA, true) => 3.0,
        (WCAGLevel::AA, false) => 4.5,
        (WCAGLevel::AAA, true) => 4.5,
        (WCAGLevel::AAA, false) => 7.0,
    };
    ratio >= required
}

// ---------------------------------------------------------------------------
// Parse hex colour strings
// ---------------------------------------------------------------------------

/// Parse a hex colour string (e.g. "#FF0000" or "FF0000") into (r, g, b).
/// Supports both 3-digit (#F00) and 6-digit (#FF0000) formats.
pub fn parse_hex_colour(hex: &str) -> Option<(u8, u8, u8)> {
    let hex = hex.trim_start_matches('#');
    match hex.len() {
        3 => {
            let r = u8::from_str_radix(&hex[0..1].repeat(2), 16).ok()?;
            let g = u8::from_str_radix(&hex[1..2].repeat(2), 16).ok()?;
            let b = u8::from_str_radix(&hex[2..3].repeat(2), 16).ok()?;
            Some((r, g, b))
        }
        6 => {
            let r = u8::from_str_radix(&hex[0..2], 16).ok()?;
            let g = u8::from_str_radix(&hex[2..4], 16).ok()?;
            let b = u8::from_str_radix(&hex[4..6], 16).ok()?;
            Some((r, g, b))
        }
        _ => None,
    }
}

// ---------------------------------------------------------------------------
// Report generation
// ---------------------------------------------------------------------------

/// Generate an accessibility compliance report from the manifest configuration
/// and a set of detected violations.
///
/// The report includes:
/// - All violations as findings (errors at the target level, warnings for higher levels)
/// - Contrast ratio check results (if applicable)
/// - Summary statistics and pass/fail determination
pub fn generate_accessibility_report(
    manifest: &Manifest,
    violations: &[AccessibilityViolation],
) -> Result<ComplianceReport> {
    let target_level =
        WCAGLevel::from_str(&manifest.accessibility.wcag_level).unwrap_or(WCAGLevel::AA);

    let mut report = ComplianceReport::new(&manifest.project.name, target_level);
    report.accessibility_violations_count = violations.len();

    for violation in violations {
        // Determine severity based on whether the violation is at or below the target level.
        let severity = if violation.level <= target_level {
            Severity::Error
        } else {
            Severity::Warning
        };

        report.add_finding(Finding {
            severity,
            category: "accessibility".to_string(),
            message: format!(
                "[WCAG {:?} §{}] {}",
                violation.level, violation.criterion, violation.message
            ),
            file: Some(violation.file.clone()),
            line: violation.line,
        });
    }

    // Add informational findings about what was checked.
    if manifest.accessibility.check_contrast {
        report.add_finding(Finding {
            severity: Severity::Info,
            category: "accessibility".to_string(),
            message: format!(
                "Contrast ratio checking enabled (min ratio: {} for {:?} normal text)",
                manifest
                    .accessibility
                    .min_contrast_ratio
                    .unwrap_or(target_level.min_contrast_ratio()),
                target_level
            ),
            file: None,
            line: None,
        });
    }

    if manifest.accessibility.check_alt_text {
        report.add_finding(Finding {
            severity: Severity::Info,
            category: "accessibility".to_string(),
            message: "Alt text checking enabled for all image elements".to_string(),
            file: None,
            line: None,
        });
    }

    if manifest.accessibility.check_aria {
        report.add_finding(Finding {
            severity: Severity::Info,
            category: "accessibility".to_string(),
            message: "ARIA label checking enabled for interactive elements".to_string(),
            file: None,
            line: None,
        });
    }

    Ok(report)
}

/// Format a compliance report according to the configured report format.
/// Supports "text", "json", and "a2ml" formats.
pub fn format_report(report: &ComplianceReport, format: &str) -> Result<String> {
    match format {
        "text" => Ok(report.to_text()),
        "json" => serde_json::to_string_pretty(report)
            .map_err(|e| anyhow::anyhow!("Failed to serialise report to JSON: {}", e)),
        "a2ml" => Ok(format_report_a2ml(report)),
        _ => anyhow::bail!("Unsupported report format: {}", format),
    }
}

/// Format a compliance report in A2ML (AI Agent Markup Language) format.
/// A2ML is the hyperpolymath standard for machine-readable AI directives.
fn format_report_a2ml(report: &ComplianceReport) -> String {
    let mut out = String::new();
    out.push_str("(compliance-report\n");
    out.push_str(&format!("  (project \"{}\")\n", report.project_name));
    out.push_str(&format!("  (wcag-level \"{:?}\")\n", report.wcag_level));
    out.push_str(&format!("  (passes {})\n", report.passes));
    out.push_str(&format!(
        "  (counts (consent-gates {}) (accessibility-violations {}) (i18n-strings {}))\n",
        report.consent_gates_count,
        report.accessibility_violations_count,
        report.i18n_strings_count
    ));
    out.push_str("  (findings\n");
    for finding in &report.findings {
        out.push_str(&format!(
            "    ({:?} \"{}\" \"{}\"",
            finding.severity, finding.category, finding.message
        ));
        if let Some(ref file) = finding.file {
            out.push_str(&format!(" (file \"{}\")", file));
        }
        if let Some(line) = finding.line {
            out.push_str(&format!(" (line {})", line));
        }
        out.push_str(")\n");
    }
    out.push_str("  )\n");
    out.push_str(")\n");
    out
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_relative_luminance_black() {
        let l = relative_luminance(0, 0, 0);
        assert!((l - 0.0).abs() < 0.001);
    }

    #[test]
    fn test_relative_luminance_white() {
        let l = relative_luminance(255, 255, 255);
        assert!((l - 1.0).abs() < 0.001);
    }

    #[test]
    fn test_contrast_ratio_black_white() {
        let ratio = contrast_ratio(0, 0, 0, 255, 255, 255);
        // Should be exactly 21.0.
        assert!((ratio - 21.0).abs() < 0.1);
    }

    #[test]
    fn test_contrast_ratio_same_colour() {
        let ratio = contrast_ratio(128, 128, 128, 128, 128, 128);
        assert!((ratio - 1.0).abs() < 0.001);
    }

    #[test]
    fn test_contrast_ratio_symmetry() {
        let ratio_ab = contrast_ratio(255, 0, 0, 0, 0, 255);
        let ratio_ba = contrast_ratio(0, 0, 255, 255, 0, 0);
        assert!((ratio_ab - ratio_ba).abs() < 0.001);
    }

    #[test]
    fn test_wcag_aa_contrast_check() {
        // Black on white: 21:1 — passes all levels.
        let ratio = contrast_ratio(0, 0, 0, 255, 255, 255);
        assert!(meets_contrast_requirement(ratio, WCAGLevel::A, false));
        assert!(meets_contrast_requirement(ratio, WCAGLevel::AA, false));
        assert!(meets_contrast_requirement(ratio, WCAGLevel::AAA, false));
    }

    #[test]
    fn test_wcag_aa_contrast_fail() {
        // Light grey on white: very low contrast.
        let ratio = contrast_ratio(200, 200, 200, 255, 255, 255);
        assert!(!meets_contrast_requirement(ratio, WCAGLevel::AA, false));
    }

    #[test]
    fn test_wcag_large_text_relaxed() {
        // A ratio of 3.5:1 should pass AA for large text but fail for normal text.
        assert!(meets_contrast_requirement(3.5, WCAGLevel::AA, true));
        assert!(!meets_contrast_requirement(3.5, WCAGLevel::AA, false));
    }

    #[test]
    fn test_all_wcag_levels_contrast_thresholds() {
        // Level A: 3.0
        assert!(meets_contrast_requirement(3.0, WCAGLevel::A, false));
        assert!(!meets_contrast_requirement(2.9, WCAGLevel::A, false));

        // Level AA normal: 4.5
        assert!(meets_contrast_requirement(4.5, WCAGLevel::AA, false));
        assert!(!meets_contrast_requirement(4.4, WCAGLevel::AA, false));

        // Level AA large: 3.0
        assert!(meets_contrast_requirement(3.0, WCAGLevel::AA, true));

        // Level AAA normal: 7.0
        assert!(meets_contrast_requirement(7.0, WCAGLevel::AAA, false));
        assert!(!meets_contrast_requirement(6.9, WCAGLevel::AAA, false));

        // Level AAA large: 4.5
        assert!(meets_contrast_requirement(4.5, WCAGLevel::AAA, true));
        assert!(!meets_contrast_requirement(4.4, WCAGLevel::AAA, true));
    }

    #[test]
    fn test_parse_hex_colour_6digit() {
        assert_eq!(parse_hex_colour("#FF0000"), Some((255, 0, 0)));
        assert_eq!(parse_hex_colour("00FF00"), Some((0, 255, 0)));
        assert_eq!(parse_hex_colour("#0000FF"), Some((0, 0, 255)));
    }

    #[test]
    fn test_parse_hex_colour_3digit() {
        assert_eq!(parse_hex_colour("#F00"), Some((255, 0, 0)));
        assert_eq!(parse_hex_colour("#FFF"), Some((255, 255, 255)));
    }

    #[test]
    fn test_parse_hex_colour_invalid() {
        assert_eq!(parse_hex_colour("ZZZZZZ"), None);
        assert_eq!(parse_hex_colour("#12"), None);
    }

    #[test]
    fn test_report_generation() {
        let manifest = crate::manifest::Manifest {
            project: crate::manifest::ProjectConfig {
                name: "test".to_string(),
                source_root: ".".to_string(),
            },
            consent: Default::default(),
            accessibility: crate::manifest::AccessibilityConfig {
                wcag_level: "AA".to_string(),
                check_contrast: true,
                check_alt_text: true,
                check_aria: true,
                min_contrast_ratio: Some(4.5),
            },
            i18n: crate::manifest::I18nConfig {
                default_locale: "en-GB".to_string(),
                supported_locales: vec!["en-GB".to_string()],
                extract_strings: true,
            },
            report: crate::manifest::ReportConfig {
                format: "text".to_string(),
            },
        };

        let violations = vec![AccessibilityViolation {
            kind: ViolationKind::MissingAltText,
            level: WCAGLevel::A,
            file: "index.html".to_string(),
            line: Some(42),
            message: "Image missing alt text".to_string(),
            criterion: "1.1.1".to_string(),
        }];

        let report =
            generate_accessibility_report(&manifest, &violations).expect("TODO: handle error");
        assert!(!report.passes); // should fail due to error-level violation
        assert_eq!(report.accessibility_violations_count, 1);
    }

    #[test]
    fn test_format_report_text() {
        let report = ComplianceReport::new("test", WCAGLevel::AA);
        let text = format_report(&report, "text").expect("TODO: handle error");
        assert!(text.contains("test"));
        assert!(text.contains("PASS"));
    }

    #[test]
    fn test_format_report_json() {
        let report = ComplianceReport::new("test", WCAGLevel::AA);
        let json = format_report(&report, "json").expect("TODO: handle error");
        assert!(json.contains("\"project_name\""));
    }

    #[test]
    fn test_format_report_a2ml() {
        let report = ComplianceReport::new("test", WCAGLevel::AA);
        let a2ml = format_report(&report, "a2ml").expect("TODO: handle error");
        assert!(a2ml.contains("(compliance-report"));
        assert!(a2ml.contains("(project \"test\")"));
    }
}
