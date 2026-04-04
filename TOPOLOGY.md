<!-- SPDX-License-Identifier: PMPL-1.0-or-later -->
<!-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk> -->
# TOPOLOGY.md — iseriser

## Purpose

iseriser is the meta-iser: it generates complete new -iser project scaffolds from a language description manifest. Given a target language or system name and its characteristics, iseriser emits a fully-structured RSR-compliant repository with the standard Rust CLI skeleton, Idris2 ABI stubs, Zig FFI bridge, manifest parser, codegen module, justfile, and all required workflow files. iseriser is the bootstrap tool for the entire -iser family and is used to create new isers consistently and quickly.

## Module Map

```
iseriser/
├── src/
│   ├── main.rs                    # CLI entry point (clap): init, validate, generate, info
│   ├── lib.rs                     # Library API
│   ├── manifest/mod.rs            # iseriser.toml parser (target language description)
│   ├── codegen/mod.rs             # Full -iser scaffold generation
│   └── abi/                       # Idris2 ABI bridge stubs
├── examples/                      # Worked examples
├── verification/                  # Proof harnesses
├── container/                     # Stapeln container ecosystem
└── .machine_readable/             # A2ML metadata
```

## Data Flow

```
iseriser.toml manifest
        │
   ┌────▼────┐
   │ Manifest │  parse + validate target language description (name, domain, backend)
   │  Parser  │
   └────┬────┘
        │  validated language spec
   ┌────▼────┐
   │ Analyser │  determine required modules, ABI/FFI shape, CLI subcommands
   └────┬────┘
        │  intermediate scaffold plan
   ┌────▼────┐
   │ Codegen  │  emit complete <language>iser/ project tree
   │          │  (src/, ffi/zig/, src/abi/, justfile, workflows, .machine_readable/)
   └─────────┘
```
