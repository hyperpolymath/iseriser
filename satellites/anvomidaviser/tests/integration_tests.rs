// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Integration tests for anvomidaviser — validates end-to-end parsing,
// ISU rule checking, and scoring for realistic figure skating programs.

use anvomidaviser::abi::*;
use anvomidaviser::codegen::parser;
use anvomidaviser::codegen::scorer;
use anvomidaviser::codegen::validator;

// ---------------------------------------------------------------------------
// Parser tests — ISU element code parsing
// ---------------------------------------------------------------------------

#[test]
fn test_parse_jump_solo_all_types() {
    // Verify all six jump types parse correctly as solo jumps
    let test_cases = vec![
        ("3T", 3, JumpType::Toeloop),
        ("3S", 3, JumpType::Salchow),
        ("3Lo", 3, JumpType::Loop),
        ("3F", 3, JumpType::Flip),
        ("3Lz", 3, JumpType::Lutz),
        ("2A", 2, JumpType::Axel),
    ];

    for (code, expected_rot, expected_type) in test_cases {
        let elem = parser::parse_element(code)
            .unwrap_or_else(|e| panic!("Failed to parse '{}': {}", code, e));
        match elem {
            ElementCode::SoloJump(j) => {
                assert_eq!(j.rotations, expected_rot, "Wrong rotations for '{}'", code);
                assert_eq!(j.jump_type, expected_type, "Wrong jump type for '{}'", code);
            }
            _ => panic!("Expected SoloJump for '{}', got {:?}", code, elem),
        }
    }
}

#[test]
fn test_parse_jump_all_rotations() {
    // Single, double, triple, and quad of each jump type
    for rot in 1..=4u8 {
        for (code_suffix, jt) in [
            ("T", JumpType::Toeloop),
            ("S", JumpType::Salchow),
            ("Lo", JumpType::Loop),
            ("F", JumpType::Flip),
            ("Lz", JumpType::Lutz),
            ("A", JumpType::Axel),
        ] {
            let code = format!("{}{}", rot, code_suffix);
            let elem = parser::parse_element(&code)
                .unwrap_or_else(|e| panic!("Failed to parse '{}': {}", code, e));
            match elem {
                ElementCode::SoloJump(j) => {
                    assert_eq!(j.rotations, rot);
                    assert_eq!(j.jump_type, jt);
                }
                _ => panic!("Expected SoloJump for '{}'", code),
            }
        }
    }
}

#[test]
fn test_parse_combination_two_jumps() {
    let elem = parser::parse_element("3Lz+3T").unwrap();
    match elem {
        ElementCode::JumpCombination(jumps) => {
            assert_eq!(jumps.len(), 2);
            assert_eq!(jumps[0].rotations, 3);
            assert_eq!(jumps[0].jump_type, JumpType::Lutz);
            assert_eq!(jumps[1].rotations, 3);
            assert_eq!(jumps[1].jump_type, JumpType::Toeloop);
        }
        _ => panic!("Expected JumpCombination"),
    }
}

#[test]
fn test_parse_combination_three_jumps() {
    let elem = parser::parse_element("3F+2T+2Lo").unwrap();
    match elem {
        ElementCode::JumpCombination(jumps) => {
            assert_eq!(jumps.len(), 3);
            assert_eq!(jumps[2].jump_type, JumpType::Loop);
        }
        _ => panic!("Expected JumpCombination"),
    }
}

// ---------------------------------------------------------------------------
// Zayak rule tests
// ---------------------------------------------------------------------------

#[test]
fn test_zayak_rule_three_triple_lutzes_violates() {
    // Three 3Lz across different element types should trigger Zayak
    let elements = vec![
        ElementCode::SoloJump(Jump::new(3, JumpType::Lutz)),
        ElementCode::JumpCombination(vec![
            Jump::new(3, JumpType::Lutz),
            Jump::new(2, JumpType::Toeloop),
        ]),
        ElementCode::SoloJump(Jump::new(3, JumpType::Lutz)),
    ];

    let violations = validator::validate_program(&elements, Segment::Free);
    let zayak = violations.iter().find(|v| {
        matches!(
            v,
            Violation::ZayakRule {
                jump_type: JumpType::Lutz,
                ..
            }
        )
    });
    assert!(zayak.is_some(), "Expected Zayak violation for triple Lutz");

    if let Some(Violation::ZayakRule { count, .. }) = zayak {
        assert_eq!(*count, 3);
    }
}

