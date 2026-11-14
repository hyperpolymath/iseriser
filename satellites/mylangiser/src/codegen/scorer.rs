// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Complexity scorer for mylangiser — calculates a 0-100 complexity score
// for each API endpoint based on weighted factors:
//   - Total parameter count (weight: 30%)
//   - Optional-to-total parameter ratio (weight: 25%)
//   - Type complexity (compound types like map/list) (weight: 25%)
//   - Required parameter count (weight: 20%)
//
// The score determines the disclosure level: beginner, intermediate, or expert.

use crate::abi::{ComplexityScore, DisclosureLevel};
use crate::codegen::parser::parse_endpoint_params;
use crate::manifest::{EndpointDef, LevelConfig};

/// Weighting constants for the complexity formula.
/// These are tuned so that a simple 2-param function scores low (~15)
/// and a 7-param function with maps and lists scores high (~75+).
const WEIGHT_PARAM_COUNT: f64 = 0.30;
const WEIGHT_OPTIONAL_RATIO: f64 = 0.25;
const WEIGHT_TYPE_COMPLEXITY: f64 = 0.25;
const WEIGHT_REQUIRED_COUNT: f64 = 0.20;

/// Maximum parameter count used for normalisation. Functions with more
/// params than this are capped at 1.0 for this factor.
const MAX_PARAM_COUNT: f64 = 10.0;

/// Maximum type complexity sum used for normalisation. A function where
/// every param is a map (weight 3) with 10 params would hit 30.
const MAX_TYPE_COMPLEXITY: f64 = 20.0;

/// Maximum required count for normalisation.
const MAX_REQUIRED_COUNT: f64 = 8.0;

/// Calculate the complexity score (0-100) for a single endpoint.
///
/// The score is a weighted combination of four factors, each normalised
/// to the 0.0-1.0 range and then scaled to 0-100:
///
/// 1. **Parameter count** — more parameters = more complex
/// 2. **Optional ratio** — higher ratio of optional params = more complex
///    (because the caller must understand what can be omitted)
/// 3. **Type complexity** — compound types (map, list) add more complexity
///    than scalar types (string, int, bool)
/// 4. **Required count** — more required params = higher cognitive load
pub fn score_endpoint(endpoint: &EndpointDef) -> ComplexityScore {
    let params = parse_endpoint_params(endpoint);

    if params.is_empty() {
        return ComplexityScore { value: 0 };
    }

    let total = params.len() as f64;
    let optional_count = params.iter().filter(|p| p.optional).count() as f64;
    let required_count = total - optional_count;
    let type_complexity_sum: f64 = params
        .iter()
        .map(|p| p.param_type.complexity_weight() as f64)
        .sum();

    // Normalise each factor to 0.0-1.0 range, capping at 1.0.
    let param_factor = (total / MAX_PARAM_COUNT).min(1.0);
    let optional_factor = if total > 0.0 {
        optional_count / total
    } else {
        0.0
    };
    let type_factor = (type_complexity_sum / MAX_TYPE_COMPLEXITY).min(1.0);
    let required_factor = (required_count / MAX_REQUIRED_COUNT).min(1.0);

    // Weighted combination scaled to 0-100.
    let raw_score = (param_factor * WEIGHT_PARAM_COUNT
        + optional_factor * WEIGHT_OPTIONAL_RATIO
        + type_factor * WEIGHT_TYPE_COMPLEXITY
        + required_factor * WEIGHT_REQUIRED_COUNT)
        * 100.0;

    // Clamp to valid range.
    let clamped = raw_score.round().min(100.0).max(0.0) as u32;

    ComplexityScore { value: clamped }
}

/// Determine the disclosure level for a given complexity score using
/// the manifest's level thresholds.
///
/// - score <= beginner_threshold => Beginner
/// - score >= expert_threshold   => Expert
/// - otherwise                   => Intermediate
pub fn assign_level(score: &ComplexityScore, levels: &LevelConfig) -> DisclosureLevel {
    if score.value <= levels.beginner_threshold {
        DisclosureLevel::Beginner
    } else if score.value >= levels.expert_threshold {
        DisclosureLevel::Expert
    } else {
        DisclosureLevel::Intermediate
    }
}

/// Score all endpoints in a manifest and return them paired with their
/// complexity scores and assigned disclosure levels.
pub fn score_all_endpoints(
    endpoints: &[EndpointDef],
    levels: &LevelConfig,
) -> Vec<(String, ComplexityScore, DisclosureLevel)> {
    endpoints
        .iter()
        .map(|ep| {
            let score = score_endpoint(ep);
            let level = assign_level(&score, levels);
            (ep.name.clone(), score, level)
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::manifest::EndpointDef;

    /// A simple 2-param endpoint (both required, scalar types) should
    /// score well below 30 — firmly in the beginner tier.
    #[test]
    fn test_simple_endpoint_scores_low() {
        let ep = EndpointDef {
            name: "ping".to_string(),
            params: vec!["host: string".to_string(), "timeout: int".to_string()],
            required: vec!["host".to_string(), "timeout".to_string()],
            description: String::new(),
        };
        let score = score_endpoint(&ep);
        assert!(
            score.value <= 30,
            "simple 2-param endpoint should be beginner-level, got {}",
            score.value
        );
    }

    /// A complex 7-param endpoint with maps, lists, and many optional
    /// params should score above 50 — intermediate or expert tier.
    #[test]
    fn test_complex_endpoint_scores_high() {
        let ep = EndpointDef {
            name: "search".to_string(),
            params: vec![
                "query: string".to_string(),
                "filters?: map".to_string(),
                "sort?: string".to_string(),
                "page?: int".to_string(),
                "limit?: int".to_string(),
                "cursor?: string".to_string(),
                "facets?: list".to_string(),
            ],
            required: vec!["query".to_string()],
            description: String::new(),
        };
        let score = score_endpoint(&ep);
        assert!(
            score.value > 50,
            "complex 7-param endpoint should be intermediate+, got {}",
            score.value
        );
    }

    #[test]
    fn test_level_assignment_beginner() {
        let levels = LevelConfig::default();
        let score = ComplexityScore { value: 20 };
        assert_eq!(assign_level(&score, &levels), DisclosureLevel::Beginner);
    }

    #[test]
    fn test_level_assignment_intermediate() {
        let levels = LevelConfig::default();
        let score = ComplexityScore { value: 50 };
        assert_eq!(assign_level(&score, &levels), DisclosureLevel::Intermediate);
    }

    #[test]
    fn test_level_assignment_expert() {
        let levels = LevelConfig::default();
        let score = ComplexityScore { value: 85 };
        assert_eq!(assign_level(&score, &levels), DisclosureLevel::Expert);
    }
}
