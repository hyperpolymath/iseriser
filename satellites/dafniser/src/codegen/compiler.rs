// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Compiler command generation for dafniser.
// Produces `dafny verify` and `dafny build` command strings for the
// generated .dfy files. These commands can be executed in a shell or
// integrated into a CI pipeline.

use std::path::Path;

use crate::abi::TargetLanguage;

/// Generate a `dafny verify` command for a .dfy file.
///
/// The verification command runs Z3-based automatic verification on all
/// methods, functions, and lemmas in the file. The timeout controls the
/// maximum per-assertion time.
///
/// # Arguments
/// * `dfy_path` - Path to the .dfy source file.
/// * `timeout_seconds` - Maximum verification time per function in seconds.
///
/// # Returns
/// A shell command string.
pub fn verification_command(dfy_path: &Path, timeout_seconds: u32) -> String {
    format!(
        "dafny verify \"{}\" --verification-time-limit {}",
        dfy_path.display(),
        timeout_seconds
    )
}

/// Generate a `dafny build` command for a .dfy file.
///
/// The build command compiles verified Dafny code to the specified target
/// language. The Dafny compiler emits source files (or a binary, depending
/// on the target) that can be integrated into the downstream project.
///
/// # Arguments
/// * `dfy_path` - Path to the .dfy source file.
/// * `target` - Target language for compilation.
///
/// # Returns
/// A shell command string.
pub fn build_command(dfy_path: &Path, target: TargetLanguage) -> String {
    format!(
        "dafny build \"{}\" --target {}",
        dfy_path.display(),
        target.dafny_target_flag()
    )
}

/// Generate a combined verify-then-build command.
///
/// Verification runs first; if it succeeds, compilation proceeds.
/// This is the recommended workflow for CI pipelines.
///
/// # Arguments
/// * `dfy_path` - Path to the .dfy source file.
/// * `target` - Target language for compilation.
/// * `timeout_seconds` - Maximum verification time per function in seconds.
///
/// # Returns
/// A shell command string using `&&` for sequencing.
pub fn verify_and_build_command(
    dfy_path: &Path,
    target: TargetLanguage,
    timeout_seconds: u32,
) -> String {
    format!(
        "{} && {}",
        verification_command(dfy_path, timeout_seconds),
        build_command(dfy_path, target)
    )
}

/// Generate a `dafny test` command for running Dafny test methods.
///
/// Dafny supports `{:test}` attributes on methods; this command runs them.
///
/// # Arguments
/// * `dfy_path` - Path to the .dfy source file.
/// * `target` - Target language for test execution.
///
/// # Returns
/// A shell command string.
pub fn test_command(dfy_path: &Path, target: TargetLanguage) -> String {
    format!(
        "dafny test \"{}\" --target {}",
        dfy_path.display(),
        target.dafny_target_flag()
    )
}

// ---------------------------------------------------------------------------
// Unit tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_verification_command() {
        let path = Path::new("output/Verified_sort.dfy");
        let cmd = verification_command(path, 30);
        assert!(cmd.contains("dafny verify"));
        assert!(cmd.contains("Verified_sort.dfy"));
        assert!(cmd.contains("--verification-time-limit 30"));
    }

    #[test]
    fn test_build_command_go() {
        let path = Path::new("output/Verified_sort.dfy");
        let cmd = build_command(path, TargetLanguage::Go);
        assert!(cmd.contains("dafny build"));
        assert!(cmd.contains("--target go"));
    }

    #[test]
    fn test_build_command_csharp() {
        let path = Path::new("output/M.dfy");
        let cmd = build_command(path, TargetLanguage::CSharp);
        assert!(cmd.contains("--target cs"));
    }

    #[test]
    fn test_verify_and_build() {
        let path = Path::new("output/M.dfy");
        let cmd = verify_and_build_command(path, TargetLanguage::Python, 60);
        assert!(cmd.contains("dafny verify"));
        assert!(cmd.contains("&&"));
        assert!(cmd.contains("dafny build"));
        assert!(cmd.contains("--target py"));
        assert!(cmd.contains("--verification-time-limit 60"));
    }

    #[test]
    fn test_test_command() {
        let path = Path::new("output/M.dfy");
        let cmd = test_command(path, TargetLanguage::Java);
        assert!(cmd.contains("dafny test"));
        assert!(cmd.contains("--target java"));
    }
}
