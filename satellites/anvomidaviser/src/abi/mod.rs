// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// ABI module for anvomidaviser — Type definitions for ISU figure skating elements,
// scoring, and program validation. These types mirror what the Idris2 ABI layer
// would formally verify: correct element representation, scoring arithmetic,
// and rule-compliance proofs.

use serde::{Deserialize, Serialize};
use std::fmt;

// ---------------------------------------------------------------------------
// Jump types — ISU Technical Panel Handbook, Section 3
// ---------------------------------------------------------------------------

/// All recognised ISU jump types, ordered by base value (ascending).
/// Each jump is identified by its ISU abbreviation code.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum JumpType {
    /// Toeloop (T) — toe-assisted, easiest toe jump
    Toeloop,
    /// Salchow (S) — edge jump from back inside edge
    Salchow,
    /// Loop (Lo) — edge jump from back outside edge
    Loop,
    /// Flip (F) — toe-assisted from back inside edge
    Flip,
    /// Lutz (Lz) — toe-assisted from back outside edge
    Lutz,
    /// Axel (A) — forward take-off edge jump (extra half rotation)
    Axel,
}

impl JumpType {
    /// Return the ISU abbreviation string for this jump type.
    pub fn code(&self) -> &'static str {
        match self {
            JumpType::Toeloop => "T",
            JumpType::Salchow => "S",
            JumpType::Loop => "Lo",
            JumpType::Flip => "F",
            JumpType::Lutz => "Lz",
            JumpType::Axel => "A",
        }
    }

    /// Parse an ISU abbreviation into a JumpType.
    pub fn from_code(code: &str) -> Option<JumpType> {
        match code {
            "T" => Some(JumpType::Toeloop),
            "S" => Some(JumpType::Salchow),
            "Lo" => Some(JumpType::Loop),
            "F" => Some(JumpType::Flip),
            "Lz" => Some(JumpType::Lutz),
            "A" => Some(JumpType::Axel),
            _ => None,
        }
    }
}

impl fmt::Display for JumpType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.code())
    }
}

// ---------------------------------------------------------------------------
// Spin types — ISU Technical Panel Handbook, Section 5
// ---------------------------------------------------------------------------

/// ISU spin position types.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum SpinPosition {
    /// Upright spin position
    Upright,
    /// Sit spin position (thigh at least parallel to ice)
    Sit,
    /// Camel spin position (free leg held backward, above hip level)
    Camel,
}

/// Full spin type including position and combination status.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum SpinType {
    /// Single-position spin: USp (upright), SSp (sit), CSp (camel)
    Single(SpinPosition),
    /// Combination spin: CCoSp (combination change of foot spin), etc.
    Combination,
    /// Flying spin entry: FSSp (flying sit spin), etc.
    Flying(SpinPosition),
    /// Change-of-foot combination spin
    ChangeFootCombination,
}

impl SpinType {
    /// Return the ISU base code prefix for this spin type.
    pub fn base_code(&self) -> &'static str {
        match self {
            SpinType::Single(SpinPosition::Upright) => "USp",
            SpinType::Single(SpinPosition::Sit) => "SSp",
            SpinType::Single(SpinPosition::Camel) => "CSp",
            SpinType::Combination => "CoSp",
            SpinType::Flying(SpinPosition::Upright) => "FUSp",
            SpinType::Flying(SpinPosition::Sit) => "FSSp",
            SpinType::Flying(SpinPosition::Camel) => "FCSp",
            SpinType::ChangeFootCombination => "CCoSp",
        }
    }
}

impl fmt::Display for SpinType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.base_code())
    }
}

// ---------------------------------------------------------------------------
// Step sequence types — ISU Technical Panel Handbook, Section 6
// ---------------------------------------------------------------------------

/// ISU step and choreographic sequence types.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum StepType {
    /// Step sequence (StSq) — required element with levels 1-4
    StepSequence,
    /// Choreographic sequence (ChSq) — artistic, fixed base value
    ChoreographicSequence,
}

impl StepType {
    /// Return the ISU code prefix for this step type.
    pub fn code(&self) -> &'static str {
        match self {
            StepType::StepSequence => "StSq",
            StepType::ChoreographicSequence => "ChSq",
        }
    }
}

impl fmt::Display for StepType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.code())
    }
}

// ---------------------------------------------------------------------------
// Element codes — unified representation of any program element
// ---------------------------------------------------------------------------

