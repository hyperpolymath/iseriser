// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//! Process orchestration regressions; target compilation is tested by Provable CI.
#![cfg(unix)]
use std::{fs, os::unix::fs::PermissionsExt, process::Command};

/// Create an isolated project with configurable compiler probes and build script.
fn fixture(chpl_exit: u8, zig_exit: u8, script_exit: u8) -> tempfile::TempDir {
    let dir = tempfile::tempdir().unwrap();
    chapeliser::manifest::init_manifest(dir.path().to_str().unwrap()).unwrap();
    let tools = dir.path().join("tools");
    fs::create_dir(&tools).unwrap();
    for (name, code) in [("chpl", chpl_exit), ("zig", zig_exit)] {
        let path = tools.join(name);
        fs::write(&path, format!("#!/bin/sh\nexit {code}\n")).unwrap();
        fs::set_permissions(path, fs::Permissions::from_mode(0o755)).unwrap();
    }
    let generated = dir.path().join("generated/chapeliser");
    fs::create_dir_all(&generated).unwrap();
    fs::write(
        generated.join("build.sh"),
        format!("#!/bin/sh\nprintf '%s' \"$CHPL_FLAGS\" > invoked\nexit {script_exit}\n"),
    )
    .unwrap();
    dir
}

/// Run a release build in the fixture with only its fake tools on `PATH`.
fn build(dir: &std::path::Path) -> std::process::Output {
    let path = std::env::join_paths([dir.join("tools"), "/usr/bin".into(), "/bin".into()]).unwrap();
    Command::new(env!("CARGO_BIN_EXE_chapeliser"))
        .current_dir(dir)
        .env("PATH", path)
        .args(["build", "--release"])
        .output()
        .unwrap()
}

/// The generated build script runs from its directory with release flags forwarded.
#[test]
fn build_runs_in_generated_directory_and_forwards_mode() {
    let dir = fixture(0, 0, 0);
    let output = build(dir.path());
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(
        fs::read_to_string(dir.path().join("generated/chapeliser/invoked")).unwrap(),
        "--fast"
    );
}

/// A failed Chapel or Zig probe prevents the generated build script from running.
#[test]
fn failed_compiler_probe_does_not_run_build_script() {
    for (chpl, zig) in [(7, 0), (0, 7)] {
        let dir = fixture(chpl, zig, 0);
        assert!(!build(dir.path()).status.success());
        assert!(!dir.path().join("generated/chapeliser/invoked").exists());
    }
}

/// A generated build-script failure is propagated to the caller.
#[test]
fn failed_build_script_is_not_reported_as_success() {
    let dir = fixture(0, 0, 9);
    assert!(!build(dir.path()).status.success());
    assert!(dir.path().join("generated/chapeliser/invoked").exists());
}
