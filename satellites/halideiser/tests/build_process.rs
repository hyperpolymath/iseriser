// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//! Execute real CMake and a host C fixture to test process orchestration.
//! This does not certify generated Halide algorithms or their schedules.
use std::{fs, process::Command};

/// Creates a temporary project fixture with a minimal configuration and generated-output directory.
///
/// # Examples
///
/// ```
/// let dir = fixture();
/// assert!(dir.path().join("halideiser.toml").is_file());
/// assert!(dir.path().join("generated/halideiser").is_dir());
/// ```
fn fixture() -> tempfile::TempDir {
    let dir = tempfile::tempdir().unwrap();
    fs::write(dir.path().join("halideiser.toml"),
        "[project]\nname = 'probe'\n[[stages]]\nname = 'blur'\noperation = 'blur'\n[target]\narch = 'x86'\n[pipeline]\ninput-format = 'png'\noutput-format = 'png'\n"
    ).unwrap();
    fs::create_dir_all(dir.path().join("generated/halideiser")).unwrap();
    dir
}

/// Runs the `halideiser` binary in the specified directory with the given arguments.
///
/// # Examples
///
/// ```no_run
/// let output = invoke(std::path::Path::new("."), &["build"]);
/// assert!(output.status.success());
/// ```
///
/// # Panics
///
/// Panics if the process cannot be started.
fn invoke(dir: &std::path::Path, args: &[&str]) -> std::process::Output {
    Command::new(env!("CARGO_BIN_EXE_halideiser"))
        .current_dir(dir)
        .args(args)
        .output()
        .unwrap()
}

#[test]
fn build_and_run_execute_and_propagate_exit_status() {
    let dir = fixture();
    let source = dir.path().join("generated/halideiser");
    fs::write(source.join("CMakeLists.txt"),
        "cmake_minimum_required(VERSION 3.22)\nproject(probe C)\nadd_executable(probe_runner probe.c)\n").unwrap();
    fs::write(source.join("probe.c"),
        "#include <string.h>\nint main(int argc, char **argv) { return argc == 2 && strcmp(argv[1], \"two words\") == 0 ? 0 : 7; }\n").unwrap();
    let output = invoke(dir.path(), &["build", "--release"]);
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        invoke(dir.path(), &["run", "--release", "--", "two words"])
            .status
            .success()
    );
    assert!(!invoke(dir.path(), &["run", "--release"]).status.success());
    // A release build must not silently satisfy a request for debug mode.
    assert!(
        !invoke(dir.path(), &["run", "--", "two words"])
            .status
            .success()
    );
}

#[test]
fn multi_configuration_generator_runs_the_selected_mode() {
    let ninja = Command::new("ninja")
        .arg("--version")
        .output()
        .is_ok_and(|output| output.status.success());
    let generator = Command::new("cmake")
        .arg("--help")
        .output()
        .is_ok_and(|output| {
            output.status.success()
                && String::from_utf8_lossy(&output.stdout).contains("Ninja Multi-Config")
        });
    if !ninja || !generator {
        // Local developers may have only a single-configuration generator.
        // CI must exercise this regression, never silently report a skipped pass.
        assert!(
            std::env::var_os("CI").is_none(),
            "CI requires Ninja and CMake with Ninja Multi-Config support"
        );
        eprintln!("SKIP: install Ninja and a CMake supporting Ninja Multi-Config to run this test");
        return;
    }
    let dir = fixture();
    let source = dir.path().join("generated/halideiser");
    fs::write(source.join("CMakeLists.txt"),
        "cmake_minimum_required(VERSION 3.22)\nproject(probe C)\nadd_executable(probe_runner probe.c)\n").unwrap();
    fs::write(source.join("probe.c"),
        "#include <stdio.h>\nint main(void) {\n#ifdef NDEBUG\nputs(\"release\");\n#else\nputs(\"debug\");\n#endif\nreturn 0; }\n").unwrap();
    for (mode, expected) in [("Release", "release"), ("Debug", "debug")] {
        let mut command = Command::new(env!("CARGO_BIN_EXE_halideiser"));
        command
            .current_dir(dir.path())
            .env("CMAKE_GENERATOR", "Ninja Multi-Config")
            .arg("build");
        if mode == "Release" {
            command.arg("--release");
        }
        let output = command.output().unwrap();
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        let args = if mode == "Release" {
            vec!["run", "--release"]
        } else {
            vec!["run"]
        };
        let output = invoke(dir.path(), &args);
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        assert!(
            String::from_utf8_lossy(&output.stdout)
                .lines()
                .any(|line| line == expected)
        );
    }
    // The second build must preserve the independently selected first artifact.
    let output = invoke(dir.path(), &["run", "--release"]);
    assert!(output.status.success());
    assert!(
        String::from_utf8_lossy(&output.stdout)
            .lines()
            .any(|line| line == "release")
    );
}

#[test]
fn missing_build_inputs_and_missing_runner_fail() {
    let dir = fixture();
    assert!(!invoke(dir.path(), &["build"]).status.success());
    assert!(!invoke(dir.path(), &["run"]).status.success());
}

#[test]
fn compilation_failure_after_successful_configuration_fails() {
    let dir = fixture();
    let source = dir.path().join("generated/halideiser");
    fs::write(source.join("CMakeLists.txt"),
        "cmake_minimum_required(VERSION 3.22)\nproject(probe C)\nadd_executable(probe_runner broken.c)\n").unwrap();
    fs::write(
        source.join("broken.c"),
        "#error planted compilation failure\n",
    )
    .unwrap();
    assert!(!invoke(dir.path(), &["build"]).status.success());
}
