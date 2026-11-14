// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// ATS2 compilation driver for atsiser.
//
// Constructs and executes the commands needed to compile ATS2 source files
// back to C via the ATS2 toolchain (patsopt for type-checking, patscc for
// C compilation). The compilation pipeline is:
//
// 1. patsopt --typecheck file.dats     → verifies linear type proofs
// 2. patsopt --output file_dats.c      → emits C code
// 3. patscc -o binary file.dats        → compiles via C compiler
//
// If any step fails (especially type-checking), it means the memory safety
// proofs did not hold and the C code has a potential safety violation.

use anyhow::{Context, Result};
use std::fmt;
use std::process::Command;

use crate::manifest::Manifest;

/// A compilation command ready to be displayed or executed.
///
/// Encapsulates the full command line for an ATS2 compilation step,
/// including environment variables, the compiler binary, and all flags.
#[derive(Debug, Clone)]
pub struct CompileCommand {
    /// Optional environment variable overrides (e.g., PATSHOME).
    pub env: Vec<(String, String)>,

    /// The compiler binary to invoke (e.g., "patscc").
    pub program: String,

    /// Command-line arguments.
    pub args: Vec<String>,
}

impl CompileCommand {
    /// Returns a human-readable display of the full command.
    pub fn display(&self) -> String {
        let env_str: Vec<String> = self
            .env
            .iter()
            .map(|(k, v)| format!("{}={}", k, v))
            .collect();
        let parts: Vec<&str> = env_str
            .iter()
            .map(|s| s.as_str())
            .chain(std::iter::once(self.program.as_str()))
            .chain(self.args.iter().map(|s| s.as_str()))
            .collect();
        parts.join(" ")
    }
}

impl fmt::Display for CompileCommand {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.display())
    }
}

/// Construct the ATS2 build command for a `.dats` file.
///
/// Assembles the patscc invocation with all flags from the manifest's [ats2]
/// section, plus release-mode optimisations if requested.
///
/// # Arguments
///
/// * `manifest` — The atsiser manifest with ATS2 configuration
/// * `dats_file` — Path to the `.dats` file to compile
/// * `release` — Whether to enable optimisations (-O2 for the C backend)
///
/// # Returns
///
/// A CompileCommand ready for execution or display.
pub fn build_command(
    manifest: &Manifest,
    dats_file: &str,
    release: bool,
) -> Result<CompileCommand> {
    let ats2 = &manifest.ats2;

    let mut env = Vec::new();
    if let Some(ref patshome) = ats2.patshome {
        env.push(("PATSHOME".to_string(), patshome.clone()));
    }

    let mut args = Vec::new();

    // ATS2-specific flags (e.g., -DATS_MEMALLOC_LIBC)
    for flag in &ats2.flags {
        args.push(flag.clone());
    }

    // C compiler flags via -ccopt
    for cflag in &ats2.c_flags {
        args.push("-ccopt".to_string());
        args.push(cflag.clone());
    }

    // Release mode: add -O2
    if release {
        args.push("-ccopt".to_string());
        args.push("-O2".to_string());
    }

    // Output binary name (strip .dats extension)
    let output_name = dats_file.trim_end_matches(".dats");
    args.push("-o".to_string());
    args.push(output_name.to_string());

    // The source file
    args.push(dats_file.to_string());

    Ok(CompileCommand {
        env,
        program: ats2.patscc.clone(),
        args,
    })
}

/// Construct a type-check-only command for a `.dats` file.
///
/// Runs patsopt with --typecheck to verify that all linear type proofs hold
/// without producing compiled output. This is useful for CI and pre-commit
/// checks.
///
/// # Arguments
///
/// * `manifest` — The atsiser manifest with ATS2 configuration
/// * `dats_file` — Path to the `.dats` file to type-check
///
/// # Returns
///
/// A CompileCommand that runs patsopt --typecheck.
pub fn typecheck_command(manifest: &Manifest, dats_file: &str) -> Result<CompileCommand> {
    let ats2 = &manifest.ats2;

    let mut env = Vec::new();
    if let Some(ref patshome) = ats2.patshome {
        env.push(("PATSHOME".to_string(), patshome.clone()));
    }

    let mut args = vec!["--typecheck".to_string()];

    // ATS2-specific flags
    for flag in &ats2.flags {
        args.push(flag.clone());
    }

    args.push(dats_file.to_string());

    Ok(CompileCommand {
        env,
        program: ats2.patsopt.clone(),
        args,
    })
}