/// A single jump within a combination or sequence, with its rotation count.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Jump {
    /// Number of rotations (1-4 for most jumps; Axel is N+0.5 rotations)
    pub rotations: u8,
    /// The type of jump
    pub jump_type: JumpType,
    /// Whether the jump was under-rotated (< marker)
    pub under_rotated: bool,
    /// Whether the jump had a downgrade (<<)
    pub downgraded: bool,
    /// Whether a wrong edge was called (e for Flip/Lutz)
    pub edge_call: bool,
}

impl Jump {
    /// Construct a clean jump with no deductions.
    pub fn new(rotations: u8, jump_type: JumpType) -> Self {
        Self {
            rotations,
            jump_type,
            under_rotated: false,
            downgraded: false,
            edge_call: false,
        }
    }

    /// Return the ISU notation string, e.g. "3Lz", "2A", "1Lo".
    pub fn notation(&self) -> String {
        format!("{}{}", self.rotations, self.jump_type.code())
    }
}

impl fmt::Display for Jump {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.notation())
    }
}

/// A spin element with position type and level.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Spin {
    /// The spin type (position + variation)
    pub spin_type: SpinType,
    /// Level (0 = Base, 1-4 = feature levels)
    pub level: u8,
}

impl Spin {
    /// Construct a spin element.
    pub fn new(spin_type: SpinType, level: u8) -> Self {
        Self { spin_type, level }
    }

    /// Return the ISU notation string, e.g. "CCoSp4", "FSSp3".
    pub fn notation(&self) -> String {
        format!("{}{}", self.spin_type.base_code(), self.level)
    }
}

impl fmt::Display for Spin {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.notation())
    }
}

/// A step or choreographic sequence element with level.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct StepSequence {
    /// The step type (step sequence vs choreographic)
    pub step_type: StepType,
    /// Level (1-4 for StSq; ChSq is always level 1)
    pub level: u8,
}

impl StepSequence {
    /// Construct a step sequence element.
    pub fn new(step_type: StepType, level: u8) -> Self {
        Self { step_type, level }
    }

    /// Return the ISU notation string, e.g. "StSq3", "ChSq1".
    pub fn notation(&self) -> String {
        format!("{}{}", self.step_type.code(), self.level)
    }
}

impl fmt::Display for StepSequence {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.notation())
    }
}

/// A parsed ISU element code — the unified representation of any program element.
/// This is the core type that the parser produces and the validator/scorer consume.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum ElementCode {
    /// A solo jump (single element, not part of combination)
    SoloJump(Jump),
    /// A jump combination (2-3 jumps connected, e.g. "3Lz+3T")
    JumpCombination(Vec<Jump>),
    /// A jump sequence (2 jumps with step between, marked with SEQ)
    JumpSequence(Vec<Jump>),
    /// A spin element
    Spin(Spin),
    /// A step or choreographic sequence
    Step(StepSequence),
}

impl ElementCode {
    /// Return the full ISU notation string for this element.
    pub fn notation(&self) -> String {
        match self {
            ElementCode::SoloJump(j) => j.notation(),
            ElementCode::JumpCombination(jumps) => jumps
                .iter()
                .map(|j| j.notation())
                .collect::<Vec<_>>()
                .join("+"),
            ElementCode::JumpSequence(jumps) => {
                let parts: Vec<String> = jumps.iter().map(|j| j.notation()).collect();
                format!("{}+SEQ", parts.join("+"))
            }
            ElementCode::Spin(s) => s.notation(),
            ElementCode::Step(st) => st.notation(),
        }
    }

    /// Return true if this element is any kind of jump (solo, combination, or sequence).
    pub fn is_jump_element(&self) -> bool {
        matches!(
            self,
            ElementCode::SoloJump(_)
                | ElementCode::JumpCombination(_)
                | ElementCode::JumpSequence(_)
        )
    }

    /// Extract all individual jumps from this element (empty vec for non-jump elements).
    pub fn jumps(&self) -> Vec<&Jump> {
        match self {
            ElementCode::SoloJump(j) => vec![j],
            ElementCode::JumpCombination(js) | ElementCode::JumpSequence(js) => js.iter().collect(),
            _ => vec![],
        }
    }
}

impl fmt::Display for ElementCode {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.notation())
    }
}

// ---------------------------------------------------------------------------
// Grade of Execution (GOE) — ISU Judging System
// ---------------------------------------------------------------------------

/// Grade of Execution for a single element, ranging from -5 to +5.
/// Each judge awards a GOE; the trimmed mean becomes the final GOE.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct GOE {
    /// The GOE value, clamped to [-5, +5]
    pub value: i8,
}

