// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Integration tests for mylangiser — validates the full pipeline from
// manifest parsing through complexity scoring, level assignment, and
// layered wrapper generation.

use mylangiser::abi::{ComplexityScore, DisclosureLevel};
use mylangiser::codegen::layer_gen;
use mylangiser::codegen::scorer::{assign_level, score_all_endpoints, score_endpoint};
use mylangiser::manifest::{EndpointDef, LevelConfig, Manifest, ProjectConfig};
use std::collections::HashMap;

/// Helper: build a test manifest matching the simplified-api example.
fn simplified_api_manifest() -> Manifest {
    let mut defaults = HashMap::new();
    defaults.insert("role".to_string(), toml::Value::String("user".to_string()));
    defaults.insert("limit".to_string(), toml::Value::Integer(20));
    defaults.insert("page".to_string(), toml::Value::Integer(1));
    defaults.insert(
        "locale".to_string(),
        toml::Value::String("en-GB".to_string()),
    );

    Manifest {
        project: ProjectConfig {
            name: "simplified-api".to_string(),
            description: "Test API".to_string(),
        },
        endpoints: vec![
            EndpointDef {
                name: "create_user".to_string(),
                params: vec![
                    "username: string".to_string(),
                    "email: string".to_string(),
                    "role?: string".to_string(),
                    "permissions?: list".to_string(),
                    "mfa?: bool".to_string(),
                    "locale?: string".to_string(),
                ],
                required: vec!["username".to_string(), "email".to_string()],
                description: String::new(),
            },
            EndpointDef {
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
            },
            EndpointDef {
                name: "get_user".to_string(),
                params: vec!["user_id: string".to_string()],
                required: vec!["user_id".to_string()],
                description: String::new(),
            },
        ],
        levels: LevelConfig::default(),
        defaults,
    }
}

// ============================================================
// Complexity scoring tests
// ============================================================

/// Test that complexity scoring produces reasonable scores for endpoints
/// of varying complexity. A 1-param endpoint should score very low,
/// a 6-param endpoint should score moderate, and a 7-param endpoint
/// with compound types should score high.
#[test]
fn test_complexity_scoring() {
    let m = simplified_api_manifest();
    let scored = score_all_endpoints(&m.endpoints, &m.levels);

    // get_user (1 param, 1 required) should have the lowest score.
    let get_user = scored
        .iter()
        .find(|(name, _, _)| name == "get_user")
        .unwrap();
    // create_user (6 params, 2 required) should be moderate.
    let create_user = scored
        .iter()
        .find(|(name, _, _)| name == "create_user")
        .unwrap();
    // search (7 params with map+list, 1 required) should be highest.
    let search = scored.iter().find(|(name, _, _)| name == "search").unwrap();

    assert!(
        get_user.1.value < create_user.1.value,
        "get_user ({}) should score lower than create_user ({})",
        get_user.1.value,
        create_user.1.value
    );
    assert!(
        create_user.1.value < search.1.value,
        "create_user ({}) should score lower than search ({})",
        create_user.1.value,
        search.1.value
    );
}

// ============================================================
// Level assignment tests
// ============================================================

/// Test that disclosure level assignment correctly maps score ranges
/// to beginner/intermediate/expert tiers using default thresholds.
#[test]
fn test_level_assignment() {
    let levels = LevelConfig::default(); // beginner <= 30, expert >= 70

    // Boundary cases.
    assert_eq!(
        assign_level(&ComplexityScore { value: 0 }, &levels),
        DisclosureLevel::Beginner
    );
    assert_eq!(
        assign_level(&ComplexityScore { value: 30 }, &levels),
        DisclosureLevel::Beginner
    );
    assert_eq!(
        assign_level(&ComplexityScore { value: 31 }, &levels),
        DisclosureLevel::Intermediate
    );
    assert_eq!(
        assign_level(&ComplexityScore { value: 69 }, &levels),
        DisclosureLevel::Intermediate
    );
    assert_eq!(
        assign_level(&ComplexityScore { value: 70 }, &levels),
        DisclosureLevel::Expert
    );
    assert_eq!(
        assign_level(&ComplexityScore { value: 100 }, &levels),
        DisclosureLevel::Expert
    );
}

/// Test that a very simple endpoint (1 required param) is assigned
/// the beginner disclosure level.
#[test]
fn test_simple_endpoint_is_beginner() {
    let m = simplified_api_manifest();
    let get_user_ep = &m.endpoints[2]; // get_user
    let score = score_endpoint(get_user_ep);
    let level = assign_level(&score, &m.levels);
    assert_eq!(
        level,
        DisclosureLevel::Beginner,
        "get_user (1 param) should be beginner, score={}",
        score.value
    );
}

// ============================================================
// Beginner layer tests
// ============================================================

