// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Code generation for Halide from halideiser manifest.
//
// This module contains three sub-modules:
//   - parser:     validates pipeline stage sequences and resolves defaults
//   - halide_gen: generates Halide C++ algorithm and schedule code
//   - build_gen:  generates CMake build files for Halide compilation

pub mod build_gen;
pub mod halide_gen;
pub mod parser;

use anyhow::{Context, Result};
use std::fs;
use std::path::Path;

use crate::manifest::Manifest;

/// Generates the Halide generator source, runner source, and CMake configuration files.
///
/// The files are written to `output_dir` using the project name from the manifest:
/// `<name>_generator.cpp`, `<name>_runner.cpp`, and `CMakeLists.txt`.
///
/// # Arguments
///
/// * `manifest` - Project manifest containing the pipeline and generation settings.
/// * `output_dir` - Directory in which to write the generated files.
///
/// # Errors
///
/// Returns an error if the pipeline is invalid, the output directory cannot be created,
/// or any generated file cannot be written.
///
/// # Examples
///
/// ```no_run
/// # let manifest: Manifest = todo!();
/// generate_all(&manifest, "generated")?;
/// # Ok::<(), anyhow::Error>(())
/// ```
pub fn generate_all(manifest: &Manifest, output_dir: &str) -> Result<()> {
    let out = Path::new(output_dir);
    fs::create_dir_all(out).context("Failed to create output directory")?;

    // Step 1: Parse and validate the pipeline sequence.
    let resolved_pipeline =
        parser::resolve_pipeline(manifest).context("Pipeline validation failed")?;

    // Step 2: Generate the Halide C++ generator source.
    let generator_code = halide_gen::generate_halide_generator(manifest, &resolved_pipeline);
    let generator_path = out.join(format!("{}_generator.cpp", manifest.project.name));
    fs::write(&generator_path, &generator_code)
        .with_context(|| format!("Failed to write {}", generator_path.display()))?;
    println!("  [codegen] wrote {}", generator_path.display());

    // Step 3: Generate the runner source.
    let runner_code = halide_gen::generate_runner(manifest);
    let runner_path = out.join(format!("{}_runner.cpp", manifest.project.name));
    fs::write(&runner_path, &runner_code)
        .with_context(|| format!("Failed to write {}", runner_path.display()))?;
    println!("  [codegen] wrote {}", runner_path.display());

    // Step 4: Generate the CMakeLists.txt.
    let cmake_code = build_gen::generate_cmake(manifest);
    let cmake_path = out.join("CMakeLists.txt");
    fs::write(&cmake_path, &cmake_code)
        .with_context(|| format!("Failed to write {}", cmake_path.display()))?;
    println!("  [codegen] wrote {}", cmake_path.display());

    Ok(())
}

/// Builds the generated project using CMake.
///
/// The build uses `Release` mode when `release` is `true` and `Debug` mode
/// otherwise.
///
/// # Examples
///
/// ```ignore
/// build(&manifest, true)?;
/// # Ok::<(), anyhow::Error>(())
/// ```
///
/// # Errors
///
/// Returns an error if the manifest is invalid, CMake cannot be started, or
/// configuration or compilation fails.
///
/// # Arguments
///
/// * `release` - Selects the `Release` build configuration when `true`;
///   otherwise selects `Debug`.
pub fn build(manifest: &Manifest, release: bool) -> Result<()> {
    crate::manifest::validate(manifest)?;
    let build_type = if release { "Release" } else { "Debug" };
    println!(
        "Building {} ({} mode) — target: {}",
        manifest.project.name, build_type, manifest.target.arch
    );
    let source_dir = Path::new("generated/halideiser");
    let build_dir = source_dir.join("build");
    // Give single- and multi-configuration generators the same runtime layout.
    // The per-configuration variable prevents CMake appending another Release/
    // or Debug/ directory when using Ninja Multi-Config or Visual Studio.
    let runtime_dir = std::env::current_dir()?
        .join(&build_dir)
        .join("bin")
        .join(build_type);
    let configure = std::process::Command::new("cmake")
        .arg("-S")
        .arg(source_dir)
        .arg("-B")
        .arg(&build_dir)
        .arg(format!("-DCMAKE_BUILD_TYPE={build_type}"))
        .arg(format!(
            "-DCMAKE_RUNTIME_OUTPUT_DIRECTORY={}",
            runtime_dir.display()
        ))
        .arg(format!(
            "-DCMAKE_RUNTIME_OUTPUT_DIRECTORY_{}={}",
            build_type.to_uppercase(),
            runtime_dir.display()
        ))
        .status()
        .context("Failed to start CMake configuration")?;
    anyhow::ensure!(
        configure.success(),
        "CMake configuration failed: {configure}"
    );
    let compile = std::process::Command::new("cmake")
        .arg("--build")
        .arg(&build_dir)
        .arg("--config")
        .arg(build_type)
        .status()
        .context("Failed to start CMake build")?;
    anyhow::ensure!(compile.success(), "CMake build failed: {compile}");
    Ok(())
}

/// Runs the generated pipeline using the debug configuration.
///
/// # Arguments
///
/// * `args` - Arguments passed to the generated runner.
///
/// # Returns
///
/// `Ok(())` if the pipeline completes successfully; otherwise, an error.
///
/// # Examples
///
/// ```no_run
/// let manifest = Manifest::default();
/// run(&manifest, &[])?;
/// # Ok::<(), _>(())
/// ```
pub fn run(manifest: &Manifest, args: &[String]) -> Result<()> {
    run_configuration(manifest, false, args)
}

/// Executes the generated pipeline runner using the selected build configuration.
///
/// Returns an error if the manifest is invalid, the runner cannot be started, or
/// the pipeline exits unsuccessfully.
///
/// # Examples
///
/// ```no_run
/// # use crate::codegen::run_configuration;
/// # use crate::manifest::Manifest;
/// # let manifest: Manifest = todo!();
/// run_configuration(&manifest, false, &[])?;
/// # Ok::<(), anyhow::Error>(())
/// ```
pub fn run_configuration(manifest: &Manifest, release: bool, args: &[String]) -> Result<()> {
    crate::manifest::validate(manifest)?;
    println!(
        "Running {} pipeline ({} stages)",
        manifest.project.name,
        manifest.stages.len()
    );
    if !args.is_empty() {
        println!("  Extra args: {}", args.join(" "));
    }
    let build_type = if release { "Release" } else { "Debug" };
    let binary = Path::new("generated/halideiser/build/bin")
        .join(build_type)
        .join(format!(
            "{}_runner{}",
            manifest.project.name,
            std::env::consts::EXE_SUFFIX
        ));
    let status = std::process::Command::new(&binary)
        .args(args)
        .status()
        .with_context(|| {
            format!(
                "Failed to execute {}; build the pipeline first",
                binary.display()
            )
        })?;
    anyhow::ensure!(status.success(), "Pipeline execution failed: {status}");
    Ok(())
}