impl GOE {
    /// Create a new GOE, clamping to the valid range [-5, +5].
    pub fn new(value: i8) -> Self {
        Self {
            value: value.clamp(-5, 5),
        }
    }

    /// Return the GOE as a percentage factor applied to the base value.
    /// Each GOE step is 10% of base value (ISU 2024-2025 rules).
    pub fn factor(&self) -> f64 {
        self.value as f64 * 0.10
    }
}

impl fmt::Display for GOE {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        if self.value >= 0 {
            write!(f, "+{}", self.value)
        } else {
            write!(f, "{}", self.value)
        }
    }
}

// ---------------------------------------------------------------------------
// Scoring types — Technical Element Score (TES) and Program Component Score (PCS)
// ---------------------------------------------------------------------------

/// The technical score for a single element: base value + GOE adjustment.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TechnicalScore {
    /// The element being scored
    pub element: ElementCode,
    /// Base value from ISU scale of values
    pub base_value: f64,
    /// GOE adjustment (positive or negative)
    pub goe_adjustment: f64,
    /// Whether this element is in the second half of the program (1.1x bonus)
    pub second_half_bonus: bool,
}

impl TechnicalScore {
    /// Calculate the total score for this element.
    /// Second-half elements receive a 10% bonus on base value.
    pub fn total(&self) -> f64 {
        let base = if self.second_half_bonus {
            self.base_value * 1.1
        } else {
            self.base_value
        };
        // Round to 2 decimal places per ISU rules
        ((base + self.goe_adjustment) * 100.0).round() / 100.0
    }
}

/// The complete program score combining all technical elements and any violations.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ProgramScore {
    /// Individual element scores
    pub elements: Vec<TechnicalScore>,
    /// Rule violations detected during validation
    pub violations: Vec<Violation>,
    /// Total technical element score (TES)
    pub total_tes: f64,
}

impl ProgramScore {
    /// Calculate the total technical element score from individual elements.
    pub fn calculate_tes(elements: &[TechnicalScore]) -> f64 {
        let sum: f64 = elements.iter().map(|e| e.total()).sum();
        (sum * 100.0).round() / 100.0
    }
}

// ---------------------------------------------------------------------------
// Rule violations — ISU Technical Rules compliance
// ---------------------------------------------------------------------------

/// A violation of ISU technical rules detected during program validation.
/// Each violation references the specific ISU rule number and affected elements.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum Violation {
    /// Zayak rule: no more than 2 triple/quad jumps of the same type,
    /// and only one may appear in a combination. (ISU Rule 611.1.f)
    ZayakRule {
        /// The jump type that was repeated too many times
        jump_type: JumpType,
        /// Number of occurrences found
        count: usize,
    },

    /// Too many jump elements in the program.
    /// Short program: max 3 jump elements; Free skate: max 7 jump elements.
    TooManyJumpElements {
        /// Number of jump elements found
        found: usize,
        /// Maximum allowed for this segment
        maximum: usize,
    },

    /// Too many spin elements in the program.
    /// Short program: max 3 spins; Free skate: max 3 spins.
    TooManySpinElements {
        /// Number of spin elements found
        found: usize,
        /// Maximum allowed
        maximum: usize,
    },

    /// Too many step sequences in the program.
    TooManyStepSequences {
        /// Number of step sequences found
        found: usize,
        /// Maximum allowed
        maximum: usize,
    },

    /// Jump combination has too many jumps (max 3 jumps per combination).
    CombinationTooLong {
        /// The element notation
        element: String,
        /// Number of jumps in the combination
        jump_count: usize,
    },

    /// Too many jump combinations in the program.
    /// Free skate: max 3 combinations (one may have 3 jumps, rest max 2).
    TooManyCombinations {
        /// Number of combinations found
        found: usize,
        /// Maximum allowed
        maximum: usize,
    },

    /// Invalid element code that could not be parsed.
    InvalidElement {
        /// The raw element code string
        code: String,
        /// Description of the parsing error
        reason: String,
    },
}

