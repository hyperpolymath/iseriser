#![forbid(unsafe_code)]
#![allow(
    dead_code,
    clippy::too_many_arguments,
    clippy::manual_strip,
    clippy::if_same_then_else,
    clippy::vec_init_then_push,
    clippy::upper_case_acronyms,
    clippy::format_in_format_args,
    clippy::enum_variant_names,
    clippy::module_inception,
    clippy::doc_lazy_continuation,
    clippy::manual_clamp,
    clippy::type_complexity
)]
// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
pub mod abi;
pub mod codegen;
pub mod manifest;
pub mod plugins;
pub use manifest::{Manifest, load_manifest};

/// Check all queries in a project against the type safety levels.
pub fn check(manifest_path: &str) -> anyhow::Result<Vec<codegen::CheckResult>> {
    let m = load_manifest(manifest_path)?;
    codegen::check_queries(&m, None, false)
}
