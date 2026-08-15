<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->
<!-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) -->
# a2mliser — Repository Topology

Map of every directory and its purpose.

```
a2mliser/
├── 0-AI-MANIFEST.a2ml              # AI agent entry point — read first
├── README.adoc                     # High-level orientation
├── ROADMAP.adoc                    # Development phases
├── TOPOLOGY.md                     # THIS FILE — repo structure map
├── CONTRIBUTING.adoc               # Contribution guidelines
├── SECURITY.md                     # Vulnerability reporting policy
├── CHANGELOG.md                    # Release history
├── LICENSE                         # MPL-2.0 full text
├── Cargo.toml                      # Rust package manifest
├── Justfile                        # Task runner (just)
├── Containerfile                   # OCI container build (Chainguard base)
├── contractile.just                # Contractile system recipes
├── flake.nix                       # Nix flake for reproducible builds
├── guix.scm                        # Guix package definition
├── .editorconfig                   # Editor formatting rules
├── .envrc                          # direnv environment
├── .gitattributes                  # Git LFS and diff config
├── .gitignore                      # Ignored paths
├── .gitlab-ci.yml                  # GitLab CI mirror pipeline
├── .guix-channel                   # Guix channel metadata
├── .tool-versions                  # asdf tool versions
│
├── src/                            # SOURCE CODE
│   ├── main.rs                     # CLI entry point (clap subcommands)
│   ├── lib.rs                      # Library root — re-exports manifest, codegen, abi
│   ├── abi/
│   │   └── mod.rs                  # Rust-side ABI module (Idris2 proof types)
│   ├── manifest/
│   │   └── mod.rs                  # Manifest parser — loads a2mliser.toml
│   ├── codegen/
│   │   └── mod.rs                  # Code generation — produces A2ML envelopes (stub)
│   ├── core/                       # Core attestation logic (planned)
│   ├── bridges/                    # Cross-iser integration bridges (planned)
│   ├── contracts/                  # Runtime contract checking (planned)
│   ├── definitions/                # Type and constant definitions (planned)
│   ├── errors/                     # Error types and diagnostics (planned)
│   ├── aspects/                    # Cross-cutting concerns
│   │   ├── integrity/              # Data integrity checks
│   │   ├── observability/          # Logging, metrics, tracing
│   │   └── security/               # Security-related aspects
│   └── interface/                  # VERIFIED INTERFACE SEAMS
│       ├── abi/                    # Idris2 ABI definitions
│       │   ├── Types.idr           # Core types (signatures, results, handles)
│       │   ├── Layout.idr          # Memory layout proofs for FFI structs
│       │   └── Foreign.idr         # FFI function declarations with proofs
│       ├── ffi/                    # Zig FFI implementation
│       │   ├── build.zig           # Zig build system config
│       │   ├── src/
│       │   │   └── main.zig        # C-compatible FFI (crypto primitives)
│       │   └── test/
│       │       └── integration_test.zig  # FFI integration tests
│       └── generated/              # Auto-generated C headers (from ABI)
│           └── abi/
│               └── .gitkeep
│
├── container/                      # Stapeln container ecosystem configs
├── docs/                           # DOCUMENTATION
│   ├── QUICKSTART.adoc             # Getting started guide
│   ├── RSR_OUTLINE.adoc            # RSR compliance outline
│   ├── STATE-VISUALIZER.adoc       # State visualisation guide
│   ├── architecture/               # Architecture diagrams and ADRs
│   ├── attribution/                # Citations, maintainers
│   ├── decisions/                  # Architectural decision records
│   ├── developer/                  # Developer guides
│   ├── governance/                 # Project governance
│   ├── legal/                      # Legal exhibits, license texts
│   ├── practice/                   # Operational manuals
│   ├── reports/                    # Generated reports
│   ├── standards/                  # Standards compliance
│   ├── templates/                  # Document templates
│   ├── theory/                     # Domain theory (A2ML specification)
│   ├── whitepapers/                # Research and whitepapers
│   └── wikis/                      # Wiki-style documentation
│
├── examples/                       # USAGE EXAMPLES
│   ├── SafeDOMExample.affine          # AffineScript example
│   └── web-project-deno.json       # Deno project example
│
├── features/                       # BDD FEATURE SPECS (Gherkin)
│
├── tests/                          # Rust integration tests
│
├── verification/                   # FORMAL VERIFICATION ARTIFACTS
│
├── .claude/
│   └── CLAUDE.md                   # Claude Code project instructions
│
├── .devcontainer/                  # Dev container config
│
├── .github/                        # GITHUB CONFIGURATION
│   ├── workflows/                  # 17 CI/CD workflows (RSR standard)
│   └── ...                         # CODEOWNERS, MAINTAINERS, etc.
│
├── .hypatia/                       # Hypatia neurosymbolic scanner rules
│
├── .machine_readable/              # ALL MACHINE-READABLE METADATA
│   ├── 6a2/                        # Core state files
│   │   ├── STATE.a2ml              # Project state and progress
│   │   ├── META.a2ml               # Architecture decisions, governance
│   │   ├── ECOSYSTEM.a2ml          # Ecosystem position, relationships
│   │   ├── AGENTIC.a2ml            # AI agent interaction patterns
│   │   ├── NEUROSYM.a2ml           # Neurosymbolic config
│   │   └── PLAYBOOK.a2ml           # Operational runbook
│   ├── ai/                         # AI agent configs (.clinerules, .cursorrules, etc.)
│   ├── anchors/                    # Semantic boundary declarations
│   ├── bot_directives/             # Gitbot-fleet instructions (rhodibot, echidnabot, etc.)
│   ├── configs/                    # Tool configs (git-cliff, etc.)
│   ├── compliance/                 # REUSE dep5, cargo-deny
│   ├── contractiles/               # Policy enforcement
│   │   ├── k9/                     # K9 validator contracts (Nickel)
│   │   ├── must/                   # Hard requirements
│   │   ├── trust/                  # Trust assertions
│   │   ├── dust/                   # Deprecation tracking
│   │   └── lust/                   # Intent declarations
│   ├── integrations/               # Integration configs (proven, verisimdb, etc.)
│   ├── policies/                   # Maintenance policies and checklists
│   └── scripts/                    # Automation scripts
│       ├── forge/                  # Forge sync, git cleanup
│       ├── lifecycle/              # Tool installation
│       ├── maintenance/            # Maintenance assault scripts
│       └── verification/           # Verification scripts
│
└── .well-known/                    # .well-known metadata (security.txt, etc.)
```

## Key Relationships

- `src/interface/abi/*.idr` **defines** the formal specification (Idris2)
- `src/interface/ffi/src/main.zig` **implements** the specification (Zig)
- `src/interface/generated/abi/` **bridges** them via C headers
- `src/manifest/mod.rs` **reads** user intent from `a2mliser.toml`
- `src/codegen/mod.rs` **produces** A2ML attestation envelopes
- `src/main.rs` **orchestrates** the pipeline via CLI subcommands

## Invariants

1. Machine-readable files live in `.machine_readable/` ONLY — never in root
2. Idris2 ABI is the specification; Zig FFI is the implementation
3. Generated C headers go in `src/interface/generated/abi/`
4. All workflows are SHA-pinned, all code is MPL-2.0