/// Execute a build command, printing stdout/stderr and checking the exit status.
///
/// # Errors
///
/// Returns an error if the command fails to start or exits with a non-zero status.
/// ATS2 type-check failures will produce descriptive error messages about which
/// linear type proof failed.
pub fn execute_build(cmd: &CompileCommand) -> Result<()> {
    let mut command = Command::new(&cmd.program);
    command.args(&cmd.args);

    for (key, value) in &cmd.env {
        command.env(key, value);
    }

    let output = command
        .output()
        .with_context(|| format!("Failed to execute: {}", cmd.display()))?;

    if !output.stdout.is_empty() {
        let stdout = String::from_utf8_lossy(&output.stdout);
        print!("{}", stdout);
    }

    if !output.stderr.is_empty() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        eprint!("{}", stderr);
    }

    if !output.status.success() {
        let code = output.status.code().unwrap_or(-1);
        anyhow::bail!(
            "ATS2 compilation failed with exit code {}.\n\
             This typically means a linear type proof could not be discharged.\n\
             Check the error messages above for details.",
            code
        );
    }

    Ok(())
}

/// Execute a compiled binary with the given arguments.
///
/// # Errors
///
/// Returns an error if the binary cannot be started or exits with a non-zero status.
pub fn execute_run(binary: &str, args: &[String]) -> Result<()> {
    let output = Command::new(binary)
        .args(args)
        .output()
        .with_context(|| format!("Failed to execute binary: {}", binary))?;

    if !output.stdout.is_empty() {
        let stdout = String::from_utf8_lossy(&output.stdout);
        print!("{}", stdout);
    }

    if !output.stderr.is_empty() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        eprint!("{}", stderr);
    }

    if !output.status.success() {
        let code = output.status.code().unwrap_or(-1);
        anyhow::bail!("Binary exited with code {}", code);
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::manifest::{ATS2Config, CSource, Manifest, OwnershipRule, ProjectConfig};

    /// Helper to create a test manifest.
    fn test_manifest() -> Manifest {
        Manifest {
            project: ProjectConfig {
                name: "test-lib".to_string(),
                version: "0.1.0".to_string(),
                description: "Test".to_string(),
                output_dir: "generated/ats".to_string(),
            },
            c_sources: vec![CSource {
                path: "test.h".to_string(),
                include_dirs: vec!["include".to_string()],
                description: String::new(),
            }],
            ownership_rules: vec![OwnershipRule {
                function: "test_alloc".to_string(),
                pattern: "alloc".to_string(),
                param_index: None,
                resource_type: Some("test_t".to_string()),
                description: String::new(),
            }],
            ats2: ATS2Config {
                patsopt: "patsopt".to_string(),
                patscc: "patscc".to_string(),
                flags: vec!["-DATS_MEMALLOC_LIBC".to_string()],
                c_flags: vec!["-O2".to_string()],
                patshome: Some("/usr/lib/ats2".to_string()),
            },
            workload: None,
            data: None,
            options: None,
        }
    }

    #[test]
    fn test_build_command_structure() {
        let manifest = test_manifest();
        let cmd = build_command(&manifest, "generated/ats/test_safe.dats", false)
            .expect("TODO: handle error");

        assert_eq!(cmd.program, "patscc");
        assert!(cmd.args.contains(&"-DATS_MEMALLOC_LIBC".to_string()));
        assert!(
            cmd.args
                .contains(&"generated/ats/test_safe.dats".to_string())
        );
        assert!(cmd.env.iter().any(|(k, _)| k == "PATSHOME"));
    }

    #[test]
    fn test_build_command_release() {
        let manifest = test_manifest();
        let cmd = build_command(&manifest, "test.dats", true).expect("TODO: handle error");

        // Release mode should add -O2 via -ccopt
        let ccopt_indices: Vec<usize> = cmd
            .args
            .iter()
            .enumerate()
            .filter(|(_, a)| *a == "-ccopt")
            .map(|(i, _)| i)
            .collect();
        let has_o2 = ccopt_indices
            .iter()
            .any(|&i| i + 1 < cmd.args.len() && cmd.args[i + 1] == "-O2");
        assert!(has_o2, "Release mode should add -ccopt -O2");
    }

    #[test]
    fn test_typecheck_command() {
        let manifest = test_manifest();
        let cmd = typecheck_command(&manifest, "test.dats").expect("TODO: handle error");

        assert_eq!(cmd.program, "patsopt");
        assert!(cmd.args.contains(&"--typecheck".to_string()));
        assert!(cmd.args.contains(&"test.dats".to_string()));
    }

    #[test]
    fn test_command_display() {
        let cmd = CompileCommand {
            env: vec![("PATSHOME".to_string(), "/usr/lib/ats2".to_string())],
            program: "patscc".to_string(),
            args: vec!["-o".to_string(), "out".to_string(), "in.dats".to_string()],
        };
        let display = cmd.display();
        assert!(display.contains("PATSHOME=/usr/lib/ats2"));
        assert!(display.contains("patscc"));
        assert!(display.contains("-o out in.dats"));
    }

    #[test]
    fn test_build_command_without_patshome() {
        let mut manifest = test_manifest();
        manifest.ats2.patshome = None;
        let cmd = build_command(&manifest, "test.dats", false).expect("TODO: handle error");
        assert!(cmd.env.is_empty());
    }
}
