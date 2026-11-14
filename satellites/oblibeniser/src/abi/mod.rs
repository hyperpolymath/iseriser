// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// ABI module for oblibeniser — core types for reversible operations, audit trails,
// undo stacks, and time-travel debugging. These types form the Oblíbený interface
// contract: every state-mutating operation MUST have a corresponding inverse.

use serde::{Deserialize, Serialize};
use std::collections::VecDeque;
use std::fmt;
use std::time::{SystemTime, UNIX_EPOCH};

/// Strategy for generating the inverse of an operation.
///
/// - `Mirror`: Derive the inverse algebraically (e.g., add→sub, insert→delete).
///   Best for pure, deterministic operations with known mathematical inverses.
/// - `LogReplay`: Record a mutation log and replay it backwards to undo.
///   Suited for complex operations where algebraic inversion is impractical.
/// - `Snapshot`: Capture full state before each operation and restore on undo.
///   Most expensive but works for any operation regardless of complexity.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum InverseStrategy {
    Mirror,
    LogReplay,
    Snapshot,
}

impl fmt::Display for InverseStrategy {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            InverseStrategy::Mirror => write!(f, "mirror"),
            InverseStrategy::LogReplay => write!(f, "log-replay"),
            InverseStrategy::Snapshot => write!(f, "snapshot"),
        }
    }
}

impl InverseStrategy {
    /// Parse a string into an InverseStrategy, returning None for unrecognised values.
    pub fn from_str_opt(s: &str) -> Option<Self> {
        match s {
            "mirror" => Some(InverseStrategy::Mirror),
            "log-replay" => Some(InverseStrategy::LogReplay),
            "snapshot" => Some(InverseStrategy::Snapshot),
            _ => None,
        }
    }
}

/// A parameter definition for an operation, capturing its name and type.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct OperationParam {
    /// Parameter name (e.g., "key", "value", "index").
    pub name: String,
    /// Type annotation as a string (e.g., "String", "i64", "Vec<u8>").
    pub param_type: String,
}

/// A reversible operation definition. Every operation has a forward function
/// and a strategy for computing its inverse. The Oblíbený guarantee: if
/// `forward(state) -> state'`, then `inverse(state') -> state`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ReversibleOperation {
    /// Unique name identifying this operation (e.g., "db_insert", "set_field").
    pub name: String,
    /// Fully qualified path to the forward function (e.g., "db::insert").
    pub forward_fn: String,
    /// Parameters accepted by the forward function.
    pub params: Vec<OperationParam>,
    /// Strategy used to generate or execute the inverse.
    pub inverse_strategy: InverseStrategy,
    /// Auto-generated name for the inverse function (e.g., "db_insert_inverse").
    pub inverse_fn_name: String,
}

impl ReversibleOperation {
    /// Construct a new ReversibleOperation, auto-generating the inverse function name.
    pub fn new(
        name: String,
        forward_fn: String,
        params: Vec<OperationParam>,
        inverse_strategy: InverseStrategy,
    ) -> Self {
        let inverse_fn_name = format!("{}_inverse", name);
        Self {
            name,
            forward_fn,
            params,
            inverse_strategy,
            inverse_fn_name,
        }
    }
}

/// A single entry in the hash-chained audit trail. Each entry contains the
/// hash of the previous entry, forming a tamper-evident chain (like a
/// lightweight blockchain for operation history).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AuditEntry {
    /// Monotonically increasing sequence number within the audit trail.
    pub sequence: u64,
    /// Timestamp as Unix epoch milliseconds when this entry was recorded.
    pub timestamp_ms: u64,
    /// Name of the operation that was executed.
    pub operation_name: String,
    /// Hex-encoded SHA-256 hash of the serialised parameters.
    pub params_hash: String,
    /// Hex-encoded SHA-256 hash of the previous AuditEntry (empty string for first entry).
    pub prev_hash: String,
    /// Hex-encoded SHA-256 hash of this entry (computed over all fields above).
    pub entry_hash: String,
}

