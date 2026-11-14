// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// ISU element code parser for anvomidaviser.
//
// Parses ISU figure skating element notation into structured types:
//   - Jumps: "3Lz", "2A", "4T", "1Lo"
//   - Combinations: "3Lz+3T", "3F+2T+2Lo"
//   - Sequences: "2A+2T+SEQ" (deprecated but still appears)
//   - Spins: "CCoSp4", "FSSp3", "USp2", "CSp4"
//   - Steps: "StSq3", "ChSq1"
//
// Reference: ISU Technical Panel Handbook (Single & Pair Skating), 2024-2025 season.

use anyhow::{Result, bail};

use crate::abi::{
    ElementCode, Jump, JumpType, Spin, SpinPosition, SpinType, StepSequence, StepType,
};

/// Parse a complete program's worth of ISU element codes.
///
/// Each code string is parsed independently. Returns all parsed elements
/// in program order (which matters for second-half bonus calculation).
///
/// # Errors
/// Returns an error if any element code is unparseable.
pub fn parse_program(codes: &[String]) -> Result<Vec<ElementCode>> {
    codes
        .iter()
        .enumerate()
        .map(|(i, code)| {
            parse_element(code.trim())
                .map_err(|e| anyhow::anyhow!("Element {} ('{}'): {}", i + 1, code, e))
        })
        .collect()
}

/// Parse a single ISU element code string into an ElementCode.
///
/// Recognises:
///   - Step sequences: codes starting with "StSq" or "ChSq"
///   - Spins: codes matching known spin prefixes (CCoSp, CoSp, FSSp, FCSp, FUSp, SSp, CSp, USp)
///   - Jump combinations/sequences: codes containing "+"
///   - Solo jumps: a digit followed by a jump type abbreviation
///
/// # Errors
/// Returns an error if the code does not match any known ISU element pattern.
pub fn parse_element(code: &str) -> Result<ElementCode> {
    if code.is_empty() {
        bail!("Empty element code");
    }

    // Try step sequences first (StSq, ChSq)
    if let Some(step) = try_parse_step(code) {
        return Ok(ElementCode::Step(step));
    }

    // Try spins (various prefixes ending with level digit)
    if let Some(spin) = try_parse_spin(code) {
        return Ok(ElementCode::Spin(spin));
    }

    // Try jump combinations/sequences (contain "+")
    if code.contains('+') {
        return parse_jump_combination(code);
    }

    // Try solo jump
    if let Some(jump) = try_parse_jump(code) {
        return Ok(ElementCode::SoloJump(jump));
    }

    bail!("Unrecognised element code: '{}'", code);
}

/// Attempt to parse a step sequence code (e.g. "StSq3", "ChSq1").
///
/// Returns None if the code does not match a step sequence pattern.
fn try_parse_step(code: &str) -> Option<StepSequence> {
    if let Some(rest) = code.strip_prefix("StSq") {
        let level = rest.parse::<u8>().ok()?;
        if level <= 4 {
            return Some(StepSequence::new(StepType::StepSequence, level));
        }
    }
    if let Some(rest) = code.strip_prefix("ChSq") {
        let level = rest.parse::<u8>().ok()?;
        if level <= 1 {
            return Some(StepSequence::new(StepType::ChoreographicSequence, level));
        }
    }
    None
}

/// Attempt to parse a spin code (e.g. "CCoSp4", "FSSp3", "CSp2").
///
/// Spin codes are matched from longest prefix to shortest to avoid ambiguity.
/// The final character must be a digit 0-4 representing the spin level.
///
/// Returns None if the code does not match a spin pattern.
fn try_parse_spin(code: &str) -> Option<Spin> {
    // Order matters: try longest prefixes first to avoid partial matches.
    // E.g. "CCoSp4" must match CCoSp before CoSp or CSp.
    let spin_prefixes: Vec<(&str, SpinType)> = vec![
        ("CCoSp", SpinType::ChangeFootCombination),
        ("FCoSp", SpinType::Flying(SpinPosition::Camel)), // Flying combination
        ("CoSp", SpinType::Combination),
        ("FSSp", SpinType::Flying(SpinPosition::Sit)),
        ("FCSp", SpinType::Flying(SpinPosition::Camel)),
        ("FUSp", SpinType::Flying(SpinPosition::Upright)),
        ("SSp", SpinType::Single(SpinPosition::Sit)),
        ("CSp", SpinType::Single(SpinPosition::Camel)),
        ("USp", SpinType::Single(SpinPosition::Upright)),
    ];

    for (prefix, spin_type) in spin_prefixes {
        if let Some(rest) = code.strip_prefix(prefix) {
            let level = rest.parse::<u8>().ok()?;
            if level <= 4 {
                return Some(Spin::new(spin_type, level));
            }
        }
    }
    None
}

