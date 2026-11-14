#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Test script for invisible character detection (local verification)
# This tests the logic from .github/workflows/dogfood-gate.yml

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES_DIR="${SCRIPT_DIR}/fixtures/invisible-chars"

echo "Testing invisible character detection..."
echo

# Test 1: Clean file should not trigger blocking
echo "Test 1: Clean file (should PASS)"
if grep -qaP '\x00|[\x01-\x08\x0B\x0C\x0E-\x1F]' "${FIXTURES_DIR}/clean.rs"; then
    echo "  ❌ FAIL: Clean file triggered C0 detection"
    exit 1
fi
if [ "$(head -c 3 "${FIXTURES_DIR}/clean.rs" | od -An -tx1 | tr -d ' ')" = "efbbbf" ]; then
    echo "  ❌ FAIL: Clean file triggered BOM detection"
    exit 1
fi
echo "  ✓ PASS"
echo

# Test 2: Legitimate whitespace should not trigger blocking
echo "Test 2: Legitimate whitespace (should PASS)"
if grep -qaP '\x00|[\x01-\x08\x0B\x0C\x0E-\x1F]' "${FIXTURES_DIR}/legitimate-whitespace.rs"; then
    echo "  ❌ FAIL: Legitimate whitespace triggered C0 detection"
    exit 1
fi
if [ "$(head -c 3 "${FIXTURES_DIR}/legitimate-whitespace.rs" | od -An -tx1 | tr -d ' ')" = "efbbbf" ]; then
    echo "  ❌ FAIL: Legitimate whitespace triggered BOM detection"
    exit 1
fi
echo "  ✓ PASS"
echo

# Test 3: Leading BOM should trigger blocking
echo "Test 3: Leading BOM (should BLOCK)"
if [ "$(head -c 3 "${FIXTURES_DIR}/leading-bom.rs" | od -An -tx1 | tr -d ' ')" = "efbbbf" ]; then
    echo "  ✓ PASS: Leading BOM detected"
else
    echo "  ❌ FAIL: Leading BOM not detected"
    exit 1
fi
echo

# Test 4: NUL byte should trigger blocking
echo "Test 4: NUL byte (should BLOCK)"
if grep -qaP '\x00|[\x01-\x08\x0B\x0C\x0E-\x1F]' "${FIXTURES_DIR}/nul-byte.rs"; then
    echo "  ✓ PASS: NUL byte detected"
else
    echo "  ❌ FAIL: NUL byte not detected"
    exit 1
fi
echo

# Test 5: Backspace should trigger blocking
echo "Test 5: Backspace (C0 control, should BLOCK)"
if grep -qaP '\x00|[\x01-\x08\x0B\x0C\x0E-\x1F]' "${FIXTURES_DIR}/backspace.rs"; then
    echo "  ✓ PASS: Backspace detected"
else
    echo "  ❌ FAIL: Backspace not detected"
    exit 1
fi
echo

# Test 6: Vertical tab should trigger blocking
echo "Test 6: Vertical tab (C0 control, should BLOCK)"
if grep -qaP '\x00|[\x01-\x08\x0B\x0C\x0E-\x1F]' "${FIXTURES_DIR}/vertical-tab.rs"; then
    echo "  ✓ PASS: Vertical tab detected"
else
    echo "  ❌ FAIL: Vertical tab not detected"
    exit 1
fi
echo

# Test 7: Form feed should trigger blocking
echo "Test 7: Form feed (C0 control, should BLOCK)"
if grep -qaP '\x00|[\x01-\x08\x0B\x0C\x0E-\x1F]' "${FIXTURES_DIR}/form-feed.rs"; then
    echo "  ✓ PASS: Form feed detected"
else
    echo "  ❌ FAIL: Form feed not detected"
    exit 1
fi
echo

# Test 8: Escape character should trigger blocking
echo "Test 8: Escape character (C0 control, should BLOCK)"
if grep -qaP '\x00|[\x01-\x08\x0B\x0C\x0E-\x1F]' "${FIXTURES_DIR}/escape.rs"; then
    echo "  ✓ PASS: Escape character detected"
else
    echo "  ❌ FAIL: Escape character not detected"
    exit 1
fi
echo

echo "=========================================="
echo "All tests passed! ✓"
echo "=========================================="
echo
echo "Detection rules verified:"
echo "  • C0 control characters (\\x00-\\x08, \\x0B, \\x0C, \\x0E-\\x1F): BLOCKING"
echo "  • Leading BOM (EF BB BF at position 0): BLOCKING"
echo "  • Legitimate whitespace (tabs, newlines, spaces): ALLOWED"
echo
