<!--
SPDX-License-Identifier: CC-BY-SA-4.0
SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->

[![License: MPL-2.0](https://img.shields.io/badge/license-PMPL--1.0--or--later-blue)](LICENSE) ![Palimpsest
Covenant](https://img.shields.io/badge/Palimpsest-Covenant-purple) ![29
repos](https://img.shields.io/badge/-iser_family-29_repos-brightgreen)
![Idris2 ABI](https://img.shields.io/badge/ABI-Idris2-red) ![Zig
FFI](https://img.shields.io/badge/FFI-Zig-orange)

<div class="lead" wrapper="1">

**29 Rust CLI tools that inject superpowers from specialist languages
into your existing codebase — without you ever learning those
languages.**

</div>

https://hyperpolymath.github.io/iseriser/\[Browse the Hub\] \|
<a href="#the-iser-family" class="cross-reference">See All 29 -isers</a>
\| <a href="#install" class="cross-reference">Install</a>

------------------------------------------------------------------------

> [!TIP]
> **New here? Start with the coordination layer:**
>
> - [**The -iser Atlas**](docs/ATLAS.adoc) — route a need straight to
>   the right -iser ("I want to… → use…").
>
> - [**Aspect-Oriented Language Design**](docs/theory/AOLD.adoc) — the
>   design philosophy (each language’s superpower as a bolt-on *aspect*;
>   the "mech suit" model; why this is the *dual* of aggregate-library).
>
> - [**Integrated Stack of Stacks**](docs/theory/iSOS.adoc) — how
>   aspects *compose* over one shared Idris2-ABI/Zig-FFI seam, kept
>   honest by invariant-path.

# What is the -iser Pattern?

An **-iser** is a Rust CLI that bridges the gap between a *specialist
language* (a language with unique strengths in a narrow domain) and the
code you already write every day. Each -iser:

1.  **Reads** a declarative TOML manifest describing what you want.

2.  **Validates** it against a formally verified Idris2 ABI
    specification.

3.  **Generates** wrapper code, bindings, or transformations targeting
    the specialist language — via a Zig FFI bridge for C-ABI
    compatibility.

4.  **Builds and runs** the result, giving you the specialist language’s
    capabilities without leaving your toolchain.

The pattern lets you tap into GPU kernels (Futhark), formal proofs
(Idris2, Dafny, TLA+), data-race freedom (Pony), fault tolerance (OTP),
distributed computing (Chapel), and 20+ other domains — all through a
consistent `init` `/` `validate` `/` `generate` `/` `build` `/` `run`
workflow.

**Iseriser is the meta-framework that generates new -iser projects.**
Given a language description, it scaffolds a complete -iser repo in
minutes: manifest parser, codegen engine, Idris2 ABI definitions, Zig
FFI bridge, 17 CI/CD workflows, RSR governance files, and documentation.

# Architecture: Idris2 ABI + Zig FFI

Every -iser in the family shares a three-layer architecture that
guarantees interface correctness through formal verification:

                         +---------------------------+
                         |     Rust CLI (cargo)       |
                         |  init/validate/gen/build   |
                         +------+----------+---------+
                                |          |
                   +------------+          +------------+
                   |                                    |
                   v                                    v
      +------------------------+         +------------------------+
      |     Idris2 ABI Layer   |         |   Zig FFI Layer        |
      |  (formal verification) |         |  (C-ABI bridge)        |
      |                        |         |                        |
      |  Types.idr             |-------->|  build.zig             |
      |    dependent types     |  gen'd  |  src/main.zig          |
      |    prove correctness   |   C     |  test/integration.zig  |
      |  Layout.idr            | headers |                        |
      |    memory layout       |         |  zero-cost C interop   |
      |    platform proofs     |         |  cross-compilation     |
      |  Foreign.idr           |         |  no runtime deps       |
      |    FFI declarations    |         |                        |
      +------------------------+         +------------------------+
                   |                                    |
                   +----------------+-------------------+
                                    |
                                    v
                       +------------------------+
                       |   Target Language       |
                       |   (Chapel, Futhark,     |
                       |    Idris2, Pony, ...)   |
                       +------------------------+

**Why Idris2 for ABI?**  
Dependent types prove interface correctness at compile time. Memory
layouts are verified. Platform-specific ABIs are selected with
compile-time proofs. Backward compatibility is provable. These are
type-level guarantees that no other approach can provide.

**Why Zig for FFI?**  
Native C ABI compatibility with zero overhead. Memory-safe by default.
Cross-compilation is built in. No runtime dependencies. The ideal bridge
between formal specifications and real-world calling conventions.

# <span id="the-iser-family"></span>The -iser Family (29 repos)

| Name | Description | Tests | Status |
|----|----|----|----|
| https://github.com/hyperpolymath/typedqliser\[**TypedQLiser**\] | Add formal type safety (10 levels, dependent/linear/session types) to any query language | 0 | scaffold |
| https://github.com/hyperpolymath/chapeliser\[**Chapeliser**\] | General-purpose Chapel acceleration — distribute any workload without learning Chapel | 22 | scaffold |
| https://github.com/hyperpolymath/verisimiser\[**Verisimiser**\] | Augment any database with VeriSimDB octad capabilities — drift, provenance, temporal | 26 | scaffold |
| https://github.com/hyperpolymath/julianiser\[**Julianiser**\] | Auto-wrap Python/R data pipelines into Julia for 100x speedups | 25 | scaffold |
| https://github.com/hyperpolymath/futharkiser\[**Futharkiser**\] | Compile annotated array operations to GPU kernels via Futhark | 42 | scaffold |
| https://github.com/hyperpolymath/idrisiser\[**Idrisiser**\] | Generate proven-correct wrappers from interfaces using Idris2 dependent types | 6 | scaffold |
| https://github.com/hyperpolymath/tlaiser\[**TLAiser**\] | Extract state machines from code and model-check with TLA+/PlusCal | 32 | scaffold |
| https://github.com/hyperpolymath/dafniser\[**Dafniser**\] | Generate correct-by-construction code for critical functions using Dafny | 28 | scaffold |
| https://github.com/hyperpolymath/ponyiser\[**Ponyiser**\] | Wrap concurrent code in Pony reference capabilities for data-race freedom | 27 | scaffold |
| https://github.com/hyperpolymath/otpiser\[**OTPiser**\] | Generate OTP supervision trees and fault-tolerance scaffolding | 1 | scaffold |
| https://github.com/hyperpolymath/halideiser\[**Halideiser**\] | Compile image/video pipelines to optimised Halide schedules | 24 | scaffold |
| https://github.com/hyperpolymath/lustreiser\[**Lustreiser**\] | Generate formally verified real-time embedded code via Lustre | 36 | scaffold |
| https://github.com/hyperpolymath/bqniser\[**BQNiser**\] | Detect array patterns and rewrite as optimised BQN primitives | 0 | scaffold |
| https://github.com/hyperpolymath/alloyiser\[**Alloyiser**\] | Extract formal models from API specs and verify with Alloy | 25 | scaffold |
| https://github.com/hyperpolymath/atsiser\[**ATSiser**\] | Wrap C codebases in ATS linear types for zero-cost memory safety | 32 | scaffold |
| https://github.com/hyperpolymath/nimiser\[**Nimiser**\] | Generate high-performance C libraries via Nim metaprogramming | 28 | scaffold |
| https://github.com/hyperpolymath/a2mliser\[**A2MLiser**\] | Add cryptographic attestation to any markup or configuration via A2ML | 0 | scaffold |
| https://github.com/hyperpolymath/affinescriptiser\[**AffineScriptiser**\] | Wrap code in affine + dependent types targeting WASM via AffineScript | 36 | scaffold |
| https://github.com/hyperpolymath/anvomidaviser\[**Anvomidaviser**\] | Convert ISU notation to formal figure skating programs via Anvomidav | 36 | scaffold |
| https://github.com/hyperpolymath/betlangiser\[**BetLangiser**\] | Add ternary probabilistic modelling to deterministic code via Betlang | 36 | scaffold |
| https://github.com/hyperpolymath/eclexiaiser\[**Eclexiaiser**\] | Add energy/carbon/resource-cost awareness to software via Eclexia | 23 | scaffold |
| https://github.com/hyperpolymath/ephapaxiser\[**Ephapaxiser**\] | Enforce single-use linear type semantics on resources via Ephapax | 17 | scaffold |
| https://github.com/hyperpolymath/k9iser\[**K9iser**\] | Wrap configs into self-validating K9 contracts | 19 | scaffold |
| https://github.com/hyperpolymath/mylangiser\[**MyLangiser**\] | Generate progressive-disclosure interfaces from complex APIs via My-Lang | 20 | scaffold |
| https://github.com/hyperpolymath/oblibeniser\[**Oblibeniser**\] | Make operations reversible and auditable via Oblibeny | 27 | scaffold |
| https://github.com/hyperpolymath/phronesiser\[**Phronesiser**\] | Add provably safe ethical constraints to AI agents via Phronesis | 31 | scaffold |
| https://github.com/hyperpolymath/wokelangiser\[**WokeLangiser**\] | Add consent patterns and accessibility to existing code via WokeLang | 44 | scaffold |
| https://github.com/hyperpolymath/squeakwell\[**SqueakWell**\] | Database recovery through cross-modal constraint propagation — 8 modalities | 0 | scaffold |
| https://github.com/hyperpolymath/iseriser\[**Iseriser**\] | **This repo** — the meta-framework that generates all other -isers | 24 | scaffold |

Total tests across the family: **726**

# <span id="install"></span>Installation

Every -iser is a standalone Rust binary. Install any of them with:

```bash
# Install a specific -iser
cargo install typedqliser
cargo install futharkiser
cargo install chapeliser
# ... or any other -iser name

# Install iseriser (the meta-framework)
cargo install iseriser
```

Or clone and build from source:

```bash
git clone https://github.com/hyperpolymath/<name>.git
cd <name>
cargo build --release
```

# Usage

All -isers share the same five-command interface:

```bash
# Initialise a new manifest for your project
<iser> init

# Validate your manifest against the Idris2 ABI spec
<iser> validate

# Generate target language code from your manifest
<iser> generate

# Build the generated output
<iser> build

# Run the result
<iser> run
```

# Using Iseriser to Create a New -iser

```bash
# 1. Create a language description
cat > mylanguage.toml <<'TOML'
[language]
name = "MyLang"
type_system = ["dependent", "linear"]
target = "native"
calling_convention = "c"
TOML

# 2. Generate the -iser repo
iseriser generate --from mylanguage.toml --output ./mylangiser

# 3. The result is a complete, functional -iser repo
cd mylangiser
cargo test   # tests pass immediately
cargo run -- init
```

## Iseriser CLI subcommands

In addition to scaffolding new -isers, iseriser itself ships with:

| `init` | Initialise an `iseriser.toml` manifest in the current directory. |
|----|----|
| `validate` | Structural + semantic validation of an `iseriser.toml`. |
| `generate` | Scaffold a complete -iser repo from the manifest. |
| `cartridge` | Scaffold a boj-server cartridge skeleton (`<iser>-mcp/`) for the manifest’s -iser — adapter + FFI + ABI + cartridge.json + panels + mod.js. Output goes to `<output>/<iser>-mcp/`; place inside `boj-server/cartridges/` so the emitted Zig build files resolve the shared invoke-shim. See `examples/cartridge-skeleton/README.adoc`. |
| `info` | Print a summary of a manifest. |
| `scan` | Walk a repository and recommend applicable -iser tools. |
| `abi-verify` | (Phase 1) Diff a cartridge’s Zig FFI against its Idris2-derived ABI manifest; exit 0=clean, 2=drift. See `examples/abi-manifests/README.adoc` for the drift taxonomy. |
| `abi-emit-manifest` | (Phase 1b) Emit the ABI manifest JSON from a cartridge’s `Safe*.idr` source. The Idris2 source is the single authority — manifest is derived, not hand-authored. Combine with `abi-verify` to gate Zig FFI drift in CI. |

The `abi-*` pair implements
<a href="https://github.com/hyperpolymath/standards/issues/92"
id="92">standards</a> (Phase 1 + 1b); see
`examples/abi-manifests/README.adoc` for the schema, the drift taxonomy,
and end-to-end usage.

The `cartridge` subcommand implements
<a href="https://github.com/hyperpolymath/standards/issues/89"
id="89">standards</a> Phase 2b — the boj-server cartridge skeleton,
modelled on the k9iser-mcp pilot (boj-server#73). Estate-wide fan-out of
the regeneration-cartridge pattern is gated on
<a href="https://github.com/hyperpolymath/standards/issues/91"
id="91">standards</a> (http-capability-gateway tier-2
production-wiring).

# Generated Repo Structure

When iseriser generates a new -iser, it produces:

    <name>/
    +-- Cargo.toml                        # Rust CLI project
    +-- src/
    |   +-- main.rs                       # CLI: init/validate/generate/build/run
    |   +-- lib.rs                        # Library API
    |   +-- manifest/mod.rs               # TOML manifest parser
    |   +-- codegen/mod.rs                # Target-specific code generation
    |   +-- abi/mod.rs                    # Rust-side ABI types
    |   +-- interface/
    |       +-- abi/
    |       |   +-- Types.idr             # Idris2 type definitions + proofs
    |       |   +-- Layout.idr            # Memory layout verification
    |       |   +-- Foreign.idr           # FFI function declarations
    |       +-- ffi/
    |           +-- build.zig             # Zig build config
    |           +-- src/main.zig          # Zig FFI implementation
    |           +-- test/integration.zig  # FFI integration tests
    +-- .github/workflows/                # 17 CI/CD workflows
    +-- .machine_readable/                # RSR governance (STATE, META, ECOSYSTEM)
    +-- README.adoc
    +-- ROADMAP.adoc
    +-- TOPOLOGY.md
    +-- LICENSE

# The Hub

Browse the full -iser family with interactive search and filtering:

**https://hyperpolymath.github.io/iseriser/**

The GitHub Pages hub provides:

- Searchable catalogue of all 29 -isers

- Architecture diagrams and domain explanations

- Quick-start guides for each -iser

- Links to crates.io, documentation, and source

# Status

All 29 -iser repos are scaffolded and functional. The architecture is
defined, CLI commands work, manifest parsers are operational, and test
suites are in place across the family. Domain-specific code generation
logic is the current frontier — each -iser is being deepened with real
codegen for its target language.

# Contributing

See <a href="CONTRIBUTING.adoc" class="adoc">CONTRIBUTING</a> for
guidelines. All contributions must pass the full CI suite including
Hypatia neurosymbolic scanning.

# License

SPDX-License-Identifier: `MPL-2.0`

Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)

Licensed under the [Palimpsest
License](https://github.com/hyperpolymath/palimpsest-license).