/// Parse a jump combination or sequence code containing "+".
///
/// Examples:
///   - "3Lz+3T" → JumpCombination([3Lz, 3T])
///   - "3F+2T+2Lo" → JumpCombination([3F, 2T, 2Lo])
///   - "2A+1Lo+SEQ" → JumpSequence([2A, 1Lo])
///
/// # Errors
/// Returns an error if any component cannot be parsed as a jump.
fn parse_jump_combination(code: &str) -> Result<ElementCode> {
    let parts: Vec<&str> = code.split('+').collect();

    // Check for SEQ marker (jump sequence, not combination)
    let is_sequence = parts.last().is_some_and(|p| p.trim() == "SEQ");
    let jump_parts = if is_sequence {
        &parts[..parts.len() - 1]
    } else {
        &parts[..]
    };

    let jumps: Vec<Jump> = jump_parts
        .iter()
        .enumerate()
        .map(|(i, part)| {
            try_parse_jump(part.trim()).ok_or_else(|| {
                anyhow::anyhow!(
                    "Cannot parse jump {} ('{}') in combination '{}'",
                    i + 1,
                    part,
                    code
                )
            })
        })
        .collect::<Result<Vec<_>>>()?;

    if jumps.is_empty() {
        bail!("Empty jump combination: '{}'", code);
    }

    if is_sequence {
        Ok(ElementCode::JumpSequence(jumps))
    } else {
        Ok(ElementCode::JumpCombination(jumps))
    }
}