impl fmt::Display for Violation {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Violation::ZayakRule { jump_type, count } => {
                write!(
                    f,
                    "Zayak rule: {} appears {} times (max 2 triples/quads of same type)",
                    jump_type, count
                )
            }
            Violation::TooManyJumpElements { found, maximum } => {
                write!(
                    f,
                    "Too many jump elements: {} found, maximum {} allowed",
                    found, maximum
                )
            }
            Violation::TooManySpinElements { found, maximum } => {
                write!(
                    f,
                    "Too many spin elements: {} found, maximum {} allowed",
                    found, maximum
                )
            }
            Violation::TooManyStepSequences { found, maximum } => {
                write!(
                    f,
                    "Too many step sequences: {} found, maximum {} allowed",
                    found, maximum
                )
            }
            Violation::CombinationTooLong {
                element,
                jump_count,
            } => {
                write!(
                    f,
                    "Combination '{}' has {} jumps (max 3)",
                    element, jump_count
                )
            }
            Violation::TooManyCombinations { found, maximum } => {
                write!(
                    f,
                    "Too many jump combinations: {} found, maximum {} allowed",
                    found, maximum
                )
            }
            Violation::InvalidElement { code, reason } => {
                write!(f, "Invalid element '{}': {}", code, reason)
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Program segment and discipline definitions
// ---------------------------------------------------------------------------

/// The competitive discipline within figure skating.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum Discipline {
    /// Men's or Women's singles
    Singles,
    /// Pairs skating
    Pairs,
    /// Ice dance
    IceDance,
}

impl fmt::Display for Discipline {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Discipline::Singles => write!(f, "singles"),
            Discipline::Pairs => write!(f, "pairs"),
            Discipline::IceDance => write!(f, "ice-dance"),
        }
    }
}

/// The program segment (short program or free skate).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum Segment {
    /// Short program (SP) — strictly defined required elements
    Short,
    /// Free skate (FS) — more elements, more artistic freedom
    Free,
}

impl Segment {
    /// Maximum number of jump elements allowed in this segment (singles).
    pub fn max_jump_elements(&self) -> usize {
        match self {
            Segment::Short => 3,
            Segment::Free => 7,
        }
    }

    /// Maximum number of spin elements allowed in this segment (singles).
    pub fn max_spin_elements(&self) -> usize {
        3
    }

    /// Maximum number of step sequences allowed in this segment (singles).
    pub fn max_step_sequences(&self) -> usize {
        match self {
            Segment::Short => 1,
            Segment::Free => 2, // 1 StSq + 1 ChSq typically
        }
    }

    /// Maximum number of jump combinations allowed in this segment (singles).
    pub fn max_combinations(&self) -> usize {
        match self {
            Segment::Short => 1,
            Segment::Free => 3,
        }
    }
}

impl fmt::Display for Segment {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Segment::Short => write!(f, "short"),
            Segment::Free => write!(f, "free"),
        }
    }
}

/// Competitive level (determines some rule variations).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum Level {
    /// Senior level (ISU Championship events)
    Senior,
    /// Junior level (ISU Junior events)
    Junior,
    /// Novice level (development level)
    Novice,
}

impl fmt::Display for Level {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Level::Senior => write!(f, "senior"),
            Level::Junior => write!(f, "junior"),
            Level::Novice => write!(f, "novice"),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_jump_type_roundtrip() {
        for jt in [
            JumpType::Toeloop,
            JumpType::Salchow,
            JumpType::Loop,
            JumpType::Flip,
            JumpType::Lutz,
            JumpType::Axel,
        ] {
            assert_eq!(JumpType::from_code(jt.code()), Some(jt));
        }
    }

    #[test]
    fn test_goe_clamping() {
        assert_eq!(GOE::new(7).value, 5);
        assert_eq!(GOE::new(-8).value, -5);
        assert_eq!(GOE::new(3).value, 3);
    }

    #[test]
    fn test_goe_factor() {
        assert!((GOE::new(3).factor() - 0.30).abs() < f64::EPSILON);
        assert!((GOE::new(-2).factor() - (-0.20)).abs() < f64::EPSILON);
    }

    #[test]
    fn test_technical_score_second_half_bonus() {
        let score = TechnicalScore {
            element: ElementCode::SoloJump(Jump::new(3, JumpType::Lutz)),
            base_value: 5.90,
            goe_adjustment: 1.18,
            second_half_bonus: true,
        };
        // 5.90 * 1.1 = 6.49, + 1.18 = 7.67
        let total = score.total();
        assert!((total - 7.67).abs() < 0.01);
    }

    #[test]
    fn test_element_code_notation() {
        let combo = ElementCode::JumpCombination(vec![
            Jump::new(3, JumpType::Lutz),
            Jump::new(3, JumpType::Toeloop),
        ]);
        assert_eq!(combo.notation(), "3Lz+3T");
    }
}
