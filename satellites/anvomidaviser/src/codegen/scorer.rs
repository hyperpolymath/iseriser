// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// ISU base value and GOE scoring calculator for anvomidaviser.
//
// Calculates base values for all ISU figure skating elements using the
// 2024-2025 ISU Scale of Values (SOV). Base values are defined per element
// and rotation count. GOE adjustments are calculated as a percentage of
// the base value (10% per GOE step).
//
// Reference: ISU Communication 2599 — Scale of Values, 2024-2025 season.

use crate::abi::{ElementCode, GOE, Jump, JumpType, Spin, SpinType, StepSequence, StepType};

/// Calculate the base value for any ISU element code.
///
/// Returns the base value in points according to the ISU 2024-2025
/// Scale of Values. Jump combinations sum their individual jump base values.
pub fn base_value(element: &ElementCode) -> f64 {
    match element {
        ElementCode::SoloJump(jump) => jump_base_value(jump),
        ElementCode::JumpCombination(jumps) => jumps.iter().map(jump_base_value).sum(),
        ElementCode::JumpSequence(jumps) => {
            // Jump sequences receive 80% of the combined base value
            let total: f64 = jumps.iter().map(jump_base_value).sum();
            (total * 0.8 * 100.0).round() / 100.0
        }
        ElementCode::Spin(spin) => spin_base_value(spin),
        ElementCode::Step(step) => step_base_value(step),
    }
}

/// Calculate the GOE adjustment for an element given its base value and GOE.
///
/// Each GOE step is 10% of the base value (ISU 2024-2025 rules).
/// The result is rounded to 2 decimal places.
pub fn goe_adjustment(base: f64, goe: GOE) -> f64 {
    let adjustment = base * goe.factor();
    (adjustment * 100.0).round() / 100.0
}

/// Base value for a single jump element, based on rotation count and type.
///
/// Values from ISU Scale of Values 2024-2025 season.
/// Note: These are the clean (non-under-rotated, non-downgraded) values.
fn jump_base_value(jump: &Jump) -> f64 {
    match (jump.rotations, jump.jump_type) {
        // Singles
        (1, JumpType::Toeloop) => 0.40,
        (1, JumpType::Salchow) => 0.40,
        (1, JumpType::Loop) => 0.50,
        (1, JumpType::Flip) => 0.50,
        (1, JumpType::Lutz) => 0.60,
        (1, JumpType::Axel) => 1.10,

        // Doubles
        (2, JumpType::Toeloop) => 1.30,
        (2, JumpType::Salchow) => 1.30,
        (2, JumpType::Loop) => 1.70,
        (2, JumpType::Flip) => 1.80,
        (2, JumpType::Lutz) => 2.10,
        (2, JumpType::Axel) => 3.30,

        // Triples
        (3, JumpType::Toeloop) => 4.20,
        (3, JumpType::Salchow) => 4.30,
        (3, JumpType::Loop) => 4.90,
        (3, JumpType::Flip) => 5.30,
        (3, JumpType::Lutz) => 5.90,
        (3, JumpType::Axel) => 8.00,

        // Quads
        (4, JumpType::Toeloop) => 9.50,
        (4, JumpType::Salchow) => 9.70,
        (4, JumpType::Loop) => 10.50,
        (4, JumpType::Flip) => 11.00,
        (4, JumpType::Lutz) => 11.50,
        (4, JumpType::Axel) => 12.50,

        // Fallback for unexpected rotation counts
        _ => 0.0,
    }
}

/// Base value for a spin element, based on type and level.
///
/// Values from ISU Scale of Values 2024-2025 season.
fn spin_base_value(spin: &Spin) -> f64 {
    // Base values vary by spin type and level (0-4).
    // Simplified table covering the most common spins.

    match &spin.spin_type {
        SpinType::Single(_) => match spin.level {
            0 => 0.00, // No base value for level 0 (base level)
            1 => 1.20,
            2 => 1.50,
            3 => 1.90,
            4 => 2.40,
            _ => 0.00,
        },
        SpinType::Combination => match spin.level {
            0 => 0.00,
            1 => 1.70,
            2 => 2.00,
            3 => 2.50,
            4 => 3.00,
            _ => 0.00,
        },
        SpinType::Flying(_) => match spin.level {
            0 => 0.00,
            1 => 1.70,
            2 => 2.00,
            3 => 2.50,
            4 => 3.00,
            _ => 0.00,
        },
        SpinType::ChangeFootCombination => match spin.level {
            0 => 0.00,
            1 => 1.70,
            2 => 2.50,
            3 => 3.00,
            4 => 3.50,
            _ => 0.00,
        },
    }
}