/// Attempt to parse a single jump code (e.g. "3Lz", "2A", "4T", "1Lo").
///
/// Format: <rotations><jump_type_code>
/// Where rotations is 1-4 and jump_type_code is one of: T, S, Lo, F, Lz, A
///
/// Returns None if the code does not match a jump pattern.
fn try_parse_jump(code: &str) -> Option<Jump> {
    if code.is_empty() {
        return None;
    }

    // First character must be a digit (rotation count)
    let first_char = code.chars().next()?;
    let rotations = first_char.to_digit(10)? as u8;
    if rotations == 0 || rotations > 4 {
        return None;
    }

    // Remaining characters are the jump type code
    let type_code = &code[1..];
    let jump_type = JumpType::from_code(type_code)?;

    Some(Jump::new(rotations, jump_type))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_solo_jump_triple_lutz() {
        let elem = parse_element("3Lz").expect("TODO: handle error");
        match elem {
            ElementCode::SoloJump(j) => {
                assert_eq!(j.rotations, 3);
                assert_eq!(j.jump_type, JumpType::Lutz);
                assert_eq!(j.notation(), "3Lz");
            }
            _ => panic!("Expected SoloJump, got {:?}", elem),
        }
    }

    #[test]
    fn test_parse_solo_jump_double_axel() {
        let elem = parse_element("2A").expect("TODO: handle error");
        match elem {
            ElementCode::SoloJump(j) => {
                assert_eq!(j.rotations, 2);
                assert_eq!(j.jump_type, JumpType::Axel);
            }
            _ => panic!("Expected SoloJump"),
        }
    }

    #[test]
    fn test_parse_solo_jump_quad_toeloop() {
        let elem = parse_element("4T").expect("TODO: handle error");
        match elem {
            ElementCode::SoloJump(j) => {
                assert_eq!(j.rotations, 4);
                assert_eq!(j.jump_type, JumpType::Toeloop);
            }
            _ => panic!("Expected SoloJump"),
        }
    }

    #[test]
    fn test_parse_combination_3lz_3t() {
        let elem = parse_element("3Lz+3T").expect("TODO: handle error");
        match elem {
            ElementCode::JumpCombination(jumps) => {
                assert_eq!(jumps.len(), 2);
                assert_eq!(jumps[0].notation(), "3Lz");
                assert_eq!(jumps[1].notation(), "3T");
            }
            _ => panic!("Expected JumpCombination"),
        }
    }

    #[test]
    fn test_parse_triple_combination() {
        let elem = parse_element("3F+2T+2Lo").expect("TODO: handle error");
        match elem {
            ElementCode::JumpCombination(jumps) => {
                assert_eq!(jumps.len(), 3);
                assert_eq!(jumps[0].jump_type, JumpType::Flip);
                assert_eq!(jumps[1].jump_type, JumpType::Toeloop);
                assert_eq!(jumps[2].jump_type, JumpType::Loop);
            }
            _ => panic!("Expected JumpCombination"),
        }
    }

    #[test]
    fn test_parse_spin_ccosp4() {
        let elem = parse_element("CCoSp4").expect("TODO: handle error");
        match elem {
            ElementCode::Spin(s) => {
                assert_eq!(s.spin_type, SpinType::ChangeFootCombination);
                assert_eq!(s.level, 4);
                assert_eq!(s.notation(), "CCoSp4");
            }
            _ => panic!("Expected Spin"),
        }
    }

    #[test]
    fn test_parse_spin_fssp3() {
        let elem = parse_element("FSSp3").expect("TODO: handle error");
        match elem {
            ElementCode::Spin(s) => {
                assert_eq!(s.spin_type, SpinType::Flying(SpinPosition::Sit));
                assert_eq!(s.level, 3);
            }
            _ => panic!("Expected Spin"),
        }
    }

    #[test]
    fn test_parse_step_sequence() {
        let elem = parse_element("StSq3").expect("TODO: handle error");
        match elem {
            ElementCode::Step(st) => {
                assert_eq!(st.step_type, StepType::StepSequence);
                assert_eq!(st.level, 3);
                assert_eq!(st.notation(), "StSq3");
            }
            _ => panic!("Expected Step"),
        }
    }

    #[test]
    fn test_parse_choreographic_sequence() {
        let elem = parse_element("ChSq1").expect("TODO: handle error");
        match elem {
            ElementCode::Step(st) => {
                assert_eq!(st.step_type, StepType::ChoreographicSequence);
                assert_eq!(st.level, 1);
            }
            _ => panic!("Expected Step"),
        }
    }

    #[test]
    fn test_parse_invalid_element() {
        assert!(parse_element("XYZ").is_err());
        assert!(parse_element("").is_err());
        assert!(parse_element("0T").is_err());
        assert!(parse_element("5Lz").is_err());
    }

    #[test]
    fn test_parse_jump_sequence_with_seq_marker() {
        let elem = parse_element("2A+2T+SEQ").expect("TODO: handle error");
        match elem {
            ElementCode::JumpSequence(jumps) => {
                assert_eq!(jumps.len(), 2);
                assert_eq!(jumps[0].jump_type, JumpType::Axel);
                assert_eq!(jumps[1].jump_type, JumpType::Toeloop);
            }
            _ => panic!("Expected JumpSequence"),
        }
    }

    #[test]
    fn test_parse_program_multiple_elements() {
        let codes = vec![
            "3Lz+3T".to_string(),
            "3F".to_string(),
            "CCoSp4".to_string(),
            "StSq3".to_string(),
            "2A".to_string(),
        ];
        let elements = parse_program(&codes).expect("TODO: handle error");
        assert_eq!(elements.len(), 5);
        assert!(elements[0].is_jump_element());
        assert!(elements[1].is_jump_element());
        assert!(!elements[2].is_jump_element()); // spin
        assert!(!elements[3].is_jump_element()); // step
        assert!(elements[4].is_jump_element());
    }
}