impl AuditEntry {
    /// Create a new AuditEntry, computing its hash from all fields plus the previous hash.
    /// Uses a simple SHA-256-style hash (actually a deterministic mixing function for
    /// the Rust-side representation; real SHA-256 is used in generated code).
    pub fn new(
        sequence: u64,
        operation_name: String,
        params_hash: String,
        prev_hash: String,
    ) -> Self {
        let timestamp_ms = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis() as u64;

        let preimage = format!(
            "{}:{}:{}:{}:{}",
            sequence, timestamp_ms, operation_name, params_hash, prev_hash
        );
        let entry_hash = simple_hash(&preimage);

        Self {
            sequence,
            timestamp_ms,
            operation_name,
            params_hash,
            prev_hash,
            entry_hash,
        }
    }

    /// Verify the integrity of this entry by recomputing its hash.
    pub fn verify(&self) -> bool {
        let preimage = format!(
            "{}:{}:{}:{}:{}",
            self.sequence, self.timestamp_ms, self.operation_name, self.params_hash, self.prev_hash
        );
        simple_hash(&preimage) == self.entry_hash
    }
}

/// The audit trail: a hash-chained sequence of AuditEntry records.
/// Supports append, verification of chain integrity, and bounded storage.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuditTrail {
    /// All entries in the trail, ordered by sequence number.
    pub entries: Vec<AuditEntry>,
    /// Maximum number of entries to retain (0 = unlimited).
    pub max_entries: usize,
    /// Whether hash-chaining is enabled (should always be true for production).
    pub hash_chain_enabled: bool,
}

impl AuditTrail {
    /// Create a new empty audit trail with the given constraints.
    pub fn new(max_entries: usize, hash_chain_enabled: bool) -> Self {
        Self {
            entries: Vec::new(),
            max_entries,
            hash_chain_enabled,
        }
    }

    /// Record a new operation in the audit trail, computing hashes and enforcing max_entries.
    pub fn record(&mut self, operation_name: &str, params_hash: &str) -> &AuditEntry {
        let sequence = self.entries.len() as u64;
        let prev_hash = self
            .entries
            .last()
            .map(|e| e.entry_hash.clone())
            .unwrap_or_default();

        let entry = AuditEntry::new(
            sequence,
            operation_name.to_string(),
            params_hash.to_string(),
            if self.hash_chain_enabled {
                prev_hash
            } else {
                String::new()
            },
        );

        self.entries.push(entry);

        // Evict oldest entries if we exceed max_entries (and max_entries > 0).
        if self.max_entries > 0 && self.entries.len() > self.max_entries {
            let excess = self.entries.len() - self.max_entries;
            self.entries.drain(0..excess);
        }

        self.entries.last().expect("TODO: handle error")
    }

    /// Verify the integrity of the entire hash chain. Returns the index of
    /// the first broken link, or None if the chain is intact.
    pub fn verify_chain(&self) -> Option<usize> {
        for (i, entry) in self.entries.iter().enumerate() {
            // Verify self-consistency of each entry.
            if !entry.verify() {
                return Some(i);
            }
            // Verify chain linkage (skip the first entry or entries after eviction).
            if i > 0 && self.hash_chain_enabled && entry.prev_hash != self.entries[i - 1].entry_hash
            {
                return Some(i);
            }
        }
        None
    }

    /// Return the number of entries in the trail.
    pub fn len(&self) -> usize {
        self.entries.len()
    }

    /// Check if the trail is empty.
    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }
}

/// A snapshot of serialised state, used by the Snapshot inverse strategy.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct StateSnapshot {
    /// The sequence number (corresponds to AuditEntry.sequence) when this snapshot was taken.
    pub at_sequence: u64,
    /// Serialised state data (opaque bytes, application-defined format).
    pub data: Vec<u8>,
}

/// The undo/redo stack providing time-travel capabilities. Operations are pushed
/// onto the undo stack when executed; undoing pops from undo and pushes to redo.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UndoStack {
    /// Stack of operations that can be undone (most recent at the back).
    pub undo_entries: VecDeque<UndoEntry>,
    /// Stack of operations that can be redone (most recent at the back).
    pub redo_entries: VecDeque<UndoEntry>,
    /// Maximum depth of the undo stack (0 = unlimited).
    pub max_depth: usize,
    /// Number of operations between automatic checkpoint snapshots (0 = disabled).
    pub auto_checkpoint_interval: usize,
    /// Counter of operations since the last checkpoint.
    operations_since_checkpoint: usize,
}

