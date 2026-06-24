<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->
<!-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk> -->
# Iseriser — Architectural Topology

## Overview

Iseriser is the meta-framework that generates new -iser projects. It takes a
language description as input and produces a complete -iser repository as output.

## Data Flow

```
                      iseriser.toml
                    (language description)
                           |
                           v
                   +---------------+
                   | Manifest      |
                   | Parser        |
                   | (Rust/serde)  |
                   +---------------+
                           |
                           v
                   +---------------+
                   | Language       |
                   | Model          |
                   | (internal IR)  |
                   +---------------+
                      /    |    \
                     /     |     \
                    v      v      v
          +--------+ +--------+ +--------+
          | Idris2 | |Template| | RSR    |
          | ABI    | | Engine | | Gov.   |
          | Proofs | |(Hbars) | | Gen.   |
          +--------+ +--------+ +--------+
                \      |      /
                 \     |     /
                  v    v    v
            +------------------+
            | Generated -iser  |
            | Repository       |
            | (complete, ready |
            |  to cargo build) |
            +------------------+
```

## Module Structure

```
iseriser/
├── src/
│   ├── main.rs                     # CLI: init, validate, generate, build, run, info
│   ├── lib.rs                      # Library API: manifest, codegen, abi modules
│   ├── manifest/
│   │   └── mod.rs                  # TOML manifest parser (language descriptions)
│   ├── codegen/
│   │   └── mod.rs                  # Template expansion engine
│   ├── abi/
│   │   └── mod.rs                  # Rust-side ABI types (mirrors Idris2)
│   ├── core/                       # Language model and feature detection
│   ├── definitions/                # Language feature definitions
│   ├── contracts/                  # Contract validation for generated output
│   ├── bridges/                    # Bridge generation (Zig FFI templates)
│   ├── errors/                     # Error types and diagnostics
│   ├── aspects/                    # Cross-cutting concerns (logging, tracing)
│   └── interface/
│       ├── abi/
│       │   ├── Types.idr           # ABI type defs: LanguageModel, TypeSystemFeature, etc.
│       │   ├── Layout.idr          # Memory layout proofs for generated structs
│       │   └── Foreign.idr         # FFI declarations for template expansion
│       ├── ffi/
│       │   ├── build.zig           # Zig build config for shared/static lib
│       │   ├── src/main.zig        # Zig FFI implementation
│       │   └── test/               # Integration tests
│       └── generated/
│           └── abi/                # Auto-generated C headers
├── .machine_readable/              # RSR governance (STATE, META, ECOSYSTEM, etc.)
├── docs/
│   └── architecture/
│       └── TOPOLOGY.md             # This file
└── tests/                          # Rust integration tests
```

## Key Dependencies

| Dependency | Purpose |
|------------|---------|
| `clap` | CLI argument parsing with derive macros |
| `serde` + `toml` | Manifest deserialization |
| `handlebars` | Template engine for code generation |
| `anyhow` + `thiserror` | Error handling |
| `walkdir` | Directory traversal for template discovery |

## Integration Points

| System | Relationship |
|--------|-------------|
| **proven** | Shared Idris2 verified library for ABI proofs |
| **typell** | Type theory engine used in language model analysis |
| **rsr-template-repo** | Source templates for generated RSR governance files |
| **PanLL** | Future: "New -Iser" wizard panel |
| **BoJ-server** | Future: `iseriser.generate` MCP cartridge |
| **VeriSimDB** | Future: persist language models and generation history |
| **Hypatia** | Neurosymbolic scanning of generated repos |

## Generation Pipeline

1. **Parse** — `iseriser.toml` -> `LanguageDescription` struct
2. **Model** — `LanguageDescription` -> `LanguageModel` (features, targets, ABI shape)
3. **Verify** — Idris2 ABI checks language model consistency
4. **Expand** — Handlebars templates + language model -> file tree
5. **Write** — file tree -> disk (complete -iser repo)
6. **Validate** — generated repo passes `cargo check` and template completeness