/// Base value for a step or choreographic sequence, based on type and level.
///
/// Values from ISU Scale of Values 2024-2025 season.
fn step_base_value(step: &StepSequence) -> f64 {
    match step.step_type {
        StepType::StepSequence => match step.level {
            1 => 1.80,
            2 => 2.60,
            3 => 3.30,
            4 => 3.90,
            _ => 0.00,
        },
        StepType::ChoreographicSequence => {
            // ChSq always has a fixed base value regardless of "level"
            3.00
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::abi::SpinType;

    #[test]
    fn test_triple_lutz_base_value() {
        let jump = Jump::new(3, JumpType::Lutz);
        assert!((jump_base_value(&jump) - 5.90).abs() < f64::EPSILON);
    }

    #[test]
    fn test_double_axel_base_value() {
        let jump = Jump::new(2, JumpType::Axel);
        assert!((jump_base_value(&jump) - 3.30).abs() < f64::EPSILON);
    }

    #[test]
    fn test_quad_toeloop_base_value() {
        let jump = Jump::new(4, JumpType::Toeloop);
        assert!((jump_base_value(&jump) - 9.50).abs() < f64::EPSILON);
    }

    #[test]
    fn test_combination_base_value() {
        // 3Lz+3T = 5.90 + 4.20 = 10.10
        let combo = ElementCode::JumpCombination(vec![
            Jump::new(3, JumpType::Lutz),
            Jump::new(3, JumpType::Toeloop),
        ]);
        assert!((base_value(&combo) - 10.10).abs() < 0.01);
    }

    #[test]
    fn test_jump_sequence_base_value() {
        // 2A+2T+SEQ = (3.30 + 1.30) * 0.8 = 3.68
        let seq = ElementCode::JumpSequence(vec![
            Jump::new(2, JumpType::Axel),
            Jump::new(2, JumpType::Toeloop),
        ]);
        assert!((base_value(&seq) - 3.68).abs() < 0.01);
    }

    #[test]
    fn test_spin_ccosp4_base_value() {
        let spin = Spin::new(SpinType::ChangeFootCombination, 4);
        assert!((spin_base_value(&spin) - 3.50).abs() < f64::EPSILON);
    }

    #[test]
    fn test_step_sequence_level3_base_value() {
        let step = StepSequence::new(StepType::StepSequence, 3);
        assert!((step_base_value(&step) - 3.30).abs() < f64::EPSILON);
    }

    #[test]
    fn test_choreographic_sequence_base_value() {
        let step = StepSequence::new(StepType::ChoreographicSequence, 1);
        assert!((step_base_value(&step) - 3.00).abs() < f64::EPSILON);
    }

    #[test]
    fn test_goe_positive_adjustment() {
        // Base 5.90, GOE +3 → 5.90 * 0.30 = 1.77
        let adj = goe_adjustment(5.90, GOE::new(3));
        assert!((adj - 1.77).abs() < 0.01);
    }

    #[test]
    fn test_goe_negative_adjustment() {
        // Base 5.90, GOE -2 → 5.90 * -0.20 = -1.18
        let adj = goe_adjustment(5.90, GOE::new(-2));
        assert!((adj - (-1.18)).abs() < 0.01);
    }

    #[test]
    fn test_all_single_jump_values_increase_with_rotation() {
        // For each jump type, higher rotations should mean higher base value
        for jt in [
            JumpType::Toeloop,
            JumpType::Salchow,
            JumpType::Loop,
            JumpType::Flip,
            JumpType::Lutz,
            JumpType::Axel,
        ] {
            let mut prev = 0.0;
            for rot in 1..=4 {
                let val = jump_base_value(&Jump::new(rot, jt));
                assert!(
                    val > prev,
                    "{}{} ({:.2}) should be > {:.2}",
                    rot,
                    jt.code(),
                    val,
                    prev
                );
                prev = val;
            }
        }
    }
}