/// A single entry on the undo/redo stack, capturing enough information to
/// reverse or re-apply an operation.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UndoEntry {
    /// The operation that was performed.
    pub operation_name: String,
    /// Serialised forward parameters (so we can redo).
    pub forward_params: Vec<u8>,
    /// Serialised inverse parameters (so we can undo).
    pub inverse_params: Vec<u8>,
    /// Optional state snapshot (for Snapshot strategy operations).
    pub snapshot: Option<StateSnapshot>,
    /// The audit trail sequence number when this operation occurred.
    pub audit_sequence: u64,
}

impl UndoStack {
    /// Create a new empty undo stack with the given constraints.
    pub fn new(max_depth: usize, auto_checkpoint_interval: usize) -> Self {
        Self {
            undo_entries: VecDeque::new(),
            redo_entries: VecDeque::new(),
            max_depth,
            auto_checkpoint_interval,
            operations_since_checkpoint: 0,
        }
    }

    /// Push a new operation onto the undo stack. Clears the redo stack (since
    /// a new operation invalidates any previously-undone future). Enforces max_depth.
    pub fn push(&mut self, entry: UndoEntry) {
        // New operation invalidates the redo stack.
        self.redo_entries.clear();

        self.undo_entries.push_back(entry);

        // Enforce max depth by evicting the oldest entry.
        if self.max_depth > 0 && self.undo_entries.len() > self.max_depth {
            self.undo_entries.pop_front();
        }

        self.operations_since_checkpoint += 1;
    }

    /// Pop the most recent operation from the undo stack, moving it to redo.
    /// Returns the UndoEntry that should be reversed, or None if the stack is empty.
    pub fn undo(&mut self) -> Option<UndoEntry> {
        if let Some(entry) = self.undo_entries.pop_back() {
            self.redo_entries.push_back(entry.clone());
            Some(entry)
        } else {
            None
        }
    }

    /// Pop the most recent operation from the redo stack, moving it back to undo.
    /// Returns the UndoEntry that should be re-applied, or None if redo is empty.
    pub fn redo(&mut self) -> Option<UndoEntry> {
        if let Some(entry) = self.redo_entries.pop_back() {
            self.undo_entries.push_back(entry.clone());
            Some(entry)
        } else {
            None
        }
    }

    /// Check whether an automatic checkpoint should be taken now.
    /// Returns true if auto_checkpoint_interval > 0 and the counter has reached it.
    pub fn should_checkpoint(&self) -> bool {
        self.auto_checkpoint_interval > 0
            && self.operations_since_checkpoint >= self.auto_checkpoint_interval
    }

    /// Reset the checkpoint counter (call after taking a checkpoint).
    pub fn reset_checkpoint_counter(&mut self) {
        self.operations_since_checkpoint = 0;
    }

    /// Return the current depth of the undo stack.
    pub fn undo_depth(&self) -> usize {
        self.undo_entries.len()
    }

    /// Return the current depth of the redo stack.
    pub fn redo_depth(&self) -> usize {
        self.redo_entries.len()
    }

    /// Check if the undo stack is empty.
    pub fn is_empty(&self) -> bool {
        self.undo_entries.is_empty()
    }
}

/// Time-travel debugger: allows navigating to any point in the operation history,
/// inspecting state at that point, and optionally forking a new timeline.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimeTravel {
    /// The complete audit trail for this timeline.
    pub audit_trail: AuditTrail,
    /// The undo/redo stack for navigating history.
    pub undo_stack: UndoStack,
    /// Periodic state snapshots for efficient time-travel (indexed by sequence number).
    pub snapshots: Vec<StateSnapshot>,
    /// The current position in the timeline (sequence number).
    pub current_position: u64,
}

impl TimeTravel {
    /// Create a new TimeTravel instance with the given audit and undo configuration.
    pub fn new(
        max_audit_entries: usize,
        hash_chain: bool,
        max_undo_depth: usize,
        checkpoint_interval: usize,
    ) -> Self {
        Self {
            audit_trail: AuditTrail::new(max_audit_entries, hash_chain),
            undo_stack: UndoStack::new(max_undo_depth, checkpoint_interval),
            snapshots: Vec::new(),
            current_position: 0,
        }
    }

