// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// ABI module for wokelangiser — core types representing consent states,
// WCAG accessibility levels, internationalisation strings, and compliance
// reporting structures. These mirror what the Idris2 ABI definitions would
// formally prove; the Rust types here are the runtime representation.

use serde::{Deserialize, Serialize};

// ---------------------------------------------------------------------------
// Consent
// ---------------------------------------------------------------------------

/// Represents the current state of user consent for a given category.
/// The state machine transitions are:
///   Pending -> OptIn  (user explicitly opts in)
///   Pending -> OptOut (user explicitly opts out, or default-state = "opt-out")
///   OptIn   -> OptOut (user revokes consent)
///   OptOut  -> OptIn  (user grants consent)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum ConsentState {
    /// User has explicitly granted consent.
    OptIn,
    /// User has explicitly denied consent (or it was never granted under opt-out default).
    OptOut,
    /// Consent has not yet been determined — no data collection is permitted.
    Pending,
}

impl ConsentState {
    /// Returns true if data collection is allowed under this consent state.
    /// Only `OptIn` permits collection; both `OptOut` and `Pending` block it.
    pub fn is_allowed(&self) -> bool {
        matches!(self, ConsentState::OptIn)
    }

    /// Transition the consent state based on an explicit user action.
    /// `grant == true` moves to OptIn, `grant == false` moves to OptOut.
    pub fn transition(&self, grant: bool) -> ConsentState {
        if grant {
            ConsentState::OptIn
        } else {
            ConsentState::OptOut
        }
    }
}

/// Categories of data collection that require separate consent.
/// Each category has its own independent ConsentState.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum ConsentCategory {
    /// Analytics and usage tracking (e.g. page views, click patterns).
    Analytics,
    /// Marketing and advertising (e.g. ad personalisation, retargeting).
    Marketing,
    /// Functional cookies/data (e.g. language preference, shopping cart).
    Functional,
    /// Custom category defined by the project.
    Custom(String),
}

impl ConsentCategory {
    /// Parse a category string into a ConsentCategory variant.
    /// Recognised strings: "analytics", "marketing", "functional".
    /// Anything else becomes Custom.
    #[allow(clippy::should_implement_trait)]
    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "analytics" => ConsentCategory::Analytics,
            "marketing" => ConsentCategory::Marketing,
            "functional" => ConsentCategory::Functional,
            other => ConsentCategory::Custom(other.to_string()),
        }
    }

    /// Return the canonical string name for this category.
    pub fn name(&self) -> &str {
        match self {
            ConsentCategory::Analytics => "analytics",
            ConsentCategory::Marketing => "marketing",
            ConsentCategory::Functional => "functional",
            ConsentCategory::Custom(s) => s.as_str(),
        }
    }
}

/// A consent gate wrapping a single data-collection point.
/// The gate blocks execution unless the associated consent state is OptIn.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConsentGate {
    /// Unique identifier for this gate (e.g. "analytics_pageview_tracker").
    pub id: String,
    /// Which consent category this gate belongs to.
    pub category: ConsentCategory,
    /// Current state of consent for this gate.
    pub state: ConsentState,
    /// Human-readable description of what data is collected.
    pub description: String,
    /// Whether GDPR compliance is required for this gate.
    pub gdpr_required: bool,
    /// Whether CCPA compliance is required for this gate.
    pub ccpa_required: bool,
}

// ---------------------------------------------------------------------------
// Accessibility (WCAG)
// ---------------------------------------------------------------------------

/// WCAG 2.2 conformance levels, from least to most stringent.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
pub enum WCAGLevel {
    /// Level A — minimum accessibility.
    A,
    /// Level AA — addresses the most common barriers (recommended baseline).
    AA,
    /// Level AAA — highest level of accessibility.
    AAA,
}

impl WCAGLevel {
    /// Parse a WCAG level string. Accepts "A", "AA", "AAA" (case-insensitive).
    #[allow(clippy::should_implement_trait)]
    pub fn from_str(s: &str) -> Option<Self> {
        match s.to_uppercase().as_str() {
            "A" => Some(WCAGLevel::A),
            "AA" => Some(WCAGLevel::AA),
            "AAA" => Some(WCAGLevel::AAA),
            _ => None,
        }
    }

    /// Minimum contrast ratio required for normal text at this WCAG level.
    /// - A: 3.0 (large text only, but we use it as floor)
    /// - AA: 4.5
    /// - AAA: 7.0
    pub fn min_contrast_ratio(&self) -> f64 {
        match self {
            WCAGLevel::A => 3.0,
            WCAGLevel::AA => 4.5,
            WCAGLevel::AAA => 7.0,
        }
    }
}

