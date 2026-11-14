// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Parser module for wokelangiser — analyses project source files to identify
// data collection points needing consent gates, UI elements requiring
// accessibility checks, and hardcoded strings needing internationalisation.

use anyhow::Result;
use std::path::Path;
use walkdir::WalkDir;

use crate::abi::{AccessibilityViolation, ConsentCategory, I18nString, ViolationKind, WCAGLevel};
use crate::manifest::Manifest;

// ---------------------------------------------------------------------------
// Consent point detection
// ---------------------------------------------------------------------------

/// A data collection point found in source code that requires a consent gate.
#[derive(Debug, Clone)]
pub struct ConsentPoint {
    /// File path where the consent point was found.
    pub file: String,
    /// Line number (1-based).
    pub line: usize,
    /// The code snippet containing the data collection call.
    pub snippet: String,
    /// Which consent category this collection falls under.
    pub category: ConsentCategory,
    /// Human-readable description of what data is being collected.
    pub description: String,
}

/// Patterns that indicate data collection requiring consent.
/// Each tuple is (pattern, category, description).
const CONSENT_PATTERNS: &[(&str, &str, &str)] = &[
    // Analytics patterns
    ("gtag(", "analytics", "Google Analytics tracking call"),
    ("analytics.track", "analytics", "Analytics tracking call"),
    ("trackEvent", "analytics", "Event tracking call"),
    ("pageview", "analytics", "Page view tracking"),
    ("sendBeacon", "analytics", "Beacon API data transmission"),
    ("_gaq.push", "analytics", "Legacy Google Analytics push"),
    ("mixpanel.track", "analytics", "Mixpanel tracking call"),
    ("plausible(", "analytics", "Plausible analytics call"),
    ("umami.track", "analytics", "Umami analytics call"),
    // Marketing patterns
    ("fbq(", "marketing", "Facebook pixel tracking"),
    ("twq(", "marketing", "Twitter pixel tracking"),
    ("lintrk(", "marketing", "LinkedIn Insight tag"),
    ("adsbygoogle", "marketing", "Google Ads tracking"),
    ("googletag", "marketing", "Google Ad Manager tag"),
    // Functional patterns
    ("localStorage.setItem", "functional", "Local storage write"),
    (
        "sessionStorage.setItem",
        "functional",
        "Session storage write",
    ),
    ("document.cookie", "functional", "Cookie access"),
    ("navigator.geolocation", "functional", "Geolocation access"),
    (
        "navigator.mediaDevices",
        "functional",
        "Media device access",
    ),
    (
        "Notification.requestPermission",
        "functional",
        "Notification permission request",
    ),
];

/// Scan all source files in the project for data collection points
/// that require consent gates.
pub fn find_consent_points(manifest: &Manifest) -> Result<Vec<ConsentPoint>> {
    let source_root = &manifest.project.source_root;
    let mut points = Vec::new();

    for entry in WalkDir::new(source_root)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| is_scannable_file(e.path()))
    {
        let path = entry.path();
        let content = match std::fs::read_to_string(path) {
            Ok(c) => c,
            Err(_) => continue, // skip binary/unreadable files
        };
        let file_str = path.to_string_lossy().to_string();

        for (line_num, line) in content.lines().enumerate() {
            for &(pattern, category, description) in CONSENT_PATTERNS {
                if line.contains(pattern) {
                    points.push(ConsentPoint {
                        file: file_str.clone(),
                        line: line_num + 1,
                        snippet: line.trim().to_string(),
                        category: ConsentCategory::from_str(category),
                        description: description.to_string(),
                    });
                }
            }
        }
    }

    Ok(points)
}

// ---------------------------------------------------------------------------
// Accessibility issue detection
// ---------------------------------------------------------------------------

/// Patterns that indicate accessibility issues in HTML/JSX/template files.
/// Each tuple is (pattern to find, what must also be present or absent, violation kind, message, criterion).
struct AccessibilityPattern {
    /// The tag or pattern to look for.
    trigger: &'static str,
    /// If this string is absent from the same element, it is a violation.
    required_attr: &'static str,
    /// The kind of violation produced.
    kind: ViolationKind,
    /// Human-readable message.
    message: &'static str,
    /// WCAG success criterion reference.
    criterion: &'static str,
    /// Minimum WCAG level at which this check applies.
    min_level: WCAGLevel,
}