/// Test that the beginner layer only exposes required parameters.
/// For create_user, beginners should see (username, email) only.
#[test]
fn test_beginner_layer() {
    let m = simplified_api_manifest();
    let layers = layer_gen::generate_layers(&m);

    let create_user = layers
        .iter()
        .find(|l| l.endpoint_name == "create_user")
        .unwrap();

    // Beginner should only have 2 params (the required ones).
    assert_eq!(
        create_user.beginner_signature.len(),
        2,
        "beginner create_user should expose 2 required params, got {}",
        create_user.beginner_signature.len()
    );

    // Verify the beginner signature contains username and email.
    let sig_text = create_user.beginner_signature.join(", ");
    assert!(
        sig_text.contains("username"),
        "beginner should include 'username'"
    );
    assert!(
        sig_text.contains("email"),
        "beginner should include 'email'"
    );
    // Should NOT contain optional params.
    assert!(
        !sig_text.contains("permissions"),
        "beginner should not include 'permissions'"
    );
}

// ============================================================
// Expert layer tests
// ============================================================

/// Test that the expert layer exposes all parameters without restriction.
#[test]
fn test_expert_layer() {
    let m = simplified_api_manifest();
    let layers = layer_gen::generate_layers(&m);

    let create_user = layers
        .iter()
        .find(|l| l.endpoint_name == "create_user")
        .unwrap();

    // Expert should have all 6 params.
    assert_eq!(
        create_user.expert_signature.len(),
        6,
        "expert create_user should expose all 6 params, got {}",
        create_user.expert_signature.len()
    );

    let search = layers.iter().find(|l| l.endpoint_name == "search").unwrap();

    // Expert search should have all 7 params.
    assert_eq!(
        search.expert_signature.len(),
        7,
        "expert search should expose all 7 params, got {}",
        search.expert_signature.len()
    );
}

// ============================================================
// Smart defaults tests
// ============================================================

/// Test that smart defaults are correctly resolved from the manifest's
/// [defaults] section and applied to optional parameters.
#[test]
fn test_smart_defaults() {
    let m = simplified_api_manifest();
    let layers = layer_gen::generate_layers(&m);

    let create_user = layers
        .iter()
        .find(|l| l.endpoint_name == "create_user")
        .unwrap();

    // create_user has optional params: role, permissions, mfa, locale.
    // Of these, 'role' and 'locale' have entries in [defaults].
    let default_names: Vec<&str> = create_user
        .smart_defaults
        .iter()
        .map(|sd| sd.param_name.as_str())
        .collect();

    assert!(
        default_names.contains(&"role"),
        "should have smart default for 'role'"
    );
    assert!(
        default_names.contains(&"locale"),
        "should have smart default for 'locale'"
    );

    // Verify actual default values.
    let role_default = create_user
        .smart_defaults
        .iter()
        .find(|sd| sd.param_name == "role")
        .unwrap();
    assert_eq!(
        role_default.default_value, "\"user\"",
        "role default should be '\"user\"'"
    );

    let locale_default = create_user
        .smart_defaults
        .iter()
        .find(|sd| sd.param_name == "locale")
        .unwrap();
    assert_eq!(
        locale_default.default_value, "\"en-GB\"",
        "locale default should be '\"en-GB\"'"
    );

    // 'permissions' should NOT have a smart default (no entry in [defaults]).
    assert!(
        !default_names.contains(&"permissions"),
        "permissions should not have a smart default"
    );

    // search endpoint: 'limit' and 'page' should have defaults.
    let search = layers.iter().find(|l| l.endpoint_name == "search").unwrap();
    let search_default_names: Vec<&str> = search
        .smart_defaults
        .iter()
        .map(|sd| sd.param_name.as_str())
        .collect();
    assert!(
        search_default_names.contains(&"limit"),
        "search should have smart default for 'limit'"
    );
    assert!(
        search_default_names.contains(&"page"),
        "search should have smart default for 'page'"
    );

    let limit_default = search
        .smart_defaults
        .iter()
        .find(|sd| sd.param_name == "limit")
        .unwrap();
    assert_eq!(
        limit_default.default_value, "20",
        "limit default should be 20"
    );
}

// ============================================================
// Manifest loading test (from example file)
// ============================================================

/// Test that the example manifest file can be loaded and validated.
#[test]
fn test_load_example_manifest() {
    let m = mylangiser::load_manifest("examples/simplified-api/mylangiser.toml")
        .expect("should load example manifest");
    mylangiser::validate(&m).expect("example manifest should be valid");

    assert_eq!(m.project.name, "simplified-api");
    assert_eq!(m.endpoints.len(), 3);
    assert_eq!(m.levels.beginner_threshold, 30);
    assert_eq!(m.levels.expert_threshold, 70);
}

// ============================================================
// Full pipeline test
// ============================================================

/// Test the full generate pipeline: load manifest, score, and generate output.
#[test]
fn test_full_pipeline() {
    let output_dir = format!(
        "/tmp/mylangiser-test-{}",
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_millis()
    );

    mylangiser::generate("examples/simplified-api/mylangiser.toml", &output_dir)
        .expect("full pipeline should succeed");

    // Verify output structure.
    assert!(
        std::path::Path::new(&format!("{}/summary.txt", output_dir)).exists(),
        "summary.txt should exist"
    );
    assert!(
        std::path::Path::new(&format!("{}/beginner/create_user.mylang", output_dir)).exists(),
        "beginner/create_user.mylang should exist"
    );
    assert!(
        std::path::Path::new(&format!("{}/expert/search.mylang", output_dir)).exists(),
        "expert/search.mylang should exist"
    );

    // Clean up.
    let _ = std::fs::remove_dir_all(&output_dir);
}