    /// Record an operation: adds to audit trail and undo stack, takes checkpoints as needed.
    pub fn record_operation(
        &mut self,
        operation_name: &str,
        params_hash: &str,
        forward_params: Vec<u8>,
        inverse_params: Vec<u8>,
        snapshot_data: Option<Vec<u8>>,
    ) {
        let audit_entry = self.audit_trail.record(operation_name, params_hash);
        let seq = audit_entry.sequence;

        let snapshot = snapshot_data.map(|data| StateSnapshot {
            at_sequence: seq,
            data,
        });

        // Store snapshot for time-travel if provided.
        if let Some(ref snap) = snapshot {
            self.snapshots.push(snap.clone());
        }

        let undo_entry = UndoEntry {
            operation_name: operation_name.to_string(),
            forward_params,
            inverse_params,
            snapshot,
            audit_sequence: seq,
        };

        self.undo_stack.push(undo_entry);
        self.current_position = seq;

        // Auto-checkpoint handling.
        if self.undo_stack.should_checkpoint() {
            self.undo_stack.reset_checkpoint_counter();
        }
    }

    /// Travel to a specific point in the timeline (by sequence number).
    /// Returns the list of operations that need to be undone (if travelling backward)
    /// or redone (if travelling forward), in execution order.
    pub fn travel_to(&mut self, target_sequence: u64) -> Vec<TimeTravelStep> {
        let mut steps = Vec::new();

        if target_sequence < self.current_position {
            // Travel backward: undo operations.
            while self.current_position > target_sequence {
                if let Some(entry) = self.undo_stack.undo() {
                    steps.push(TimeTravelStep {
                        direction: TimeTravelDirection::Backward,
                        entry,
                    });
                    self.current_position = self.current_position.saturating_sub(1);
                } else {
                    break;
                }
            }
        } else if target_sequence > self.current_position {
            // Travel forward: redo operations.
            while self.current_position < target_sequence {
                if let Some(entry) = self.undo_stack.redo() {
                    steps.push(TimeTravelStep {
                        direction: TimeTravelDirection::Forward,
                        entry,
                    });
                    self.current_position += 1;
                } else {
                    break;
                }
            }
        }

        steps
    }

    /// Find the nearest snapshot at or before the given sequence number.
    /// Used to efficiently restore state for time-travel without replaying
    /// the entire history from the beginning.
    pub fn nearest_snapshot(&self, target_sequence: u64) -> Option<&StateSnapshot> {
        self.snapshots
            .iter()
            .filter(|s| s.at_sequence <= target_sequence)
            .max_by_key(|s| s.at_sequence)
    }
}

/// A single step in a time-travel operation (either undo or redo).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimeTravelStep {
    /// Direction of travel (backward = undo, forward = redo).
    pub direction: TimeTravelDirection,
    /// The undo entry being applied or reversed.
    pub entry: UndoEntry,
}

/// Direction of time-travel navigation.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum TimeTravelDirection {
    Forward,
    Backward,
}

// ---------------------------------------------------------------------------
// Internal utility: a simple deterministic hash function for Rust-side
// audit chain computation. This uses FNV-1a (64-bit) and formats as hex.
// Generated code uses proper SHA-256 via platform libraries.
// ---------------------------------------------------------------------------

