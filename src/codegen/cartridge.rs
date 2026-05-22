// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Cartridge scaffolder — emits a complete boj-server cartridge skeleton
// (adapter + FFI + ABI + cartridge.json + panels + mod.js) for a new
// -iser, modelled on the k9iser-mcp pilot (boj-server#73).
//
// Output topology: <output_dir>/<iser_name>-mcp/
//
// The output is meant to be placed inside `boj-server/cartridges/`; the
// emitted ffi/build.zig references the shared ADR-0006 invoke-shim via
// `../../../ffi/zig/src/cartridge_shim.zig`, which only resolves when the
// cartridge sits at `boj-server/cartridges/<name>-mcp/`.
//
// Tracks hyperpolymath/standards#89 Phase 2b.

use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};

use crate::abi::GeneratedFile;
use crate::manifest::Manifest;

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Outcome of a cartridge scaffold operation.
#[derive(Debug)]
pub enum CartridgeScaffoldResult {
    Success(CartridgeRepo),
    OutputError(String),
}

impl CartridgeScaffoldResult {
    pub fn is_success(&self) -> bool {
        matches!(self, CartridgeScaffoldResult::Success(_))
    }
    pub fn repo(&self) -> Option<&CartridgeRepo> {
        match self {
            CartridgeScaffoldResult::Success(r) => Some(r),
            _ => None,
        }
    }
    pub fn error_message(&self) -> Option<&str> {
        match self {
            CartridgeScaffoldResult::OutputError(msg) => Some(msg),
            _ => None,
        }
    }
}

/// A scaffolded boj-server cartridge.
#[derive(Debug)]
pub struct CartridgeRepo {
    /// Cartridge name (e.g. "chapeliser-mcp").
    pub name: String,
    /// Root directory where the cartridge was written.
    pub root: PathBuf,
    /// All generated files (relative paths + content).
    pub files: Vec<GeneratedFile>,
}

impl CartridgeRepo {
    pub fn file_count(&self) -> usize {
        self.files.len()
    }

    /// True iff every mandatory directory + file is present.
    pub fn is_complete(&self) -> bool {
        let paths: Vec<String> = self
            .files
            .iter()
            .map(|f| f.path.display().to_string())
            .collect();
        let has = |needle: &str| paths.iter().any(|p| p.contains(needle));

        has("cartridge.json")
            && has("mod.js")
            && has("panels/manifest.json")
            && has("abi/")
            && has("ffi/")
            && has("adapter/")
            && has("README.adoc")
    }
}

/// Scaffold a boj-server cartridge skeleton for the given manifest.
///
/// Writes `<output_dir>/<iser_name>-mcp/` and all its contents.
pub fn scaffold_cartridge(
    manifest: &Manifest,
    output_dir: &Path,
) -> CartridgeScaffoldResult {
    let model = manifest.to_language_model();
    let iser_name = model.iser_name();
    let cartridge_name = format!("{}-mcp", iser_name);
    let module_name = idris2_module_name(&iser_name);
    let mcp_module = format!("{}Mcp", module_name);
    let lib_name = format!("{}_mcp", iser_name.replace('-', "_"));
    let lang_name = model.name.clone();

    let ctx = TemplateCtx {
        iser_name: iser_name.clone(),
        cartridge_name: cartridge_name.clone(),
        module_name,
        mcp_module,
        lib_name,
        lang_name,
    };

    let mut files: Vec<GeneratedFile> = Vec::new();

    // Top-level files
    files.push(generate_readme(&ctx));
    files.push(generate_cartridge_json(&ctx));
    files.push(generate_mod_js(&ctx));

    // Panels
    files.push(generate_panels_manifest(&ctx));

    // Idris2 ABI
    files.push(generate_abi_readme(&ctx));
    files.push(generate_ipkg(&ctx));
    files.push(generate_safe_idr(&ctx));

    // Zig FFI
    files.push(generate_ffi_readme(&ctx));
    files.push(generate_ffi_build_zig(&ctx));
    files.push(generate_ffi_zig(&ctx));

    // Unified gated adapter
    files.push(generate_adapter_readme(&ctx));
    files.push(generate_adapter_build_zig(&ctx));
    files.push(generate_adapter_zig(&ctx));

    let root = output_dir.join(&cartridge_name);
    if let Err(e) = write_files(&root, &files) {
        return CartridgeScaffoldResult::OutputError(format!(
            "Failed to write to {}: {}",
            root.display(),
            e
        ));
    }

    CartridgeScaffoldResult::Success(CartridgeRepo {
        name: cartridge_name,
        root,
        files,
    })
}

