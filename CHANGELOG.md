# Changelog

All notable changes to iseriser will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added (2026-05-20)
- `cartridge` subcommand — scaffolds a complete boj-server cartridge skeleton (`<iser>-mcp/`) from an `iseriser.toml` manifest. Emits 13 files across `cartridge.json`, `mod.js`, `panels/`, `abi/` (Idris2), `ffi/` (Zig, ADR-0006 5-symbol C ABI), and `adapter/` (unified gated adapter, REST + SSE + GraphQL + gRPC-compat behind the transaction gate). Modelled on the k9iser-mcp pilot (boj-server#73). Implements [standards#89 Phase 2b](https://github.com/hyperpolymath/standards/issues/89). End-to-end verified: `idris2 --build`, `zig build test` on `ffi/` (4/4) and `adapter/` (5/5). (PR #24)

### Changed (2026-05-20)
- Scaffolder no longer emits `adapter/<name>_adapter.zig` into new -iser repos. The unified transaction-gated adapter belongs to the boj-server cartridge for the -iser (`boj-server/cartridges/<name>-mcp/adapter/`), not to the -iser repo itself. Use the new `cartridge` subcommand to scaffold the cartridge. (PR #23, reverts the wrong-place emission added in #12.)
- Cartridge scaffolder emits `depends = base, contrib` on the generated `.ipkg` to match the pilot convention. (PR #25, corrects an omission in #24.)

### Added (2026-04-04)
- Criterion benchmark suite (`benches/iseriser_bench.rs`) — 8 benchmarks covering codegen performance and manifest parsing efficiency

## [0.1.0] - 2026-03-20

### Added
- Initial project scaffold from rsr-template-repo
- CLI with subcommands (init, validate, generate, build, run, info)
- Manifest parser (`iseriser.toml`)
- Codegen engine (stubs — target-language-specific implementation pending)
- ABI module (Idris2 proof type definitions)
- Library API for programmatic use
- Full RSR template (17 CI workflows, governance docs, bot directives)
- README.adoc with architecture overview and value proposition