/// The kind of accessibility violation detected.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum ViolationKind {
    /// Foreground/background colour contrast is below the required ratio.
    InsufficientContrast,
    /// An <img> or equivalent element is missing alt text.
    MissingAltText,
    /// An interactive element is missing required ARIA attributes.
    MissingAriaLabel,
    /// A form input has no associated <label>.
    MissingFormLabel,
    /// Heading hierarchy is broken (e.g. h1 -> h3 with no h2).
    HeadingHierarchy,
    /// Keyboard navigation is not possible for an interactive element.
    KeyboardInaccessible,
    /// Custom violation type for project-specific checks.
    Custom(String),
}

/// A single accessibility violation found during analysis.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AccessibilityViolation {
    /// The kind of violation.
    pub kind: ViolationKind,
    /// WCAG level at which this violation is relevant.
    pub level: WCAGLevel,
    /// File path where the violation was found.
    pub file: String,
    /// Line number (1-based) where the violation was found, if known.
    pub line: Option<usize>,
    /// Human-readable description of the violation.
    pub message: String,
    /// WCAG success criterion reference (e.g. "1.4.3" for contrast).
    pub criterion: String,
}

// ---------------------------------------------------------------------------
// Internationalisation (i18n)
// ---------------------------------------------------------------------------

/// A locale identifier following BCP 47 (e.g. "en-GB", "fr-FR").
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Locale {
    /// The BCP 47 language tag (e.g. "en-GB").
    pub tag: String,
}

impl Locale {
    /// Create a new Locale from a BCP 47 tag string.
    pub fn new(tag: &str) -> Self {
        Locale {
            tag: tag.to_string(),
        }
    }

    /// Return the language subtag (e.g. "en" from "en-GB").
    pub fn language(&self) -> &str {
        self.tag.split('-').next().unwrap_or(&self.tag)
    }

    /// Return the region subtag if present (e.g. "GB" from "en-GB").
    pub fn region(&self) -> Option<&str> {
        let parts: Vec<&str> = self.tag.split('-').collect();
        if parts.len() > 1 {
            Some(parts[1])
        } else {
            None
        }
    }
}

/// A translatable string extracted from source code.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct I18nString {
    /// Unique key for this string (e.g. "login.button.label").
    pub key: String,
    /// The original string value in the default locale.
    pub default_value: String,
    /// File path where this string was found.
    pub source_file: String,
    /// Line number (1-based) where the string was found.
    pub line: usize,
    /// Optional context hint for translators.
    pub context: Option<String>,
}

/// A collection of translations for a single locale.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LocaleFile {
    /// The locale these translations belong to.
    pub locale: Locale,
    /// Key-value pairs of translated strings.
    pub translations: Vec<(String, String)>,
}

// ---------------------------------------------------------------------------
// Compliance Report
// ---------------------------------------------------------------------------

/// Severity of a finding in the compliance report.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub enum Severity {
    /// Informational note, no action required.
    Info,
    /// Warning — should be addressed but not blocking.
    Warning,
    /// Error — must be fixed for compliance.
    Error,
}

/// A single finding in the compliance report, covering consent, accessibility,
/// or internationalisation issues.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Finding {
    /// Severity of this finding.
    pub severity: Severity,
    /// Category label (e.g. "consent", "accessibility", "i18n").
    pub category: String,
    /// Human-readable message describing the finding.
    pub message: String,
    /// File path where the finding was located.
    pub file: Option<String>,
    /// Line number where the finding was located.
    pub line: Option<usize>,
}

/// The full compliance report aggregating all findings from consent analysis,
/// accessibility checks, and i18n extraction.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ComplianceReport {
    /// Name of the project that was analysed.
    pub project_name: String,
    /// All findings from the analysis.
    pub findings: Vec<Finding>,
    /// Total number of consent gates generated.
    pub consent_gates_count: usize,
    /// Total number of accessibility violations found.
    pub accessibility_violations_count: usize,
    /// Total number of i18n strings extracted.
    pub i18n_strings_count: usize,
    /// WCAG level that was checked against.
    pub wcag_level: WCAGLevel,
    /// Whether the project passes compliance at the configured level.
    pub passes: bool,
}

impl ComplianceReport {
    /// Create a new empty compliance report for the given project.
    pub fn new(project_name: &str, wcag_level: WCAGLevel) -> Self {
        ComplianceReport {
            project_name: project_name.to_string(),
            findings: Vec::new(),
            consent_gates_count: 0,
            accessibility_violations_count: 0,
            i18n_strings_count: 0,
            wcag_level,
            passes: true,
        }
    }

    /// Add a finding to the report. If the finding is an Error, the report
    /// is marked as not passing.
    pub fn add_finding(&mut self, finding: Finding) {
        if finding.severity == Severity::Error {
            self.passes = false;
        }
        self.findings.push(finding);
    }