fn write_files(root: &Path, files: &[GeneratedFile]) -> Result<()> {
    for file in files {
        let full_path = root.join(&file.path);
        if let Some(parent) = full_path.parent() {
            fs::create_dir_all(parent)
                .with_context(|| format!("Failed to create directory: {}", parent.display()))?;
        }
        fs::write(&full_path, &file.content)
            .with_context(|| format!("Failed to write: {}", full_path.display()))?;
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// Template context
// ---------------------------------------------------------------------------

struct TemplateCtx {
    /// e.g. "chapeliser"
    iser_name: String,
    /// e.g. "chapeliser-mcp"
    cartridge_name: String,
    /// Pascal-cased iser name. e.g. "Chapeliser"
    module_name: String,
    /// Pascal-cased Mcp module. e.g. "ChapeliserMcp"
    mcp_module: String,
    /// Underscored library name. e.g. "chapeliser_mcp"
    lib_name: String,
    /// Language name from the manifest. e.g. "Chapel"
    lang_name: String,
}

impl TemplateCtx {
    fn render(&self, template: &str) -> String {
        template
            .replace("__CARTRIDGE_NAME__", &self.cartridge_name)
            .replace("__ISER_NAME__", &self.iser_name)
            .replace("__MCP_MODULE__", &self.mcp_module)
            .replace("__MODULE_NAME__", &self.module_name)
            .replace("__LIB_NAME__", &self.lib_name)
            .replace("__LANG_NAME__", &self.lang_name)
    }
}

fn idris2_module_name(iser_name: &str) -> String {
    let mut chars = iser_name.chars();
    match chars.next() {
        Some(c) => c.to_uppercase().to_string() + chars.as_str(),
        None => iser_name.to_string(),
    }
}

// ---------------------------------------------------------------------------
// File generators — top-level
// ---------------------------------------------------------------------------

fn generate_readme(ctx: &TemplateCtx) -> GeneratedFile {
    let content = ctx.render(
        r#"= __CARTRIDGE_NAME__
:toc:
:toclevels: 2

A boj-server cartridge skeleton for __LANG_NAME__, scaffolded by iseriser
(hyperpolymath/standards#89 Phase 2b).

== Topology

[source]
----
boj-server/cartridges/__CARTRIDGE_NAME__/
├── cartridge.json          — registration manifest (boj.dev schema v1)
├── mod.js                  — Deno module entry (JS-worker fallback path)
├── README.adoc             — this file
├── panels/manifest.json    — observability panel registration
├── abi/                    — Idris2 ABI (source of truth)
├── ffi/                    — Zig FFI implementing ADR-0006 5-symbol interface
└── adapter/                — Unified transaction-gated adapter (loopback)
----

== Build

The cartridge presumes it lives inside `boj-server/cartridges/`; the
`ffi/build.zig` and `adapter/build.zig` reference the shared invoke-shim
at `boj-server/ffi/zig/src/cartridge_shim.zig` via `../../../`.

[source,shell]
----
cd ffi && zig build test           # FFI test suite
cd ../adapter && zig build test    # adapter test suite
cd ../abi && idris2 --build __CARTRIDGE_NAME__.ipkg
----

== Status

Skeleton-only. The state machine, tool dispatch bodies, and per-tool
business logic are stubs — replace with real implementations as you
build out __ISER_NAME__'s regeneration pipeline. The exposure/transaction
gate is filled in (mirrors the Idris2 contract) and ready for production.

== References

- ADR-0004 — http-capability-gateway tier-2 (cartridge adapters are
  internal/loopback, never public)
- ADR-0006 — five-symbol cartridge C ABI
  (`boj_cartridge_init`/`deinit`/`name`/`version`/`invoke`)
- Pilot: `boj-server/cartridges/k9iser-mcp/`
- Tracking: hyperpolymath/standards#89, #90, #91
"#,
    );
    GeneratedFile {
        path: PathBuf::from("README.adoc"),
        content,
    }
}

fn generate_cartridge_json(ctx: &TemplateCtx) -> GeneratedFile {
    let content = ctx.render(
        r#"{
  "$schema": "https://boj.dev/schemas/cartridge/v1.json",
  "spdx": "MPL-2.0",
  "copyright": "Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>",
  "name": "__CARTRIDGE_NAME__",
  "version": "0.1.0",
  "description": "__LANG_NAME__ -iser cartridge skeleton — regeneration pipeline (scaffold)",
  "domain": "scaffold",
  "tier": "Ayo",
  "protocols": [
    "MCP",
    "REST"
  ],
  "auth": {
    "method": "none",
    "env_var": null,
    "credential_source": null
  },
  "api": {
    "base_url": "local://__CARTRIDGE_NAME__",
    "content_type": "application/json"
  },
  "tools": [
    {
      "name": "__ISER_NAME___generate",
      "description": "Regenerate __ISER_NAME__ output for a target repository (skeleton tool — replace with real implementation)",
      "inputSchema": {
        "type": "object",
        "properties": {
          "repo": {
            "type": "string",
            "description": "owner/name of the repository"
          },
          "branch": {
            "type": "string",
            "description": "Target branch"
          }
        },
        "required": [
          "repo"
        ]
      }
    }
  ],
  "ffi": {
    "so_path": "ffi/zig-out/lib/lib__LIB_NAME__.so",
    "abi_version": "ADR-0006",
    "symbols": [
      "boj_cartridge_init",
      "boj_cartridge_deinit",
      "boj_cartridge_name",
      "boj_cartridge_version",
      "boj_cartridge_invoke"
    ]
  }
}
"#,
    );
    GeneratedFile {
        path: PathBuf::from("cartridge.json"),
        content,
    }
}

fn generate_mod_js(ctx: &TemplateCtx) -> GeneratedFile {
    let content = ctx.render(
        r#"// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// __CARTRIDGE_NAME__/mod.js — JS-worker fallback path for the cartridge.
//
// boj_rest dispatches FFI cartridges to the Zig adapter; this module is
// the Deno fallback only used if the FFI path is unavailable. Delegates
// to a backend at http://127.0.0.1:7744 (override with __ISER_NAME___BACKEND_URL).

const BASE_URL = Deno.env.get("__ISER_NAME___BACKEND_URL".toUpperCase()) ?? "http://127.0.0.1:7744";
const TIMEOUT_MS = 15_000;

async function post(path, payload) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), TIMEOUT_MS);
  try {
    const r = await fetch(`${BASE_URL}${path}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
      signal: ctrl.signal,
    });
    const data = await r.json().catch(() => ({ success: false, error: "non-JSON response" }));
    return { status: r.status, data };
  } catch (e) {
    if (e.name === "AbortError") return { status: 504, data: { success: false, error: "__CARTRIDGE_NAME__ backend timed out" } };
    return { status: 503, data: { success: false, error: `__CARTRIDGE_NAME__ backend unavailable: ${e.message}` } };
  } finally { clearTimeout(t); }
}

export async function handleTool(toolName, args) {
  switch (toolName) {
    case "__ISER_NAME___generate":
      return post("/api/v1/__ISER_NAME___generate", args ?? {});
    default:
      return { status: 404, data: { error: `Unknown tool: ${toolName}` } };
  }
}
"#,
    );
    GeneratedFile {
        path: PathBuf::from("mod.js"),
        content,
    }
}

fn generate_panels_manifest(ctx: &TemplateCtx) -> GeneratedFile {
    let content = ctx.render(
        r##"{
  "$schema": "https://panll.dev/schemas/panel-manifest/v1.json",
  "spdx": "MPL-2.0",
  "cartridge": "__CARTRIDGE_NAME__",
  "domain": "__LANG_NAME__ -iser regeneration",
  "version": "0.1.0",
  "panels": [
    {
      "id": "__ISER_NAME__-status",
      "title": "__ISER_NAME__ Engine Status",
      "description": "Regeneration backend readiness",
      "type": "status-indicator",
      "data_source": {
        "endpoint": "/cartridge/__CARTRIDGE_NAME__/invoke",
        "method": "POST",
        "body": { "tool": "status" },
        "refresh_interval_ms": 5000
      },
      "widgets": [
        {
          "type": "state-badge",
          "field": "state",
          "states": {
            "ready":    { "color": "#2ecc71", "icon": "shield-check" },
            "degraded": { "color": "#f39c12", "icon": "alert-circle" },
            "error":    { "color": "#e74c3c", "icon": "alert-triangle" }
          }
        },
        { "type": "text", "field": "version", "label": "Version" }
      ]
    }
  ]
}
"##,
    );
    GeneratedFile {
        path: PathBuf::from("panels/manifest.json"),
        content,
    }
}

// ---------------------------------------------------------------------------
// File generators — Idris2 ABI
// ---------------------------------------------------------------------------

fn generate_abi_readme(ctx: &TemplateCtx) -> GeneratedFile {
    let content = ctx.render(
        r#"= __CARTRIDGE_NAME__ — Idris2 ABI

Source of truth for the cartridge's interface contract. The Zig FFI
(`../ffi/__ISER_NAME___ffi.zig`) and the unified adapter
(`../adapter/__ISER_NAME___adapter.zig`) mirror the definitions here.

== Modules

- `__MCP_MODULE__.Safe__MODULE_NAME__` — exposure-gate contract,
  tool enumeration, and the C-ABI bridge declarations.

== Build

[source,shell]
----
idris2 --check __CARTRIDGE_NAME__.ipkg
----

== Conformance

The Zig `exposureSatisfied` mirror in
`../adapter/__ISER_NAME___adapter.zig` is cross-checked against this
module's contract by the adapter's truth-table tests.
"#,
    );
    GeneratedFile {
        path: PathBuf::from("abi/README.adoc"),
        content,
    }
}

fn generate_ipkg(ctx: &TemplateCtx) -> GeneratedFile {
    let lower_pkg = ctx.cartridge_name.replace('-', "");
    let content = format!(
        r#"-- SPDX-License-Identifier: MPL-2.0
package {pkg}

authors    = "Jonathan D.A. Jewell"
version    = 0.1.0
license    = "MPL-2.0"
brief      = "{cartridge} cartridge — {lang} -iser regeneration"

sourcedir  = "."
modules    = {mcp}.Safe{module}
depends    = base, contrib
"#,
        pkg = lower_pkg,
        cartridge = ctx.cartridge_name,
        lang = ctx.lang_name,
        mcp = ctx.mcp_module,
        module = ctx.module_name,
    );
    GeneratedFile {
        path: PathBuf::from(format!("abi/{}.ipkg", ctx.cartridge_name)),
        content,
    }
}

fn generate_safe_idr(ctx: &TemplateCtx) -> GeneratedFile {
    let content = ctx.render(
        r#"-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
||| __MCP_MODULE__.Safe__MODULE_NAME__: cartridge interface contract.
|||
||| Cartridge: __CARTRIDGE_NAME__
||| Skeleton scaffolded by iseriser (standards#89 Phase 2b).
|||
||| Source of truth for:
|||   - The exposure / transaction-gate (mirrored by the Zig adapter).
|||   - MCP tool enumeration (mirrored by ffi/__ISER_NAME___ffi.zig).
|||   - C-ABI gate bridge (k9_exposure_satisfied analogue).
module __MCP_MODULE__.Safe__MODULE_NAME__

import Data.List

%default total

-- ═══════════════════════════════════════════════════════════════════════════
-- MCP Tool Definitions
-- ═══════════════════════════════════════════════════════════════════════════

||| MCP tools exposed by this cartridge.  Grow as the cartridge gains tools.
public export
data McpTool
  = ToolGenerate       -- Regenerate __ISER_NAME__ output
  | ToolStatus         -- Health check

||| MCP tool name (JSON-RPC method form).
public export
toolName : McpTool -> String
toolName ToolGenerate = "__ISER_NAME__/generate"
toolName ToolStatus   = "__ISER_NAME__/status"

-- ═══════════════════════════════════════════════════════════════════════════
-- Exposure / transaction-gating contract (BoJ interface-safety policy)
-- ═══════════════════════════════════════════════════════════════════════════
-- A port boundary must never be a gatekeeperless gateway: every adapter
-- exposes the unified ABI ONLY behind this transaction gate. Mirrors
-- BojRest.TrustPolicy: caller exposure derived from the cartridge's
-- auth.method, loopback callers locally trusted, X-Trust-Level enforced.

||| Caller trust the gateway/sidecar has established.
public export
data Exposure = Public | Authenticated | Internal

||| Required exposure inferred from cartridge auth.method.
||| "none"/absent → Public; any credential-bearing method → Authenticated.
public export
requiredExposure : (authMethodIsNone : Bool) -> Exposure
requiredExposure True  = Public
requiredExposure False = Authenticated

||| The transaction gate.  Loopback callers are locally trusted (mcp-bridge,
||| local curl).  Otherwise the presented X-Trust-Level must meet the
||| required exposure.  This is the total relation the Zig transaction layer
||| mirrors; no dispatch may occur unless it returns True.
public export
exposureSatisfied : (required : Exposure) -> (presented : Exposure) -> (isLocal : Bool) -> Bool
exposureSatisfied _             _             True  = True
exposureSatisfied Public        _             _     = True
exposureSatisfied Authenticated Authenticated _     = True
exposureSatisfied Authenticated Internal      _     = True
exposureSatisfied Internal      Internal      _     = True
exposureSatisfied _             _             _     = False

||| FFI: 1 if dispatch is permitted, 0 if the gate rejects.
||| req/pres encoding: 0=Public 1=Authenticated 2=Internal; isLocal: 1/0.
export
__ISER_NAME___exposure_satisfied : Int -> Int -> Int -> Int
__ISER_NAME___exposure_satisfied req pres isLocal =
  let r = case req  of { 0 => Public; 1 => Authenticated; _ => Internal }
      p = case pres of { 0 => Public; 1 => Authenticated; _ => Internal }
  in if exposureSatisfied r p (isLocal /= 0) then 1 else 0
"#,
    );
    GeneratedFile {
        path: PathBuf::from(format!(
            "abi/{}/Safe{}.idr",
            ctx.mcp_module, ctx.module_name
        )),
        content,
    }
}

// ---------------------------------------------------------------------------
// File generators — Zig FFI
// ---------------------------------------------------------------------------

fn generate_ffi_readme(ctx: &TemplateCtx) -> GeneratedFile {
    let content = ctx.render(
        r#"= __CARTRIDGE_NAME__ — Zig FFI

Implements the ADR-0006 five-symbol cartridge interface:

- `boj_cartridge_init() -> i32`
- `boj_cartridge_deinit() -> void`
- `boj_cartridge_name() -> [*:0]const u8`
- `boj_cartridge_version() -> [*:0]const u8`
- `boj_cartridge_invoke(tool_name, json_args, out_buf, in_out_len) -> i32`

The dispatch table inside `boj_cartridge_invoke` mirrors the MCP tool
enumeration in `../abi/__MCP_MODULE__/Safe__MODULE_NAME__.idr`.

== Build

[source,shell]
----
zig build test     # run tests
zig build lib      # produce shared library (zig-out/lib/lib__LIB_NAME__.so)
----

The build references the shared invoke-shim at
`../../../ffi/zig/src/cartridge_shim.zig`; the cartridge MUST live under
`boj-server/cartridges/__CARTRIDGE_NAME__/` for that relative path to
resolve.
"#,
    );
    GeneratedFile {
        path: PathBuf::from("ffi/README.adoc"),
        content,
    }
}

fn generate_ffi_build_zig(ctx: &TemplateCtx) -> GeneratedFile {
    let content = ctx.render(
        r#"// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// __CARTRIDGE_NAME__ — Zig FFI build configuration (Zig 0.15+).

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Shared ADR-0006 invoke-shim module (relative path up to boj-server trunk).
    const shim_mod = b.addModule("cartridge_shim", .{
        .root_source_file = b.path("../../../ffi/zig/src/cartridge_shim.zig"),
        .target = target,
        .optimize = optimize,
    });

    const ffi_mod = b.addModule("__ISER_NAME___ffi", .{
        .root_source_file = b.path("__ISER_NAME___ffi.zig"),
        .target = target,
        .optimize = optimize,
    });
    ffi_mod.addImport("cartridge_shim", shim_mod);

    // ── Tests ────────────────────────────────────────────────────────
    const ffi_tests = b.addTest(.{
        .root_module = ffi_mod,
    });

    const run_tests = b.addRunArtifact(ffi_tests);

    const test_step = b.step("test", "Run __CARTRIDGE_NAME__ FFI tests");
    test_step.dependOn(&run_tests.step);

    // ── Shared library ──────────────────────────────────────────────
    const lib_mod = b.createModule(.{
        .root_source_file = b.path("__ISER_NAME___ffi.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_mod.addImport("cartridge_shim", shim_mod);

    const lib = b.addLibrary(.{
        .name = "__LIB_NAME__",
        .root_module = lib_mod,
        .linkage = .dynamic,
    });
    b.installArtifact(lib);

    const lib_step = b.step("lib", "Build shared library");
    lib_step.dependOn(&lib.step);
}
"#,
    );
    GeneratedFile {
        path: PathBuf::from("ffi/build.zig"),
        content,
    }
}

fn generate_ffi_zig(ctx: &TemplateCtx) -> GeneratedFile {
    let content = ctx.render(
        r#"// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// __CARTRIDGE_NAME__ — Zig FFI: implements the ADR-0006 5-symbol cartridge
// interface and the boj_cartridge_invoke dispatch table.  The dispatch
// arms are stubs; replace each one as you wire in real __ISER_NAME__ logic.

const std = @import("std");
const shim = @import("cartridge_shim");

// ═══════════════════════════════════════════════════════════════════════
// ADR-0006 standard cartridge interface (5 symbols)
// ═══════════════════════════════════════════════════════════════════════

pub export fn boj_cartridge_init() c_int {
    return 0;
}

pub export fn boj_cartridge_deinit() void {}

pub export fn boj_cartridge_name() [*:0]const u8 {
    return "__CARTRIDGE_NAME__";
}

pub export fn boj_cartridge_version() [*:0]const u8 {
    return "0.1.0";
}

// ═══════════════════════════════════════════════════════════════════════
// ADR-0006 dispatch
// ═══════════════════════════════════════════════════════════════════════

/// Dispatch table for the cartridge.json MCP tools.  Each arm is a stub
/// returning a placeholder JSON body; replace with real implementations.
pub export fn boj_cartridge_invoke(
    tool_name: [*c]const u8,
    json_args: [*c]const u8,
    out_buf: [*c]u8,
    in_out_len: [*c]usize,
) callconv(.c) i32 {
    _ = json_args;
    if (shim.invokeArgsNull(tool_name, out_buf, in_out_len)) return shim.RC_BAD_ARGS;

    const body: []const u8 = if (shim.toolIs(tool_name, "__ISER_NAME___generate"))
        "{\"result\":{\"status\":\"stub\"}}"
    else
        return shim.RC_UNKNOWN_TOOL;

    return shim.writeResult(out_buf, in_out_len, body);
}

// ═══════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════

test "invoke: declared tool succeeds" {
    var buf: [256]u8 = undefined;
    var len: usize = buf.len;
    const rc = boj_cartridge_invoke("__ISER_NAME___generate", "{}", &buf, &len);
    try std.testing.expectEqual(@as(i32, 0), rc);
    try std.testing.expect(std.mem.indexOf(u8, buf[0..len], "result") != null);
}

test "invoke: unknown tool returns -1" {
    var buf: [64]u8 = undefined;
    var len: usize = buf.len;
    const rc = boj_cartridge_invoke("nope", "{}", &buf, &len);
    try std.testing.expectEqual(@as(i32, -1), rc);
}

test "invoke: buffer too small returns -3" {
    var buf: [4]u8 = undefined;
    var len: usize = buf.len;
    const rc = boj_cartridge_invoke("__ISER_NAME___generate", "{}", &buf, &len);
    try std.testing.expectEqual(@as(i32, -3), rc);
    try std.testing.expect(len > 4);
}

test "name and version are non-empty" {
    const name = std.mem.span(boj_cartridge_name());
    const version = std.mem.span(boj_cartridge_version());
    try std.testing.expect(name.len > 0);
    try std.testing.expect(version.len > 0);
}
"#,
    );
    GeneratedFile {
        path: PathBuf::from(format!("ffi/{}_ffi.zig", ctx.iser_name)),
        content,
    }
}

// ---------------------------------------------------------------------------
// File generators — unified gated adapter
// ---------------------------------------------------------------------------

fn generate_adapter_readme(ctx: &TemplateCtx) -> GeneratedFile {
    let content = ctx.render(
        r#"= __CARTRIDGE_NAME__ — Unified gated adapter

Internal-only adapter that fronts the ADR-0006 cartridge ABI with a single
loopback listener, protocol-routed (REST + SSE + GraphQL + gRPC-compat),
behind the transaction gate (mirrors the Idris2 `exposureSatisfied`
contract in `../abi/__MCP_MODULE__/Safe__MODULE_NAME__.idr`).

== Routes

[cols="1m,2"]
|===
| POST /invoke            | REST            (JSON in/out)
| POST /sse               | SSE             (text/event-stream)
| POST /graphql           | GraphQL         (op parsed from body)
| POST /grpc/<Svc>/<Mthd> | gRPC-compat     (tool = method)
|===

Every request passes the transaction gate BEFORE dispatch.  No request
reaches the ABI ungated.

== Build

[source,shell]
----
zig build              # produce adapter binary
zig build test         # run the unified-adapter test suite
----

The adapter binds 127.0.0.1:9390 by construction; the only governed
public surface is the http-capability-gateway (ADR-0004) in front.
"#,
    );
    GeneratedFile {
        path: PathBuf::from("adapter/README.adoc"),
        content,
    }
}

fn generate_adapter_build_zig(ctx: &TemplateCtx) -> GeneratedFile {
    let content = ctx.render(
        r#"// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// __CARTRIDGE_NAME__/adapter/build.zig

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const shim_mod = b.addModule("cartridge_shim", .{
        .root_source_file = b.path("../../../ffi/zig/src/cartridge_shim.zig"),
        .target = target,
        .optimize = optimize,
    });

    const ffi_mod = b.createModule(.{
        .root_source_file = b.path("../ffi/__ISER_NAME___ffi.zig"),
        .target = target,
        .optimize = optimize,
    });
    ffi_mod.addImport("cartridge_shim", shim_mod);

    const adapter_mod = b.createModule(.{
        .root_source_file = b.path("__ISER_NAME___adapter.zig"),
        .target = target,
        .optimize = optimize,
    });
    adapter_mod.addImport("__ISER_NAME___ffi", ffi_mod);

    const adapter = b.addExecutable(.{
        .name = "__ISER_NAME___adapter",
        .root_module = adapter_mod,
    });
    b.installArtifact(adapter);

    // Unified-adapter tests (classify/toolFor/dispatch → one Zig ABI).
    const adapter_tests = b.addTest(.{ .root_module = adapter_mod });
    const run_tests = b.addRunArtifact(adapter_tests);
    const test_step = b.step("test", "Run __CARTRIDGE_NAME__ unified adapter tests");
    test_step.dependOn(&run_tests.step);
}
"#,
    );
    GeneratedFile {
        path: PathBuf::from("adapter/build.zig"),
        content,
    }
}

fn generate_adapter_zig(ctx: &TemplateCtx) -> GeneratedFile {
    let content = ctx.render(
        r#"// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// __CARTRIDGE_NAME__/adapter/__ISER_NAME___adapter.zig
//
// INTERNAL-ONLY unified adapter. This is NOT a public ingress. Per
// ADR-0004 the only governed public surface is the http-capability-gateway
// (tier-2) in front of the unified Zig core; cartridge adapters bind
// loopback and sit behind it. One listener, one port, protocol-routed
// (REST + SSE + GraphQL + gRPC-compat) into a SINGLE transaction-gated
// dispatch → the one Zig ABI (ffi.boj_cartridge_invoke). Deliberately NOT
// N parallel servers and NOT a public listener.
//
//   POST /invoke            → REST            (JSON in/out)
//   POST /sse               → SSE             (text/event-stream)
//   POST /graphql           → GraphQL         (op parsed from body)
//   POST /grpc/<Svc>/<Mthd> → gRPC-compat     (tool = method)
//
// Every request passes the transaction gate (exposureGate, mirroring the
// Idris2 __MCP_MODULE__.Safe__MODULE_NAME__.exposureSatisfied contract)
// BEFORE dispatch.  No request reaches the ABI ungated — this boundary
// is not a gatekeeperless gateway (estate interface-safety policy).

const std = @import("std");
const ffi = @import("__ISER_NAME___ffi");

// Loopback-only by construction: this adapter is internal, fronted by the
// http-capability-gateway (ADR-0004). Never bind a routable interface.
const BIND_IP = [4]u8{ 127, 0, 0, 1 };
const PORT: u16 = 9390;

// ── Transaction gate (mirrors Idris2 Safe__MODULE_NAME__.exposureSatisfied) ──
//
// Encoding matches the Idris2 contract: 0=Public 1=Authenticated 2=Internal.
const Exposure = enum(u8) { public = 0, authenticated = 1, internal = 2 };

// __CARTRIDGE_NAME__ cartridge.json: auth.method = "none" → requiredExposure = Public.
const REQUIRED_EXPOSURE: Exposure = .public;

/// Zig mirror of Idris2 `exposureSatisfied`. Cross-checked by the truth-table
/// test below; the Idris2 module is the source-of-truth contract.
fn exposureSatisfied(required: Exposure, presented: Exposure, is_local: bool) bool {
    if (is_local) return true; // loopback callers are locally trusted
    return switch (required) {
        .public => true,
        .authenticated => presented == .authenticated or presented == .internal,
        .internal => presented == .internal,
    };
}

/// Parse the `X-Trust-Level` request header the gateway/sidecar sets.
/// Missing/unknown → Public (conservative). Case-insensitive header name.
fn presentedExposure(req: []const u8) Exposure {
    const val = headerValue(req, "x-trust-level") orelse return .public;
    if (eqIgnoreCase(val, "internal")) return .internal;
    if (eqIgnoreCase(val, "authenticated")) return .authenticated;
    return .public;
}

fn eqIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| if (std.ascii.toLower(x) != std.ascii.toLower(y)) return false;
    return true;
}

/// Case-insensitive single-header lookup over a raw HTTP/1.1 request.
fn headerValue(req: []const u8, name: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, req, '\n');
    _ = lines.next(); // request line
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, "\r");
        if (line.len == 0) break; // end of headers
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        if (eqIgnoreCase(std.mem.trim(u8, line[0..colon], " "), name))
            return std.mem.trim(u8, line[colon + 1 ..], " ");
    }
    return null;
}

const Dispatch = struct { status: u16, body: []const u8 };

/// The single point where every protocol converges onto the one Zig ABI.
fn dispatch(tool: []const u8, args_json: []const u8, out: []u8) Dispatch {
    var tnbuf: [128]u8 = undefined;
    if (tool.len == 0 or tool.len >= tnbuf.len)
        return .{ .status = 400, .body = "{\"error\":\"bad-tool\"}" };
    @memcpy(tnbuf[0..tool.len], tool);
    tnbuf[tool.len] = 0;

    var abuf: [4096]u8 = undefined;
    const a = if (args_json.len == 0) "{}" else args_json;
    if (a.len >= abuf.len)
        return .{ .status = 413, .body = "{\"error\":\"args-too-large\"}" };
    @memcpy(abuf[0..a.len], a);
    abuf[a.len] = 0;

    var len: usize = out.len;
    const rc = ffi.boj_cartridge_invoke(@ptrCast(&tnbuf), @ptrCast(&abuf), @ptrCast(out.ptr), &len);
    return switch (rc) {
        0 => .{ .status = 200, .body = out[0..len] },
        -1 => .{ .status = 404, .body = "{\"error\":\"unknown-tool\"}" },
        -2 => .{ .status = 400, .body = "{\"error\":\"bad-args\"}" },
        -3 => .{ .status = 500, .body = "{\"error\":\"buffer-too-small\"}" },
        else => .{ .status = 500, .body = "{\"error\":\"invoke-failed\"}" },
    };
}

const Protocol = enum { rest, sse, graphql, grpc, unknown };

fn classify(path: []const u8) Protocol {
    if (std.mem.startsWith(u8, path, "/invoke")) return .rest;
    if (std.mem.startsWith(u8, path, "/sse")) return .sse;
    if (std.mem.startsWith(u8, path, "/graphql")) return .graphql;
    if (std.mem.startsWith(u8, path, "/grpc/")) return .grpc;
    return .unknown;
}

fn toolFor(proto: Protocol, path: []const u8, body: []const u8) ?[]const u8 {
    switch (proto) {
        .grpc => {
            var it = std.mem.splitScalar(u8, path, '/');
            _ = it.next(); // ""
            _ = it.next(); // "grpc"
            _ = it.next(); // service
            return it.next();
        },
        .rest, .sse => {
            if (std.mem.indexOf(u8, path, "tool=")) |q| {
                const rest = path[q + 5 ..];
                const end = std.mem.indexOfAny(u8, rest, "& ") orelse rest.len;
                if (end > 0) return rest[0..end];
            }
            return jsonStringField(body, "tool");
        },
        .graphql => {
            // Single-tool default — grow as cartridge.json declares more.
            if (std.mem.indexOf(u8, body, "__ISER_NAME___generate") != null) return "__ISER_NAME___generate";
            return null;
        },
        .unknown => return null,
    }
}

fn jsonStringField(body: []const u8, key: []const u8) ?[]const u8 {
    var kbuf: [64]u8 = undefined;
    if (key.len + 2 >= kbuf.len) return null;
    kbuf[0] = '"';
    @memcpy(kbuf[1 .. 1 + key.len], key);
    kbuf[1 + key.len] = '"';
    const needle = kbuf[0 .. key.len + 2];
    const k = std.mem.indexOf(u8, body, needle) orelse return null;
    var i = k + needle.len;
    while (i < body.len and (body[i] == ':' or body[i] == ' ')) : (i += 1) {}
    if (i >= body.len or body[i] != '"') return null;
    i += 1;
    const start = i;
    while (i < body.len and body[i] != '"') : (i += 1) {}
    if (i > start) return body[start..i] else return null;
}

fn writeHttp(stream: std.net.Stream, status: u16, ctype: []const u8, body: []const u8) void {
    var hdr: [256]u8 = undefined;
    const h = std.fmt.bufPrint(&hdr, "HTTP/1.1 {d} OK\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n", .{ status, ctype, body.len }) catch return;
    _ = stream.write(h) catch {};
    _ = stream.write(body) catch {};
}

fn writeSse(stream: std.net.Stream, d: Dispatch) void {
    const head = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n";
    _ = stream.write(head) catch {};
    _ = stream.write("event: open\ndata: {\"cartridge\":\"__CARTRIDGE_NAME__\"}\n\n") catch {};
    var fb: [4608]u8 = undefined;
    const ev = if (d.status == 200) "result" else "error";
    const frame = std.fmt.bufPrint(&fb, "event: {s}\ndata: {s}\n\n", .{ ev, d.body }) catch "event: error\ndata: {}\n\n";
    _ = stream.write(frame) catch {};
    _ = stream.write("event: done\ndata: {}\n\n") catch {};
}

// Loopback-only listener ⇒ peers are local by construction. We still
// evaluate the gate every request (no gatekeeperless path); the
// non-local branch is exercised by exposureSatisfied's tests.
fn handleConnection(stream: std.net.Stream) void {
    defer stream.close();
    var buf: [8192]u8 = undefined;
    const n = stream.read(&buf) catch return;
    const req = buf[0..n];

    var lines = std.mem.splitScalar(u8, req, '\n');
    const first = lines.next() orelse return;
    var parts = std.mem.splitScalar(u8, std.mem.trim(u8, first, "\r"), ' ');
    _ = parts.next(); // method
    const path = parts.next() orelse return;

    const body_start = std.mem.indexOf(u8, req, "\r\n\r\n");
    const body = if (body_start) |bs| req[bs + 4 ..] else "";

    const proto = classify(path);
    if (proto == .unknown) {
        writeHttp(stream, 404, "application/json", "{\"error\":\"route-not-found\"}");
        return;
    }

    // ── TRANSACTION GATE — runs before dispatch, every request ──────────
    const is_local = true; // loopback-bound (BIND_IP); see module header
    if (!exposureSatisfied(REQUIRED_EXPOSURE, presentedExposure(req), is_local)) {
        writeHttp(stream, 403, "application/json", "{\"error\":\"forbidden\",\"detail\":\"exposure-gate\"}");
        return;
    }

    const tool = toolFor(proto, path, body) orelse {
        writeHttp(stream, 400, "application/json", "{\"error\":\"missing-tool\"}");
        return;
    };

    var out: [4096]u8 = undefined;
    const d = dispatch(tool, body, &out);

    switch (proto) {
        .sse => writeSse(stream, d),
        .graphql => {
            var gb: [4352]u8 = undefined;
            const g = std.fmt.bufPrint(&gb, "{{\"data\":{{\"invoke\":{s}}}}}", .{d.body}) catch d.body;
            writeHttp(stream, d.status, "application/json", g);
        },
        else => writeHttp(stream, d.status, "application/json", d.body), // rest, grpc
    }
}

pub fn main() !void {
    _ = ffi.boj_cartridge_init();
    defer ffi.boj_cartridge_deinit();
    const addr = std.net.Address.initIp4(BIND_IP, PORT);
    var server = try addr.listen(.{ .reuse_address = true });
    defer server.deinit();
    std.debug.print("__CARTRIDGE_NAME__ INTERNAL unified adapter on 127.0.0.1:{d} (behind http-capability-gateway; rest|sse|graphql|grpc; transaction-gated)\n", .{PORT});
    while (true) {
        const conn = try server.accept();
        const t = try std.Thread.spawn(.{}, handleConnection, .{conn.stream});
        t.detach();
    }
}

// ───────────────────────── tests ─────────────────────────

test "classify routes each protocol to one surface" {
    try std.testing.expectEqual(Protocol.rest, classify("/invoke"));
    try std.testing.expectEqual(Protocol.sse, classify("/sse"));
    try std.testing.expectEqual(Protocol.graphql, classify("/graphql"));
    try std.testing.expectEqual(Protocol.grpc, classify("/grpc/Svc/Method"));
    try std.testing.expectEqual(Protocol.unknown, classify("/nope"));
}

test "toolFor extracts across protocols" {
    try std.testing.expectEqualStrings("__ISER_NAME___generate", toolFor(.rest, "/invoke?tool=__ISER_NAME___generate", "").?);
    try std.testing.expectEqualStrings("__ISER_NAME___generate", toolFor(.sse, "/sse", "{\"tool\":\"__ISER_NAME___generate\"}").?);
    try std.testing.expectEqualStrings("__ISER_NAME___generate", toolFor(.graphql, "/graphql", "{query: invoke(tool:\"__ISER_NAME___generate\")}").?);
    try std.testing.expectEqualStrings("method", toolFor(.grpc, "/grpc/Svc/method", "").?);
    try std.testing.expect(toolFor(.rest, "/invoke", "{}") == null);
}

test "dispatch funnels into the one Zig ABI" {
    var out: [256]u8 = undefined;
    const d = dispatch("__ISER_NAME___generate", "{}", &out);
    try std.testing.expectEqual(@as(u16, 200), d.status);
    try std.testing.expect(std.mem.indexOf(u8, d.body, "result") != null);
    try std.testing.expectEqual(@as(u16, 404), dispatch("nope", "{}", &out).status);
}

// Transaction-gate truth table — must match Idris2
// __MCP_MODULE__.Safe__MODULE_NAME__.exposureSatisfied exactly.
test "exposureSatisfied mirrors the Idris2 contract" {
    // local caller: always permitted regardless of required/presented
    try std.testing.expect(exposureSatisfied(.internal, .public, true));
    // public requirement: any presented level passes
    try std.testing.expect(exposureSatisfied(.public, .public, false));
    // authenticated requirement
    try std.testing.expect(!exposureSatisfied(.authenticated, .public, false));
    try std.testing.expect(exposureSatisfied(.authenticated, .authenticated, false));
    try std.testing.expect(exposureSatisfied(.authenticated, .internal, false));
    // internal requirement
    try std.testing.expect(!exposureSatisfied(.internal, .authenticated, false));
    try std.testing.expect(exposureSatisfied(.internal, .internal, false));
}

test "presentedExposure parses X-Trust-Level (case-insensitive)" {
    const req = "POST /invoke HTTP/1.1\r\nHost: x\r\nX-Trust-Level: Internal\r\n\r\n{}";
    try std.testing.expectEqual(Exposure.internal, presentedExposure(req));
    try std.testing.expectEqual(Exposure.public, presentedExposure("POST / HTTP/1.1\r\n\r\n"));
}
"#,
    );
    GeneratedFile {
        path: PathBuf::from(format!("adapter/{}_adapter.zig", ctx.iser_name)),
        content,
    }
}

// ---------------------------------------------------------------------------
// Unit tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use crate::manifest::Manifest;

    fn test_manifest() -> Manifest {
        let toml = r#"
[project]
name = "chapeliser"
version = "0.1.0"

[language]
name = "Chapel"
paradigm = "imperative"
type-system = "simple"
compilation-target = "native"
key-primitives = ["task", "locale", "domain"]

[output]
repo-name = "chapeliser"
github-org = "hyperpolymath"
description = "Chapel distributed computing -iser"
"#;
        toml::from_str(toml).expect("test manifest")
    }

    #[test]
    fn test_cartridge_scaffold_succeeds() {
        let manifest = test_manifest();
        let tmp = tempfile::tempdir().unwrap();
        let result = scaffold_cartridge(&manifest, tmp.path());
        assert!(
            result.is_success(),
            "scaffold failed: {:?}",
            result.error_message()
        );
        let repo = result.repo().unwrap();
        assert_eq!(repo.name, "chapeliser-mcp");
        assert!(repo.is_complete(), "cartridge missing mandatory files");
    }

    #[test]
    fn test_cartridge_file_count() {
        let manifest = test_manifest();
        let tmp = tempfile::tempdir().unwrap();
        let result = scaffold_cartridge(&manifest, tmp.path());
        let repo = result.repo().unwrap();
        // 13 files: README + cartridge.json + mod.js + panels/manifest.json
        //   + abi/(README + ipkg + SafeXxx.idr)
        //   + ffi/(README + build.zig + xxx_ffi.zig)
        //   + adapter/(README + build.zig + xxx_adapter.zig)
        assert_eq!(repo.file_count(), 13, "expected 13 files");
    }

    #[test]
    fn test_cartridge_files_written_to_disk() {
        let manifest = test_manifest();
        let tmp = tempfile::tempdir().unwrap();
        let result = scaffold_cartridge(&manifest, tmp.path());
        assert!(result.is_success());

        let root = tmp.path().join("chapeliser-mcp");
        assert!(root.join("README.adoc").exists());
        assert!(root.join("cartridge.json").exists());
        assert!(root.join("mod.js").exists());
        assert!(root.join("panels/manifest.json").exists());
        assert!(root.join("abi/README.adoc").exists());
        assert!(root.join("abi/chapeliser-mcp.ipkg").exists());
        assert!(root.join("abi/ChapeliserMcp/SafeChapeliser.idr").exists());
        assert!(root.join("ffi/README.adoc").exists());
        assert!(root.join("ffi/build.zig").exists());
        assert!(root.join("ffi/chapeliser_ffi.zig").exists());
        assert!(root.join("adapter/README.adoc").exists());
        assert!(root.join("adapter/build.zig").exists());
        assert!(root.join("adapter/chapeliser_adapter.zig").exists());
    }

    #[test]
    fn test_cartridge_json_has_correct_name() {
        let manifest = test_manifest();
        let tmp = tempfile::tempdir().unwrap();
        let result = scaffold_cartridge(&manifest, tmp.path());
        let cj_path = tmp.path().join("chapeliser-mcp/cartridge.json");
        let content = std::fs::read_to_string(&cj_path).unwrap();
        assert!(content.contains("\"name\": \"chapeliser-mcp\""));
        assert!(content.contains("\"chapeliser_generate\""));
        assert!(content.contains("boj_cartridge_invoke"));
        let _ = result;
    }

    #[test]
    fn test_safe_idr_has_exposure_gate() {
        let manifest = test_manifest();
        let tmp = tempfile::tempdir().unwrap();
        let _ = scaffold_cartridge(&manifest, tmp.path());
        let idr_path = tmp
            .path()
            .join("chapeliser-mcp/abi/ChapeliserMcp/SafeChapeliser.idr");
        let content = std::fs::read_to_string(&idr_path).unwrap();
        assert!(content.contains("exposureSatisfied"));
        assert!(content.contains("data Exposure = Public | Authenticated | Internal"));
        assert!(content.contains("chapeliser_exposure_satisfied"));
    }

    #[test]
    fn test_adapter_zig_has_all_four_protocols() {
        let manifest = test_manifest();
        let tmp = tempfile::tempdir().unwrap();
        let _ = scaffold_cartridge(&manifest, tmp.path());
        let adapter_path = tmp
            .path()
            .join("chapeliser-mcp/adapter/chapeliser_adapter.zig");
        let content = std::fs::read_to_string(&adapter_path).unwrap();
        assert!(content.contains("Protocol.rest"));
        assert!(content.contains("Protocol.sse"));
        assert!(content.contains("Protocol.graphql"));
        assert!(content.contains("Protocol.grpc"));
        assert!(content.contains("classify"));
        assert!(content.contains("toolFor"));
        assert!(content.contains("dispatch("));
    }

    #[test]
    fn test_ffi_zig_exports_five_symbols() {
        let manifest = test_manifest();
        let tmp = tempfile::tempdir().unwrap();
        let _ = scaffold_cartridge(&manifest, tmp.path());
        let ffi_path = tmp.path().join("chapeliser-mcp/ffi/chapeliser_ffi.zig");
        let content = std::fs::read_to_string(&ffi_path).unwrap();
        assert!(content.contains("pub export fn boj_cartridge_init"));
        assert!(content.contains("pub export fn boj_cartridge_deinit"));
        assert!(content.contains("pub export fn boj_cartridge_name"));
        assert!(content.contains("pub export fn boj_cartridge_version"));
        assert!(content.contains("pub export fn boj_cartridge_invoke"));
    }

    #[test]
    fn test_idris2_module_name_derivation() {
        assert_eq!(idris2_module_name("chapeliser"), "Chapeliser");
        assert_eq!(idris2_module_name("bqniser"), "Bqniser");
        assert_eq!(idris2_module_name("k9iser"), "K9iser");
    }
}