/// Built-in accessibility patterns for HTML analysis.
const ACCESSIBILITY_PATTERNS: &[AccessibilityPattern] = &[
    AccessibilityPattern {
        trigger: "<img",
        required_attr: "alt=",
        kind: ViolationKind::MissingAltText,
        message: "Image element missing alt attribute",
        criterion: "1.1.1",
        min_level: WCAGLevel::A,
    },
    AccessibilityPattern {
        trigger: "<input",
        required_attr: "aria-label",
        kind: ViolationKind::MissingAriaLabel,
        message: "Input element missing aria-label or associated label",
        criterion: "1.3.1",
        min_level: WCAGLevel::A,
    },
    AccessibilityPattern {
        trigger: "<button",
        required_attr: "aria-label",
        kind: ViolationKind::MissingAriaLabel,
        message: "Button element missing accessible name (aria-label or text content)",
        criterion: "4.1.2",
        min_level: WCAGLevel::A,
    },
];

/// Scan all source files for accessibility violations at the given WCAG level.
pub fn find_accessibility_issues(
    manifest: &Manifest,
    wcag_level: WCAGLevel,
) -> Result<Vec<AccessibilityViolation>> {
    let source_root = &manifest.project.source_root;
    let mut violations = Vec::new();

    for entry in WalkDir::new(source_root)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| is_html_like(e.path()))
    {
        let path = entry.path();
        let content = match std::fs::read_to_string(path) {
            Ok(c) => c,
            Err(_) => continue,
        };
        let file_str = path.to_string_lossy().to_string();

        for (line_num, line) in content.lines().enumerate() {
            for pattern in ACCESSIBILITY_PATTERNS {
                // Only check patterns at or below our target level.
                if pattern.min_level > wcag_level {
                    continue;
                }
                if line.contains(pattern.trigger) && !line.contains(pattern.required_attr) {
                    // For <button>, also check if it has text content (non-self-closing).
                    if pattern.trigger == "<button"
                        && line.contains(">")
                        && line.contains("</button>")
                    {
                        let after_open = line.split('>').nth(1).unwrap_or("");
                        let text = after_open.split('<').next().unwrap_or("").trim();
                        if !text.is_empty() {
                            continue; // has text content, accessible
                        }
                    }
                    // For <input>, also check for id= with a corresponding <label for=>.
                    if pattern.trigger == "<input" && line.contains("id=") {
                        // We would need multi-line analysis for label association;
                        // for now, accept id= as potentially having a label.
                        continue;
                    }
                    violations.push(AccessibilityViolation {
                        kind: pattern.kind.clone(),
                        level: pattern.min_level,
                        file: file_str.clone(),
                        line: Some(line_num + 1),
                        message: pattern.message.to_string(),
                        criterion: pattern.criterion.to_string(),
                    });
                }
            }
        }
    }

    Ok(violations)
}

// ---------------------------------------------------------------------------
// i18n string extraction
// ---------------------------------------------------------------------------

/// Patterns that indicate hardcoded strings needing internationalisation.
/// We look for string literals in HTML text content, placeholder attributes,
/// title attributes, and JavaScript/ReScript string assignments to UI text.
///
/// This is a heuristic approach — it finds common patterns rather than doing
/// full AST parsing (which would require language-specific parsers).
pub fn extract_i18n_strings(manifest: &Manifest) -> Result<Vec<I18nString>> {
    let source_root = &manifest.project.source_root;
    let mut strings = Vec::new();
    let mut key_counter: usize = 0;

    for entry in WalkDir::new(source_root)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| is_scannable_file(e.path()))
    {
        let path = entry.path();
        let content = match std::fs::read_to_string(path) {
            Ok(c) => c,
            Err(_) => continue,
        };
        let file_str = path.to_string_lossy().to_string();

        for (line_num, line) in content.lines().enumerate() {
            let trimmed = line.trim();

            // Extract strings from HTML text content between tags.
            // Pattern: >Some visible text<
            for extracted in extract_html_text_content(trimmed) {
                if is_translatable(&extracted) {
                    key_counter += 1;
                    strings.push(I18nString {
                        key: format!("str_{}", key_counter),
                        default_value: extracted,
                        source_file: file_str.clone(),
                        line: line_num + 1,
                        context: None,
                    });
                }
            }

            // Extract strings from placeholder="..." and title="..." attributes.
            for attr in &["placeholder=\"", "title=\"", "aria-label=\"", "alt=\""] {
                if let Some(value) = extract_attribute_value(trimmed, attr)
                    && is_translatable(&value)
                {
                    key_counter += 1;
                    strings.push(I18nString {
                        key: format!("str_{}", key_counter),
                        default_value: value,
                        source_file: file_str.clone(),
                        line: line_num + 1,
                        context: Some(format!(
                            "{} attribute",
                            attr.trim_end_matches('"').trim_end_matches('=')
                        )),
                    });
                }
            }
        }
    }

    Ok(strings)
}