#[test]
fn test_zayak_rule_two_triple_lutzes_passes() {
    let elements = vec![
        ElementCode::SoloJump(Jump::new(3, JumpType::Lutz)),
        ElementCode::JumpCombination(vec![
            Jump::new(3, JumpType::Lutz),
            Jump::new(2, JumpType::Toeloop),
        ]),
    ];

    let violations = validator::validate_program(&elements, Segment::Free);
    assert!(
        !violations
            .iter()
            .any(|v| matches!(v, Violation::ZayakRule { .. })),
        "Two triple Lutzes should not trigger Zayak"
    );
}

#[test]
fn test_zayak_rule_ignores_doubles() {
    // Doubles are exempt from the Zayak rule
    let elements = vec![
        ElementCode::SoloJump(Jump::new(2, JumpType::Toeloop)),
        ElementCode::SoloJump(Jump::new(2, JumpType::Toeloop)),
        ElementCode::SoloJump(Jump::new(2, JumpType::Toeloop)),
        ElementCode::SoloJump(Jump::new(2, JumpType::Toeloop)),
    ];

    let violations = validator::validate_program(&elements, Segment::Free);
    assert!(
        !violations
            .iter()
            .any(|v| matches!(v, Violation::ZayakRule { .. })),
        "Doubles should not trigger Zayak rule"
    );
}

// ---------------------------------------------------------------------------
// Base value tests
// ---------------------------------------------------------------------------

#[test]
fn test_base_values_triple_lutz() {
    let elem = ElementCode::SoloJump(Jump::new(3, JumpType::Lutz));
    assert!((scorer::base_value(&elem) - 5.90).abs() < f64::EPSILON);
}

#[test]
fn test_base_values_double_axel() {
    let elem = ElementCode::SoloJump(Jump::new(2, JumpType::Axel));
    assert!((scorer::base_value(&elem) - 3.30).abs() < f64::EPSILON);
}

#[test]
fn test_base_values_combination_3lz_3t() {
    // 3Lz+3T = 5.90 + 4.20 = 10.10
    let elem = ElementCode::JumpCombination(vec![
        Jump::new(3, JumpType::Lutz),
        Jump::new(3, JumpType::Toeloop),
    ]);
    assert!((scorer::base_value(&elem) - 10.10).abs() < 0.01);
}

#[test]
fn test_base_values_spin_ccosp4() {
    let elem = ElementCode::Spin(Spin::new(SpinType::ChangeFootCombination, 4));
    assert!((scorer::base_value(&elem) - 3.50).abs() < f64::EPSILON);
}

#[test]
fn test_base_values_step_sequence_level3() {
    let elem = ElementCode::Step(StepSequence::new(StepType::StepSequence, 3));
    assert!((scorer::base_value(&elem) - 3.30).abs() < f64::EPSILON);
}

// ---------------------------------------------------------------------------
// Element count limit tests
// ---------------------------------------------------------------------------

#[test]
fn test_element_count_limit_free_skate_7_jumps_ok() {
    let mut elements: Vec<ElementCode> = (0..7)
        .map(|i| {
            let jt = match i % 6 {
                0 => JumpType::Toeloop,
                1 => JumpType::Salchow,
                2 => JumpType::Loop,
                3 => JumpType::Flip,
                4 => JumpType::Lutz,
                _ => JumpType::Axel,
            };
            ElementCode::SoloJump(Jump::new(2, jt))
        })
        .collect();
    // Add required spins and steps
    elements.push(ElementCode::Spin(Spin::new(
        SpinType::ChangeFootCombination,
        4,
    )));
    elements.push(ElementCode::Spin(Spin::new(SpinType::Combination, 3)));
    elements.push(ElementCode::Spin(Spin::new(
        SpinType::Flying(SpinPosition::Sit),
        3,
    )));
    elements.push(ElementCode::Step(StepSequence::new(
        StepType::StepSequence,
        3,
    )));

    let violations = validator::validate_program(&elements, Segment::Free);
    assert!(
        !violations
            .iter()
            .any(|v| matches!(v, Violation::TooManyJumpElements { .. })),
        "7 jumps in free skate should be valid"
    );
}

#[test]
fn test_element_count_limit_free_skate_8_jumps_violates() {
    let elements: Vec<ElementCode> = (0..8)
        .map(|i| {
            let jt = match i % 6 {
                0 => JumpType::Toeloop,
                1 => JumpType::Salchow,
                2 => JumpType::Loop,
                3 => JumpType::Flip,
                4 => JumpType::Lutz,
                _ => JumpType::Axel,
            };
            ElementCode::SoloJump(Jump::new(2, jt))
        })
        .collect();

    let violations = validator::validate_program(&elements, Segment::Free);
    assert!(
        violations.iter().any(|v| matches!(
            v,
            Violation::TooManyJumpElements {
                found: 8,
                maximum: 7
            }
        )),
        "8 jumps in free skate should violate"
    );
}

