#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Regression controls for the actual structural ABI gate, not compiled proofs.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
mkdir -p "$fixture/src/interface/abi" "$fixture/src/interface/ffi/src"
abi="$fixture/src/interface/abi/Types.idr"
ffi="$fixture/src/interface/ffi/src/main.zig"
printf '%%foreign "C:sample"\nresultToInt Ok = 0\nresultToInt Error = 1\n' > "$abi"
printf 'export fn sample() void {}\nconst Result = enum(c_int) { ok = 0, err = 1 };\n' > "$ffi"
julia "$repo_root/scripts/abi-ffi-gate.jl" "$fixture"
cp "$abi" "$fixture/valid.idr"
cp "$ffi" "$fixture/valid.zig"
# reject verifies that the ABI/FFI gate rejects the fixture with exit status 1 for the named invalid condition.
reject() {
  local name="$1" status=0
  julia "$repo_root/scripts/abi-ffi-gate.jl" "$fixture" > "$fixture/result.log" 2>&1 || status=$?
  if [ "$status" -ne 1 ]; then
    cat "$fixture/result.log"
    echo "Expected structural rejection for $name; got $status" >&2
    exit 1
  fi
  echo "Rejected: $name"
}
mv "$abi" "$fixture/temporarily-absent.idr"
reject 'missing Idris ABI sources'
mv "$fixture/temporarily-absent.idr" "$abi"
mv "$ffi" "$fixture/temporarily-absent.zig"
reject 'missing Zig FFI source'
mv "$fixture/temporarily-absent.zig" "$ffi"
printf '%%foreign "C:sample"\n' > "$abi"
reject 'missing Idris result mapping'
cp "$fixture/valid.idr" "$abi"
printf 'export fn sample() void {}\n' > "$ffi"
reject 'missing Zig result mapping'
printf 'export fn sample() void {}\nconst Result = enum(c_int) { ok = 0, err = 2 };\n' > "$ffi"
reject 'mismatched result code'
cp "$fixture/valid.zig" "$ffi"
julia "$repo_root/scripts/abi-ffi-gate.jl" "$fixture"