/// Extract text content from between HTML tags on a single line.
/// Returns all text segments found between > and < characters.
fn extract_html_text_content(line: &str) -> Vec<String> {
    let mut results = Vec::new();
    let mut rest = line;

    while let Some(gt_pos) = rest.find('>') {
        let after_gt = &rest[gt_pos + 1..];
        if let Some(lt_pos) = after_gt.find('<') {
            let text = after_gt[..lt_pos].trim();
            if !text.is_empty() {
                results.push(text.to_string());
            }
            rest = &after_gt[lt_pos..];
        } else {
            break;
        }
    }

    results
}

/// Extract the value of an HTML attribute from a line.
/// Looks for `attr_prefix` (e.g. `placeholder="`) and returns the content
/// up to the closing double quote.
fn extract_attribute_value(line: &str, attr_prefix: &str) -> Option<String> {
    if let Some(start) = line.find(attr_prefix) {
        let after = &line[start + attr_prefix.len()..];
        if let Some(end) = after.find('"') {
            let value = &after[..end];
            if !value.is_empty() {
                return Some(value.to_string());
            }
        }
    }
    None
}

/// Determine whether a string is likely user-facing and translatable.
/// Filters out code-like strings, very short strings, and technical identifiers.
fn is_translatable(s: &str) -> bool {
    // Must have at least 2 characters.
    if s.len() < 2 {
        return false;
    }
    // Must contain at least one letter.
    if !s.chars().any(|c| c.is_alphabetic()) {
        return false;
    }
    // Skip things that look like code: variable names, CSS classes, etc.
    if s.starts_with('{') || s.starts_with("//") || s.starts_with("/*") {
        return false;
    }
    // Skip single words that are likely technical (all lowercase, no spaces).
    if !s.contains(' ') && s.len() < 4 && s == s.to_lowercase() {
        return false;
    }
    true
}

// ---------------------------------------------------------------------------
// File type helpers
// ---------------------------------------------------------------------------

/// Returns true if the file is a type we should scan for consent/i18n patterns.
fn is_scannable_file(path: &Path) -> bool {
    let ext = path.extension().and_then(|e| e.to_str()).unwrap_or("");
    matches!(
        ext,
        "html" | "htm" | "jsx" | "tsx" | "js" | "mjs" | "res" | "svelte" | "vue" | "astro"
    )
}

/// Returns true if the file contains HTML-like content (for accessibility checks).
fn is_html_like(path: &Path) -> bool {
    let ext = path.extension().and_then(|e| e.to_str()).unwrap_or("");
    matches!(
        ext,
        "html" | "htm" | "jsx" | "tsx" | "svelte" | "vue" | "astro"
    )
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_extract_html_text_content() {
        let texts = extract_html_text_content("<p>Hello World</p>");
        assert_eq!(texts, vec!["Hello World"]);
    }

    #[test]
    fn test_extract_html_text_content_multiple() {
        let texts = extract_html_text_content("<h1>Title</h1><p>Body text</p>");
        assert_eq!(texts, vec!["Title", "Body text"]);
    }

    #[test]
    fn test_extract_attribute_value() {
        let val = extract_attribute_value(
            r#"<input placeholder="Enter your name" />"#,
            "placeholder=\"",
        );
        assert_eq!(val, Some("Enter your name".to_string()));
    }

    #[test]
    fn test_extract_attribute_value_missing() {
        let val = extract_attribute_value("<input />", "placeholder=\"");
        assert_eq!(val, None);
    }

    #[test]
    fn test_is_translatable_filters() {
        assert!(is_translatable("Hello World"));
        assert!(is_translatable("Click here"));
        assert!(!is_translatable("x")); // too short
        assert!(!is_translatable("123")); // no letters
        assert!(!is_translatable("{variable}")); // code-like
        assert!(!is_translatable("// comment")); // comment
    }

    #[test]
    fn test_consent_patterns_cover_all_categories() {
        let categories: Vec<&str> = CONSENT_PATTERNS.iter().map(|p| p.1).collect();
        assert!(categories.contains(&"analytics"));
        assert!(categories.contains(&"marketing"));
        assert!(categories.contains(&"functional"));
    }
}