    /// Return the count of findings at each severity level.
    pub fn summary(&self) -> (usize, usize, usize) {
        let errors = self
            .findings
            .iter()
            .filter(|f| f.severity == Severity::Error)
            .count();
        let warnings = self
            .findings
            .iter()
            .filter(|f| f.severity == Severity::Warning)
            .count();
        let infos = self
            .findings
            .iter()
            .filter(|f| f.severity == Severity::Info)
            .count();
        (errors, warnings, infos)
    }

    /// Format the report as plain text.
    pub fn to_text(&self) -> String {
        let mut out = String::new();
        out.push_str(&format!(
            "=== Compliance Report: {} ===\n",
            self.project_name
        ));
        out.push_str(&format!("WCAG Level: {:?}\n", self.wcag_level));
        out.push_str(&format!("Consent gates: {}\n", self.consent_gates_count));
        out.push_str(&format!(
            "Accessibility violations: {}\n",
            self.accessibility_violations_count
        ));
        out.push_str(&format!("I18n strings: {}\n", self.i18n_strings_count));
        let (errors, warnings, infos) = self.summary();
        out.push_str(&format!(
            "Findings: {} errors, {} warnings, {} info\n",
            errors, warnings, infos
        ));
        out.push_str(&format!(
            "Result: {}\n\n",
            if self.passes { "PASS" } else { "FAIL" }
        ));
        for finding in &self.findings {
            let loc = match (&finding.file, finding.line) {
                (Some(f), Some(l)) => format!("{}:{}", f, l),
                (Some(f), None) => f.clone(),
                _ => "unknown".to_string(),
            };
            out.push_str(&format!(
                "[{:?}] [{}] {} ({})\n",
                finding.severity, finding.category, finding.message, loc
            ));
        }
        out
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_consent_state_allowed() {
        assert!(ConsentState::OptIn.is_allowed());
        assert!(!ConsentState::OptOut.is_allowed());
        assert!(!ConsentState::Pending.is_allowed());
    }

    #[test]
    fn test_consent_state_transitions() {
        let pending = ConsentState::Pending;
        assert_eq!(pending.transition(true), ConsentState::OptIn);
        assert_eq!(pending.transition(false), ConsentState::OptOut);
        let opted_in = ConsentState::OptIn;
        assert_eq!(opted_in.transition(false), ConsentState::OptOut);
        let opted_out = ConsentState::OptOut;
        assert_eq!(opted_out.transition(true), ConsentState::OptIn);
    }

    #[test]
    fn test_consent_category_parsing() {
        assert_eq!(
            ConsentCategory::from_str("analytics"),
            ConsentCategory::Analytics
        );
        assert_eq!(
            ConsentCategory::from_str("MARKETING"),
            ConsentCategory::Marketing
        );
        assert_eq!(
            ConsentCategory::from_str("functional"),
            ConsentCategory::Functional
        );
        assert_eq!(
            ConsentCategory::from_str("telemetry"),
            ConsentCategory::Custom("telemetry".to_string())
        );
    }

    #[test]
    fn test_wcag_level_parsing() {
        assert_eq!(WCAGLevel::from_str("A"), Some(WCAGLevel::A));
        assert_eq!(WCAGLevel::from_str("aa"), Some(WCAGLevel::AA));
        assert_eq!(WCAGLevel::from_str("AAA"), Some(WCAGLevel::AAA));
        assert_eq!(WCAGLevel::from_str("B"), None);
    }

    #[test]
    fn test_wcag_contrast_ratios() {
        assert!((WCAGLevel::A.min_contrast_ratio() - 3.0).abs() < f64::EPSILON);
        assert!((WCAGLevel::AA.min_contrast_ratio() - 4.5).abs() < f64::EPSILON);
        assert!((WCAGLevel::AAA.min_contrast_ratio() - 7.0).abs() < f64::EPSILON);
    }

    #[test]
    fn test_locale_parsing() {
        let locale = Locale::new("en-GB");
        assert_eq!(locale.language(), "en");
        assert_eq!(locale.region(), Some("GB"));

        let lang_only = Locale::new("fr");
        assert_eq!(lang_only.language(), "fr");
        assert_eq!(lang_only.region(), None);
    }

    #[test]
    fn test_compliance_report_pass_fail() {
        let mut report = ComplianceReport::new("test-project", WCAGLevel::AA);
        assert!(report.passes);

        report.add_finding(Finding {
            severity: Severity::Warning,
            category: "accessibility".to_string(),
            message: "Consider adding aria-label".to_string(),
            file: Some("index.html".to_string()),
            line: Some(10),
        });
        assert!(report.passes); // warnings don't fail

        report.add_finding(Finding {
            severity: Severity::Error,
            category: "accessibility".to_string(),
            message: "Missing alt text".to_string(),
            file: Some("index.html".to_string()),
            line: Some(20),
        });
        assert!(!report.passes); // errors cause failure
    }
}
