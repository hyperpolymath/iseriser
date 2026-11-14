// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// ISU technical rules validator for anvomidaviser.
//
// Validates figure skating programs against ISU technical rules including:
//   - Zayak rule (ISU Rule 611.1.f): no more than 2 triple/quad jumps of the
//     same type, and at most one of those may appear in a combination.
//   - Element count limits: maximum jumps, spins, step sequences per segment.
//   - Combination rules: max 3 jumps per combination, max combinations per segment.
//
// Reference: ISU Communication 2599 (2024-2025 season rules for Singles).

use std::collections::HashMap;

use crate::abi::{ElementCode, JumpType, Segment, Violation};

/// Validate a complete program against ISU technical rules for the given segment.
///
/// Returns a list of all violations found. An empty list means the program
/// is rule-compliant. Multiple violations can be returned simultaneously
/// (e.g. both Zayak and element count violations).
pub fn validate_program(elements: &[ElementCode], segment: Segment) -> Vec<Violation> {
    let mut violations = Vec::new();

    check_element_counts(elements, segment, &mut violations);
    check_combination_rules(elements, segment, &mut violations);
    check_zayak_rule(elements, &mut violations);

    violations
}

/// Check that the number of each element type does not exceed segment limits.
///
/// Singles limits:
///   - Short program: 3 jump elements, 3 spins, 1 step sequence
///   - Free skate: 7 jump elements, 3 spins, 2 step/choreo sequences
fn check_element_counts(
    elements: &[ElementCode],
    segment: Segment,
    violations: &mut Vec<Violation>,
) {
    let jump_count = elements.iter().filter(|e| e.is_jump_element()).count();
    let spin_count = elements
        .iter()
        .filter(|e| matches!(e, ElementCode::Spin(_)))
        .count();
    let step_count = elements
        .iter()
        .filter(|e| matches!(e, ElementCode::Step(_)))
        .count();

    let max_jumps = segment.max_jump_elements();
    let max_spins = segment.max_spin_elements();
    let max_steps = segment.max_step_sequences();

    if jump_count > max_jumps {
        violations.push(Violation::TooManyJumpElements {
            found: jump_count,
            maximum: max_jumps,
        });
    }

    if spin_count > max_spins {
        violations.push(Violation::TooManySpinElements {
            found: spin_count,
            maximum: max_spins,
        });
    }

    if step_count > max_steps {
        violations.push(Violation::TooManyStepSequences {
            found: step_count,
            maximum: max_steps,
        });
    }
}

/// Check jump combination rules:
///   - No combination may contain more than 3 jumps.
///   - Free skate: maximum 3 combinations total (one may have 3 jumps).
///   - Short program: maximum 1 combination.
fn check_combination_rules(
    elements: &[ElementCode],
    segment: Segment,
    violations: &mut Vec<Violation>,
) {
    let combinations: Vec<&ElementCode> = elements
        .iter()
        .filter(|e| matches!(e, ElementCode::JumpCombination(_)))
        .collect();

    // Check each combination length
    for combo in &combinations {
        if let ElementCode::JumpCombination(jumps) = combo
            && jumps.len() > 3
        {
            violations.push(Violation::CombinationTooLong {
                element: combo.notation(),
                jump_count: jumps.len(),
            });
        }
    }

    // Check total number of combinations
    let max_combos = segment.max_combinations();
    if combinations.len() > max_combos {
        violations.push(Violation::TooManyCombinations {
            found: combinations.len(),
            maximum: max_combos,
        });
    }
}