#[test]
fn test_element_count_limit_short_program() {
    // Short program allows max 3 jump elements
    let elements = vec![
        ElementCode::SoloJump(Jump::new(3, JumpType::Lutz)),
        ElementCode::SoloJump(Jump::new(3, JumpType::Flip)),
        ElementCode::SoloJump(Jump::new(2, JumpType::Axel)),
        ElementCode::SoloJump(Jump::new(2, JumpType::Toeloop)), // 4th jump — violates
    ];

    let violations = validator::validate_program(&elements, Segment::Short);
    assert!(
        violations.iter().any(|v| matches!(
            v,
            Violation::TooManyJumpElements {
                found: 4,
                maximum: 3
            }
        )),
        "4 jumps in short program should violate"
    );
}

// ---------------------------------------------------------------------------
// Full program end-to-end test
// ---------------------------------------------------------------------------

#[test]
fn test_full_free_skate_program_parsing_and_scoring() {
    // A realistic senior women's free skate program (simplified)
    let codes = vec![
        "3Lz+3T".to_string(),     // Jump combination
        "3F".to_string(),         // Solo jump
        "CCoSp4".to_string(),     // Change foot combination spin
        "StSq3".to_string(),      // Step sequence
        "3Lo".to_string(),        // Solo jump
        "2A+2T".to_string(),      // Jump combination
        "3S".to_string(),         // Solo jump
        "FSSp3".to_string(),      // Flying sit spin
        "2A".to_string(),         // Solo jump (double Axel)
        "3Lz+2T+2Lo".to_string(), // Triple combination
        "CoSp4".to_string(),      // Combination spin
        "ChSq1".to_string(),      // Choreographic sequence
    ];

    // Parse all elements
    let elements = parser::parse_program(&codes).unwrap();
    assert_eq!(elements.len(), 12);

    // Count element types
    let jump_count = elements.iter().filter(|e| e.is_jump_element()).count();
    let spin_count = elements
        .iter()
        .filter(|e| matches!(e, ElementCode::Spin(_)))
        .count();
    let step_count = elements
        .iter()
        .filter(|e| matches!(e, ElementCode::Step(_)))
        .count();

    assert_eq!(jump_count, 7, "Should have 7 jump elements");
    assert_eq!(spin_count, 3, "Should have 3 spins");
    assert_eq!(step_count, 2, "Should have 2 step/choreo sequences");

    // Validate: should pass all rules
    let violations = validator::validate_program(&elements, Segment::Free);
    assert!(
        violations.is_empty(),
        "Realistic free skate should have no violations, got: {:?}",
        violations
    );

    // Calculate total base value
    let total_base: f64 = elements.iter().map(scorer::base_value).sum();
    // Expected: 3Lz+3T(10.10) + 3F(5.30) + CCoSp4(3.50) + StSq3(3.30) +
    //           3Lo(4.90) + 2A+2T(4.60) + 3S(4.30) + FSSp3(2.50) +
    //           2A(3.30) + 3Lz+2T+2Lo(9.70) + CoSp4(3.00) + ChSq1(3.00)
    assert!(
        total_base > 50.0,
        "Total base value should exceed 50 points, got {:.2}",
        total_base
    );
}

// ---------------------------------------------------------------------------
// Manifest loading test (requires a temp file)
// ---------------------------------------------------------------------------

#[test]
fn test_manifest_load_and_validate() {
    let manifest_content = r#"
[project]
name = "test-program"

[program]
discipline = "singles"
segment = "free"
level = "senior"

[[elements]]
code = "3Lz+3T"

[[elements]]
code = "3F"

[[elements]]
code = "CCoSp4"

[[elements]]
code = "StSq3"

[[elements]]
code = "2A"

[scoring]
goe-table = "2024-2025"
"#;

    let dir = tempfile::tempdir().unwrap();
    let manifest_path = dir.path().join("anvomidaviser.toml");
    std::fs::write(&manifest_path, manifest_content).unwrap();

    let m = anvomidaviser::load_manifest(manifest_path.to_str().unwrap()).unwrap();
    anvomidaviser::validate(&m).unwrap();

    assert_eq!(m.project.name, "test-program");
    assert_eq!(m.elements.len(), 5);
    assert_eq!(m.program.segment, Segment::Free);
    assert_eq!(m.program.discipline, Discipline::Singles);
}