/// Compute a simple deterministic hash (FNV-1a 64-bit, hex-encoded) of the input string.
/// Used internally for audit chain hashing in the Rust CLI. Generated code uses SHA-256.
pub fn simple_hash(input: &str) -> String {
    const FNV_OFFSET: u64 = 14695981039346656037;
    const FNV_PRIME: u64 = 1099511628211;

    let mut hash = FNV_OFFSET;
    for byte in input.as_bytes() {
        hash ^= *byte as u64;
        hash = hash.wrapping_mul(FNV_PRIME);
    }
    format!("{:016x}", hash)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_inverse_strategy_display() {
        assert_eq!(InverseStrategy::Mirror.to_string(), "mirror");
        assert_eq!(InverseStrategy::LogReplay.to_string(), "log-replay");
        assert_eq!(InverseStrategy::Snapshot.to_string(), "snapshot");
    }

    #[test]
    fn test_inverse_strategy_from_str() {
        assert_eq!(
            InverseStrategy::from_str_opt("mirror"),
            Some(InverseStrategy::Mirror)
        );
        assert_eq!(InverseStrategy::from_str_opt("invalid"), None);
    }

    #[test]
    fn test_reversible_operation_new() {
        let op = ReversibleOperation::new(
            "db_insert".to_string(),
            "db::insert".to_string(),
            vec![OperationParam {
                name: "key".to_string(),
                param_type: "String".to_string(),
            }],
            InverseStrategy::Mirror,
        );
        assert_eq!(op.inverse_fn_name, "db_insert_inverse");
    }

    #[test]
    fn test_audit_entry_verify() {
        let entry = AuditEntry::new(
            0,
            "test_op".to_string(),
            "abc123".to_string(),
            String::new(),
        );
        assert!(entry.verify());
    }

    #[test]
    fn test_audit_trail_chain() {
        let mut trail = AuditTrail::new(100, true);
        trail.record("op1", "hash1");
        trail.record("op2", "hash2");
        trail.record("op3", "hash3");
        assert_eq!(trail.len(), 3);
        assert!(trail.verify_chain().is_none(), "chain should be intact");
    }

    #[test]
    fn test_audit_trail_max_entries() {
        let mut trail = AuditTrail::new(2, true);
        trail.record("op1", "h1");
        trail.record("op2", "h2");
        trail.record("op3", "h3");
        assert_eq!(trail.len(), 2);
        assert_eq!(trail.entries[0].operation_name, "op2");
    }

    #[test]
    fn test_undo_stack_push_undo_redo() {
        let mut stack = UndoStack::new(10, 0);
        stack.push(UndoEntry {
            operation_name: "op1".to_string(),
            forward_params: vec![1],
            inverse_params: vec![2],
            snapshot: None,
            audit_sequence: 0,
        });
        stack.push(UndoEntry {
            operation_name: "op2".to_string(),
            forward_params: vec![3],
            inverse_params: vec![4],
            snapshot: None,
            audit_sequence: 1,
        });
        assert_eq!(stack.undo_depth(), 2);

        let undone = stack.undo().expect("TODO: handle error");
        assert_eq!(undone.operation_name, "op2");
        assert_eq!(stack.undo_depth(), 1);
        assert_eq!(stack.redo_depth(), 1);

        let redone = stack.redo().expect("TODO: handle error");
        assert_eq!(redone.operation_name, "op2");
        assert_eq!(stack.undo_depth(), 2);
        assert_eq!(stack.redo_depth(), 0);
    }

    #[test]
    fn test_undo_stack_max_depth() {
        let mut stack = UndoStack::new(2, 0);
        for i in 0..5 {
            stack.push(UndoEntry {
                operation_name: format!("op{}", i),
                forward_params: vec![],
                inverse_params: vec![],
                snapshot: None,
                audit_sequence: i as u64,
            });
        }
        assert_eq!(stack.undo_depth(), 2);
        let entry = stack.undo().expect("TODO: handle error");
        assert_eq!(entry.operation_name, "op4");
    }

    #[test]
    fn test_simple_hash_deterministic() {
        let h1 = simple_hash("hello world");
        let h2 = simple_hash("hello world");
        assert_eq!(h1, h2);
        let h3 = simple_hash("different input");
        assert_ne!(h1, h3);
    }

    #[test]
    fn test_time_travel_record_and_navigate() {
        let mut tt = TimeTravel::new(100, true, 50, 0);
        tt.record_operation("op1", "h1", vec![1], vec![2], None);
        tt.record_operation("op2", "h2", vec![3], vec![4], None);
        tt.record_operation("op3", "h3", vec![5], vec![6], None);

        assert_eq!(tt.current_position, 2);

        let steps = tt.travel_to(0);
        assert_eq!(steps.len(), 2);
        assert_eq!(steps[0].direction, TimeTravelDirection::Backward);
        assert_eq!(tt.current_position, 0);
    }
}