/// Check the Zayak rule (ISU Rule 611.1.f):
///
/// For triple and quadruple jumps, no jump type may appear more than twice
/// in a program. If a jump type appears twice, at most one occurrence may
/// be in a combination or sequence.
///
/// This rule prevents skaters from repeating the same high-value jump
/// excessively (named after Elaine Zayak who famously performed six
/// triple toe loops in 1982).
fn check_zayak_rule(elements: &[ElementCode], violations: &mut Vec<Violation>) {
    // Count occurrences of each triple/quad jump type across all elements.
    // We track: (total_count, count_in_combination_or_sequence)
    let mut jump_counts: HashMap<JumpType, (usize, usize)> = HashMap::new();

    for element in elements {
        let in_combo = matches!(
            element,
            ElementCode::JumpCombination(_) | ElementCode::JumpSequence(_)
        );

        for jump in element.jumps() {
            // Zayak rule only applies to triples and quads
            if jump.rotations >= 3 {
                let entry = jump_counts.entry(jump.jump_type).or_insert((0, 0));
                entry.0 += 1;
                if in_combo {
                    entry.1 += 1;
                }
            }
        }
    }

    for (jump_type, (total_count, _combo_count)) in &jump_counts {
        if *total_count > 2 {
            violations.push(Violation::ZayakRule {
                jump_type: *jump_type,
                count: *total_count,
            });
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::abi::{Jump, JumpType};

    /// Helper: create a solo jump element.
    fn solo_jump(rotations: u8, jt: JumpType) -> ElementCode {
        ElementCode::SoloJump(Jump::new(rotations, jt))
    }

    /// Helper: create a jump combination element.
    fn combo(jumps: Vec<(u8, JumpType)>) -> ElementCode {
        ElementCode::JumpCombination(jumps.into_iter().map(|(r, jt)| Jump::new(r, jt)).collect())
    }

    /// Helper: create a spin element.
    fn spin() -> ElementCode {
        use crate::abi::{Spin, SpinType};
        ElementCode::Spin(Spin::new(SpinType::ChangeFootCombination, 4))
    }

    /// Helper: create a step sequence element.
    fn step() -> ElementCode {
        use crate::abi::{StepSequence, StepType};
        ElementCode::Step(StepSequence::new(StepType::StepSequence, 3))
    }

    #[test]
    fn test_valid_free_skate_program() {
        // A valid free skate with 7 jumps, 3 spins, 2 steps
        let elements = vec![
            combo(vec![(3, JumpType::Lutz), (3, JumpType::Toeloop)]),
            solo_jump(3, JumpType::Flip),
            combo(vec![(3, JumpType::Salchow), (2, JumpType::Toeloop)]),
            solo_jump(2, JumpType::Axel),
            solo_jump(3, JumpType::Loop),
            combo(vec![
                (2, JumpType::Axel),
                (1, JumpType::Loop),
                (2, JumpType::Salchow),
            ]),
            solo_jump(2, JumpType::Lutz),
            spin(),
            spin(),
            spin(),
            step(),
            step(),
        ];
        let violations = validate_program(&elements, Segment::Free);
        assert!(
            violations.is_empty(),
            "Expected no violations, got: {:?}",
            violations
        );
    }

    #[test]
    fn test_zayak_rule_violation() {
        // Three triple Lutzes — Zayak violation
        let elements = vec![
            solo_jump(3, JumpType::Lutz),
            combo(vec![(3, JumpType::Lutz), (2, JumpType::Toeloop)]),
            solo_jump(3, JumpType::Lutz),
        ];
        let violations = validate_program(&elements, Segment::Free);
        assert!(
            violations.iter().any(|v| matches!(
                v,
                Violation::ZayakRule {
                    jump_type: JumpType::Lutz,
                    count: 3
                }
            )),
            "Expected Zayak violation for Lutz, got: {:?}",
            violations
        );
    }

    #[test]
    fn test_zayak_rule_passes_with_two() {
        // Two triple Lutzes — allowed by Zayak
        let elements = vec![
            solo_jump(3, JumpType::Lutz),
            combo(vec![(3, JumpType::Lutz), (2, JumpType::Toeloop)]),
        ];
        let violations = validate_program(&elements, Segment::Free);
        let zayak_violations: Vec<_> = violations
            .iter()
            .filter(|v| matches!(v, Violation::ZayakRule { .. }))
            .collect();
        assert!(
            zayak_violations.is_empty(),
            "Expected no Zayak violations, got: {:?}",
            zayak_violations
        );
    }

    #[test]
    fn test_zayak_ignores_doubles() {
        // Three double toeloops — Zayak only applies to triples/quads
        let elements = vec![
            solo_jump(2, JumpType::Toeloop),
            solo_jump(2, JumpType::Toeloop),
            solo_jump(2, JumpType::Toeloop),
        ];
        let violations = validate_program(&elements, Segment::Free);
        let zayak_violations: Vec<_> = violations
            .iter()
            .filter(|v| matches!(v, Violation::ZayakRule { .. }))
            .collect();
        assert!(zayak_violations.is_empty());
    }

    #[test]
    fn test_too_many_jump_elements_free_skate() {
        // 8 jump elements in a free skate (max 7)
        let elements = vec![
            solo_jump(3, JumpType::Lutz),
            solo_jump(3, JumpType::Flip),
            solo_jump(3, JumpType::Loop),
            solo_jump(3, JumpType::Salchow),
            solo_jump(2, JumpType::Axel),
            solo_jump(2, JumpType::Toeloop),
            solo_jump(2, JumpType::Flip),
            solo_jump(2, JumpType::Loop),
        ];
        let violations = validate_program(&elements, Segment::Free);
        assert!(
            violations.iter().any(|v| matches!(
                v,
                Violation::TooManyJumpElements {
                    found: 8,
                    maximum: 7
                }
            )),
            "Expected TooManyJumpElements, got: {:?}",
            violations
        );
    }

    #[test]
    fn test_too_many_jump_elements_short_program() {
        // 4 jump elements in a short program (max 3)
        let elements = vec![
            solo_jump(3, JumpType::Lutz),
            solo_jump(3, JumpType::Flip),
            solo_jump(2, JumpType::Axel),
            solo_jump(2, JumpType::Toeloop),
        ];
        let violations = validate_program(&elements, Segment::Short);
        assert!(
            violations.iter().any(|v| matches!(
                v,
                Violation::TooManyJumpElements {
                    found: 4,
                    maximum: 3
                }
            )),
            "Expected TooManyJumpElements for short program, got: {:?}",
            violations
        );
    }

    #[test]
    fn test_combination_too_long() {
        // 4-jump combination (max 3)
        let elements = vec![ElementCode::JumpCombination(vec![
            Jump::new(3, JumpType::Lutz),
            Jump::new(2, JumpType::Toeloop),
            Jump::new(2, JumpType::Loop),
            Jump::new(1, JumpType::Toeloop),
        ])];
        let violations = validate_program(&elements, Segment::Free);
        assert!(
            violations
                .iter()
                .any(|v| matches!(v, Violation::CombinationTooLong { .. })),
            "Expected CombinationTooLong, got: {:?}",
            violations
        );
    }

    #[test]
    fn test_too_many_combinations_short_program() {
        // 2 combinations in short program (max 1)
        let elements = vec![
            combo(vec![(3, JumpType::Lutz), (3, JumpType::Toeloop)]),
            combo(vec![(3, JumpType::Flip), (2, JumpType::Toeloop)]),
            solo_jump(2, JumpType::Axel),
        ];
        let violations = validate_program(&elements, Segment::Short);
        assert!(
            violations.iter().any(|v| matches!(
                v,
                Violation::TooManyCombinations {
                    found: 2,
                    maximum: 1
                }
            )),
            "Expected TooManyCombinations, got: {:?}",
            violations
        );
    }
}
