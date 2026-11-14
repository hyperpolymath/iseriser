// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Code generation orchestrator for tlaiser.
//
// Coordinates generation of TLA+ specs, PlusCal algorithms, and TLC
// model checker configuration from validated manifest definitions.

pub mod parser;
pub mod pluscal_gen;
pub mod tla_gen;
pub mod tlc_gen;

use anyhow::{Context, Result};
use std::fs;
use std::path::Path;

use crate::manifest::Manifest;

/// Generate all TLA+ artifacts from a validated manifest.
///
/// For each state machine in the manifest, generates:
/// 1. A `.tla` file with the TLA+ specification (Init, Next, properties).
/// 2. A `.pcal` file with the PlusCal algorithm equivalent.
/// 3. A `.cfg` file for the TLC model checker.
/// 4. A `run_tlc.sh` script with the TLC invocation command.
///
/// All files are written to `output_dir/`.
pub fn generate_all(manifest: &Manifest, output_dir: &str) -> Result<()> {
    let out = Path::new(output_dir);
    fs::create_dir_all(out).context("Failed to create output directory")?;

    // First, validate all state machines via the parser module.
    for sm_cfg in &manifest.state_machines {
        let sm = sm_cfg.to_abi();
        parser::validate_state_machine(&sm)
            .with_context(|| format!("Validation failed for machine '{}'", sm.name))?;
    }

    // Convert properties to ABI types.
    let properties: Vec<_> = manifest.properties.iter().map(|p| p.to_abi()).collect();

    // Generate artifacts for each state machine.
    for sm_cfg in &manifest.state_machines {
        let sm = sm_cfg.to_abi();

        // TLA+ specification
        let tla_content = tla_gen::generate_tla_spec(&sm, &properties);
        let tla_path = out.join(format!("{}.tla", sm.name));
        fs::write(&tla_path, &tla_content)
            .with_context(|| format!("Failed to write {}", tla_path.display()))?;
        println!("  [tla] {}", tla_path.display());

        // PlusCal algorithm
        let pcal_content = pluscal_gen::generate_pluscal(&sm, &properties);
        let pcal_path = out.join(format!("{}PlusCal.tla", sm.name));
        fs::write(&pcal_path, &pcal_content)
            .with_context(|| format!("Failed to write {}", pcal_path.display()))?;
        println!("  [pcal] {}", pcal_path.display());

        // TLC configuration
        let cfg_content = tlc_gen::generate_tlc_cfg(&sm, &properties, &manifest.tlc);
        let cfg_path = out.join(format!("{}.cfg", sm.name));
        fs::write(&cfg_path, &cfg_content)
            .with_context(|| format!("Failed to write {}", cfg_path.display()))?;
        println!("  [cfg] {}", cfg_path.display());

        // TLC run script
        let run_content = tlc_gen::generate_run_script(&sm, &manifest.tlc);
        let run_path = out.join(format!("run_tlc_{}.sh", sm.name));
        fs::write(&run_path, &run_content)
            .with_context(|| format!("Failed to write {}", run_path.display()))?;
        println!("  [sh]  {}", run_path.display());
    }

    Ok(())
}

/// Build generated artifacts (invoke TLA+ toolbox / TLC).
///
/// Currently prints the command that would be run; actual TLC invocation
/// requires a Java runtime and the TLA+ tools jar on the PATH.
pub fn build(manifest: &Manifest, _release: bool) -> Result<()> {
    println!(
        "Building tlaiser specs for project: {}",
        manifest.project.name
    );
    for sm_cfg in &manifest.state_machines {
        println!(
            "  Would run TLC on {}.tla with {}.cfg",
            sm_cfg.name, sm_cfg.name
        );
    }
    println!("(Ensure tla2tools.jar is on your CLASSPATH or use `tlaiser run`)");
    Ok(())
}

/// Run the TLC model checker on generated specs.
///
/// Currently prints the invocation command. A future version will
/// shell out to `java -jar tla2tools.jar` directly.
pub fn run(manifest: &Manifest, _args: &[String]) -> Result<()> {
    println!("Running TLC for project: {}", manifest.project.name);
    for sm_cfg in &manifest.state_machines {
        let cmd = tlc_gen::tlc_command(&sm_cfg.name, &manifest.tlc);
        println!("  {}", cmd);
    }
    Ok(())
}
