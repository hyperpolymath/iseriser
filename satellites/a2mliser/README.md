<!--
SPDX-License-Identifier: CC-BY-SA-4.0
SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->

[![Funding](https://img.shields.io/badge/Funding-See_FUNDING-brightgreen)](FUNDING)

# What Is a2mliser?

a2mliser wraps any markup, configuration, or manifest file in an **A2ML
(Attestable Markup Language) envelope** — adding cryptographic
signatures, provenance chains, and tamper detection without altering the
original content.

Where most signing tools operate on opaque blobs, a2mliser understands
structure. It parses TOML, YAML, JSON, XML, and INI files, then
generates attestation wrappers that cover both the content and its
schema. A consumer can verify not only that a file has not been tampered
with, but that its structure conforms to the attested schema at the
moment of signing.

a2mliser is part of the [-iser acceleration
family](https://github.com/hyperpolymath/iseriser) — tools that wrap
existing code in a target language’s capabilities via manifest-driven
code generation.

# Key Value Proposition

- **Any file can be attested** — configs, manifests, CI definitions,
  lock files, even other A2ML documents.

- **Cryptographic proof** of authenticity and integrity (SHA-256,
  BLAKE3).

- **Provenance chains** — trace any artifact back through its chain of
  custody. A attests B attests C, forming a directed acyclic graph of
  trust.

- **Structure-aware signing** — unlike GPG detached signatures, a2mliser
  understands the file format and signs individual fields or sections.

- **Supply chain security** — verify that CI configs, dependency
  manifests, and deployment descriptors have not been altered since the
  authorised signer produced them.

- **Format-preserving** — the original file remains readable;
  attestation metadata is carried in a sidecar `.a2ml` envelope or
  embedded as comments.

# Architecture

a2mliser follows the hyperpolymath ABI-FFI-codegen architecture:

                              a2mliser.toml (user manifest)
                                    |
                                    v
                        +------------------------+
                        |  Manifest Parser (Rust) |  <-- reads user intent
                        +------------------------+
                                    |
                      +-------------+-------------+
                      |                           |
                      v                           v
        +---------------------+     +-----------------------+
        | Idris2 ABI Proofs   |     | Format Handlers       |
        | (signature correct- |     | (TOML, YAML, JSON,    |
        |  ness, non-repudia- |     |  XML, INI parsers)    |
        |  tion, chain valid- |     +-----------------------+
        |  ity)               |                |
        +---------------------+                v
                  |               +-----------------------+
                  v               | Attestation Engine    |
        +---------------------+   | (hash, sign, embed)   |
        | Zig FFI Bridge      |   +-----------------------+
        | (crypto primitives: |                |
        |  BLAKE3, Ed25519,   |                v
        |  SHA-256)           |   +-----------------------+
        +---------------------+   | Codegen (A2ML wrapper |
                  |               |  generation)          |
                  v               +-----------------------+
        +---------------------+                |
        | C Headers (generated|                v
        |  from ABI)          |     attested output files
        +---------------------+     (.a2ml envelopes)

## Layer Responsibilities

Manifest Parser (Rust)  
Reads `a2mliser.toml`, validates user intent, dispatches to format
handlers and the attestation engine.

Idris2 ABI (`src/interface/abi/`)  
Formally proves that signature operations are correct: signing a
document and verifying the same document always agree; provenance chains
form a valid DAG; attestation envelopes are non-repudiable.

Zig FFI (`src/interface/ffi/`)  
Implements the actual cryptographic primitives (BLAKE3 hashing, Ed25519
signing, SHA-256 digests) as a C-compatible shared library. Zero runtime
overhead from the proof layer — Idris2 proofs are erased at compile
time.

Format Handlers (`src/codegen/`)  
Parse each supported format while preserving structure, identify
attestable regions, and generate the A2ML envelope that wraps the
original content.

# Supported Formats

| Format | Notes |
|----|----|
| TOML | Full structural attestation. Individual tables and key-value pairs can be signed independently. |
| YAML | Document and sub-document attestation. Anchors and aliases are resolved before signing. |
| JSON | Object-level and array-level attestation. JSON Schema can be co-attested. |
| XML | Element-level signing with XPath selectors. Namespace-aware. |
| INI | Section-level attestation. Comments are preserved but excluded from signatures by default. |
| Custom | Plugin system (Phase 3+) for arbitrary formats via a trait-based handler interface. |

# CLI Commands

```bash
# Create a new a2mliser.toml in the current directory
a2mliser init

# Validate an existing manifest
a2mliser validate --manifest a2mliser.toml

# Generate A2ML attestation envelopes for all declared files
a2mliser generate --manifest a2mliser.toml --output attested/

# Build the generated artifacts (compile Zig FFI, link)
a2mliser build --manifest a2mliser.toml [--release]

# Run the attestation workload end-to-end
a2mliser run --manifest a2mliser.toml

# Show manifest information and attestation summary
a2mliser info --manifest a2mliser.toml
```

# Example Manifest

An `a2mliser.toml` that attests a Cargo.toml and a CI workflow:

```toml
# a2mliser manifest — declare which files to attest
[workload]
name = "my-project-attestation"
entry = "Cargo.toml"
strategy = "structure-aware"

[data]
input-type = "toml"
output-type = "a2ml-envelope"

[options]
flags = ["sign-sections", "provenance-chain"]

# Files to attest
[[targets]]
path = "Cargo.toml"
format = "toml"
granularity = "table"          # sign each [section] independently

[[targets]]
path = ".github/workflows/ci.yml"
format = "yaml"
granularity = "document"       # sign the entire document

[signing]
algorithm = "ed25519"
hash = "blake3"
key-source = "env:A2ML_SIGNING_KEY"  # or "file:keys/signing.pem"
```

# Integration With Other -isers

k9iser  
Contract validation. k9iser validates that configuration files satisfy
K9 contracts; a2mliser then attests the validated result, proving that
the file both conforms to its contract and has not been modified since
validation.

typedqliser  
Query attestation. When typedqliser generates type-safe query wrappers,
a2mliser can attest the generated code, proving it was produced by a
specific version of typedqliser from a specific schema.

verisimiser  
Database augmentation. Attestation records (who signed what, when) can
be stored in VeriSimDB octads via verisimiser, providing a
tamper-evident audit trail.

# Build and Test

```bash
# Build
cargo build --release

# Test
cargo test

# Full quality check (format, lint, test)
just quality

# Pre-commit scan
just assail
```

# Status

**Pre-alpha (Phase 0 complete).**

The CLI skeleton, manifest parser, and ABI/FFI scaffolding are in place.
Codegen stubs exist but do not yet produce real attestation envelopes.

See <a href="ROADMAP.adoc" class="adoc">ROADMAP</a> for the full
development plan.

See <a href="TOPOLOGY.md" class="md">TOPOLOGY</a> for the repository
structure map.

# License

SPDX-License-Identifier: CC-BY-SA-4.0

Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
