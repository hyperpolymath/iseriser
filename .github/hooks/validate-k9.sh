#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# validate-k9.sh — K9 configuration file validation script
#
# K9 files come in two dialects, validated differently (standards#434):
#
#   Plain dialect (.k9) — text/YAML-ish documents. The `K9!` magic line is
#   the format marker and MUST be the first non-empty line. Fields use
#   `key: value` form.
#
#   Nickel dialect (.k9.ncl) — Nickel source. A bare `K9!` line is a Nickel
#   syntax error, so the format marker is carried differently: a
#   `magic_number = "K9!"` field, a literal `K9!` preamble line (template
#   files that are preprocessed before evaluation), or by construction —
#   the file imports/merges a K9 pedigree schema (`K9Pedigree`,
#   `pedigree_schema`, or an `import ".…k9.ncl"` of a base template that
#   itself carries the magic). Library/contractile modules are that last
#   class and are first-class citizens, not violations.
#
# Checks:
#   1. Format marker (dialect-appropriate, see above)
#   2. Pedigree presence with required fields (name; version as warning)
#   3. Security level (`leash`, `security_level`, or schema-v1 `trust_level`)
#      is one of: kennel, yard, hunt (case-insensitive)
#   4. Hunt-level files must have a signature or signature_required field
#   5. SPDX-License-Identifier header presence
#
# This is a LEXICAL linter (grep-grade), not a Nickel evaluator. Field
# checks are file-scope presence checks on purpose: Nickel lets authors
# factor the pedigree through `let` bindings and `&` merges, which no
# line-oriented block tracker can follow. (A previous version tracked
# brace depth to scope checks to the pedigree block; it missed every
# `let component_pedigree = {…}` factoring and miscounted its own opening
# brace. Do not reintroduce block scoping here — deep validation belongs
# to the Nickel contracts themselves.)
#
# Environment variables:
#   INPUT_PATH   — Directory to scan (default: .)
#   INPUT_STRICT — Promote warnings to errors (default: false)
#   INPUT_PATHS_IGNORE — Newline-separated path fragments to skip. When the
#                        variable is unset, estate-safe defaults are used. Set
#                        it to an empty string to scan every matching file.
#
# Exit codes:
#   0 — All files valid (or only warnings in non-strict mode)
#   1 — Validation errors found

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

SCAN_PATH="${INPUT_PATH:-.}"
STRICT="${INPUT_STRICT:-false}"

# Some estate files share the .k9/.k9.ncl suffix without being pedigree
# contracts. Others are deliberately invalid fixtures or vendored copies that
# belong to a different repository's validation boundary. These defaults were
# introduced in 47cca67, then accidentally lost when fa30044 absorbed the
# standards implementation. Keep the policy here as well as in action.yml so
# direct/pre-push invocations behave the same as the GitHub Action.
DEFAULT_PATHS_IGNORE=$'vendor/\nvendored/\nverified-container-spec/\n.audittraining/\nintegration/fixtures/\ntest/fixtures/\ntests/fixtures/\nabsolute-zero/\ncoordination.k9\nsession/custom-checks.k9\nself-validating/methodology-guard.k9.ncl'
if [[ ${INPUT_PATHS_IGNORE+x} == x ]]; then
    PATHS_IGNORE_RAW="$INPUT_PATHS_IGNORE"
else
    PATHS_IGNORE_RAW="$DEFAULT_PATHS_IGNORE"
fi

PATHS_IGNORE=()
while IFS= read -r fragment; do
    fragment="${fragment#"${fragment%%[![:space:]]*}"}"
    fragment="${fragment%"${fragment##*[![:space:]]}"}"
    [[ -z "$fragment" || "$fragment" == \#* ]] && continue
    PATHS_IGNORE+=("$fragment")
done <<< "$PATHS_IGNORE_RAW"

# Check if a file path matches any configured ignore fragment.
# Returns 0 (true) if the path should be skipped, 1 (false) otherwise.
path_ignored() {
    local path="$1" fragment
    for fragment in "${PATHS_IGNORE[@]}"; do
        [[ "$path" == *"$fragment"* ]] && return 0
    done
    return 1
}

# Remove K9/YAML/Nickel line comments while preserving hashes inside
# double-quoted strings. SPDX detection deliberately continues to use the raw
# file because its marker is itself a comment.
strip_k9_comment() {
    local input="$1" output="" char
    local in_double=false escaped=false i
    for ((i = 0; i < ${#input}; i++)); do
        char="${input:i:1}"
        if [[ "$escaped" == "true" ]]; then
            output+="$char"
            escaped=false
        elif [[ "$in_double" == "true" && "$char" == "\\" ]]; then
            output+="$char"
            escaped=true
        elif [[ "$char" == '"' ]]; then
            output+="$char"
            if [[ "$in_double" == "true" ]]; then
                in_double=false
            else
                in_double=true
            fi
        elif [[ "$char" == '#' && "$in_double" == "false" ]]; then
            break
        else
            output+="$char"
        fi
    done
    printf '%s\n' "$output"
}

comment_free_file() {
    local file="$1" line
    while IFS= read -r line; do
        strip_k9_comment "$line"
    done < "$file"
}

# Replace double-quoted string contents with spaces before classifying a file.
# Schema words in prose or metadata values are not reachable K9 syntax, while
# structural expressions such as `pedigree.K9Pedigree` remain visible.
mask_k9_quoted_text() {
    local input="$1" output="" char
    local in_double=false escaped=false i
    for ((i = 0; i < ${#input}; i++)); do
        char="${input:i:1}"
        if [[ "$in_double" == "true" ]]; then
            if [[ "$escaped" == "true" ]]; then
                output+=" "
                escaped=false
            elif [[ "$char" == "\\" ]]; then
                output+=" "
                escaped=true
            elif [[ "$char" == '"' ]]; then
                output+="$char"
                in_double=false
            else
                output+=" "
            fi
        elif [[ "$char" == '"' ]]; then
            output+="$char"
            in_double=true
        else
            output+="$char"
        fi
    done
    printf '%s\n' "$output"
}

structural_syntax_file() {
    local file="$1" line
    while IFS= read -r line; do
        mask_k9_quoted_text "$(strip_k9_comment "$line")"
    done < "$file"
}

# Check if a file is a K9 pedigree contract by searching for unambiguous
# pedigree signals (K9!, magic_number, pedigree metadata, or K9 schema reference).
# Returns 0 (true) if the file is a pedigree contract, 1 (false) otherwise.
is_pedigree_contract() {
    local file="$1" syntax_content
    syntax_content=$(structural_syntax_file "$file")
    grep -Eq \
        '^[[:space:]]*K9![[:space:]]*$|^[[:space:]]*magic_number[[:space:]]*[=:]|^[[:space:]]*(let[[:space:]]+)?[A-Za-z_]*pedigree[[:space:]]*=|^[[:space:]]*(metadata|pedigree):[[:space:]]*$|K9Pedigree|pedigree_schema' \
        <<< "$syntax_content"
}

# Outside GitHub Actions GITHUB_OUTPUT is unset; under `set -u` an unset
# expansion inside a redirection aborts the whole script (the `|| true`
# cannot catch an expansion error). Default to /dev/null for local runs.
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

# Counters
FILES_SCANNED=0
ERRORS=0
WARNINGS=0

# Valid security levels (the leash metaphor)
VALID_LEVELS="kennel yard hunt"

# ---------------------------------------------------------------------------
# Helper: emit GitHub annotation
# ---------------------------------------------------------------------------
annotate() {
    local level="$1" file="$2" line="$3" message="$4"
    echo "::${level} file=${file},line=${line}::${message}"
}

# ---------------------------------------------------------------------------
# Helper: report issue (respects strict mode)
# ---------------------------------------------------------------------------
report_issue() {
    local severity="$1" file="$2" line="$3" message="$4"

    if [[ "$severity" == "warning" && "$STRICT" == "true" ]]; then
        severity="error"
    fi

    annotate "$severity" "$file" "$line" "$message"

    if [[ "$severity" == "error" ]]; then
        ERRORS=$((ERRORS + 1))
    else
        WARNINGS=$((WARNINGS + 1))
    fi
}

# ---------------------------------------------------------------------------
# Helper: normalise a security level string
# ---------------------------------------------------------------------------
# Strips quotes, leading/trailing whitespace, Nickel enum tick prefix.
# Handles both separators: `leash = 'Hunt` (Nickel) and `leash: hunt` (plain).
normalise_level() {
    local raw="$1"
    # Remove surrounding quotes, tick prefix ('Kennel -> Kennel), whitespace
    if [[ "$raw" == *"="* ]]; then
        raw="${raw#*=}"          # Remove everything before =
    else
        raw="${raw#*:}"          # Plain dialect: remove everything before :
    fi
    raw="${raw//\"/}"            # Remove double quotes
    raw="${raw//\'/}"            # Remove single quotes (Nickel tick)
    raw="${raw//,/}"             # Remove trailing commas
    raw="${raw%%#*}"             # Remove inline comments
    # Trim ALL leading/trailing whitespace (a single-space `%% ` pattern
    # strips only one char and let `'Kennel  # comment` survive as
    # "kennel " — an invalid-level false positive)
    raw="${raw#"${raw%%[![:space:]]*}"}"
    raw="${raw%"${raw##*[![:space:]]}"}"
    echo "${raw,,}"             # Lowercase
}

# ---------------------------------------------------------------------------
# Validator: check a single K9 file
# ---------------------------------------------------------------------------
validate_k9() {
    local file="$1"
    local syntax_content
    syntax_content=$(comment_free_file "$file")
    FILES_SCANNED=$((FILES_SCANNED + 1))

    # Dialect: .k9.ncl is Nickel source; bare .k9 is the plain dialect.
    local dialect="plain"
    if [[ "$file" == *.k9.ncl ]]; then
        dialect="ncl"
    fi

    # --- Check 1: format marker (dialect-appropriate) ---
    local first_content_line=""
    local first_content_line_num=0
    local line_num=0

    while IFS= read -r line; do
        line_num=$((line_num + 1))
        # Skip empty lines
        if [[ -z "${line// /}" ]]; then
            continue
        fi
        first_content_line="$line"
        first_content_line_num=$line_num
        break
    done < "$file"

    if [[ "$dialect" == "plain" ]]; then
        if [[ "$first_content_line" != "K9!" ]]; then
            report_issue "error" "$file" "$first_content_line_num" \
                "Missing K9! magic number. First non-empty line must be exactly 'K9!'"
        fi
    else
        # Nickel dialect: a bare K9! line is a Nickel syntax error, so the
        # marker may instead be a magic_number field or arrive by construction
        # through a pedigree-schema import/merge (library modules, #434).
        local has_marker=false
        if [[ "$first_content_line" == "K9!" ]]; then
            has_marker=true
        elif grep -Eq '^[[:space:]]*magic_number[[:space:]]*=[[:space:]]*"K9!"' <<< "$syntax_content"; then
            has_marker=true
        elif grep -Eq '(K9Pedigree|pedigree_schema)([[:space:]]*&|[[:space:]]*\{)|&[[:space:]]*(.*\.)?(K9Pedigree|pedigree_schema)|import[[:space:]]*"[^"]*(pedigree|\.k9)\.ncl"' <<< "$syntax_content"; then
            has_marker=true
        fi

        if [[ "$has_marker" == "false" ]]; then
            report_issue "error" "$file" "$first_content_line_num" \
                "Missing K9 format marker. A .k9.ncl file needs a magic_number = \"K9!\" field, a K9! preamble line, or a K9 pedigree schema import/application/merge"
        fi
    fi

    # --- Check 2: SPDX header ---
    local has_spdx=false
    line_num=0
    while IFS= read -r line; do
        line_num=$((line_num + 1))
        if [[ $line_num -gt 10 ]]; then
            break
        fi
        if [[ "$line" == *"SPDX-License-Identifier"* ]]; then
            has_spdx=true
            break
        fi
    done < "$file"

    if [[ "$has_spdx" == "false" ]]; then
        report_issue "warning" "$file" 1 \
            "Missing SPDX-License-Identifier in first 10 lines"
    fi

    # --- Check 3: Pedigree presence with required fields ---
    # File-scope scans by design (see header): Nickel factoring means the
    # pedigree may be `pedigree = {…}`, a let-bound `let component_pedigree
    # = {…}`, a schema merge `X.pedigree_schema & {…}` / `X.K9Pedigree &
    # {…}`, or — plain dialect — a `metadata:`/`pedigree:` YAML block.
    local has_pedigree=false
    local has_pedigree_name=false
    local has_pedigree_version=false
    local has_security_level=false
    local has_primary_security_level=false
    local security_level_value=""
    local security_level_line=0
    local has_signature_field=false
    local in_policy=false
    local policy_depth=0

    line_num=0
    while IFS= read -r line; do
        line_num=$((line_num + 1))

        if [[ "$line" =~ (^|[[:space:]\{,])policy[[:space:]]*=[[:space:]]*\{ ]]; then
            in_policy=true
            policy_depth=0
        fi

        # Pedigree construct, Nickel forms: direct, let-bound, schema
        # application (`K9Pedigree { ... }`), or schema merge.
        if [[ "$line" =~ ^[[:space:]]*(let[[:space:]]+)?[A-Za-z_]*pedigree[[:space:]]*= ]] \
           || [[ "$line" =~ (K9Pedigree|pedigree_schema)[[:space:]]*\{ ]] \
           || [[ "$line" =~ (K9Pedigree|pedigree_schema)[[:space:]]*\& ]] \
           || [[ "$line" =~ \&[[:space:]]*([A-Za-z_][A-Za-z0-9_]*\.)?(K9Pedigree|pedigree_schema) ]]; then
            has_pedigree=true
        fi

        # Pedigree construct, plain dialect: top-level metadata:/pedigree: block
        if [[ "$dialect" == "plain" ]] \
           && [[ "$line" =~ ^(metadata|pedigree):[[:space:]]*$ ]]; then
            has_pedigree=true
        fi

        # Required fields, either separator (= Nickel, : plain)
        if [[ "$line" =~ (^|[[:space:]\{,])name[[:space:]]*[=:] ]]; then
            has_pedigree_name=true
        fi

        if [[ "$line" =~ (^|[[:space:]\{,])(version|schema_version)[[:space:]]*[=:] ]]; then
            has_pedigree_version=true
        fi

        # Security level (leash field)
        if [[ "$line" =~ (^|[[:space:]\{,])(leash|security_level)[[:space:]]*[=:][[:space:]]*([^,\}\#]+) ]]; then
            has_security_level=true
            has_primary_security_level=true
            security_level_value="$(normalise_level "${BASH_REMATCH[0]}")"
            security_level_line=$line_num
        elif [[ "$has_primary_security_level" == "false" ]]; then
            local trust_is_policy=false
            if [[ "$line" =~ policy[[:space:]]*\.[[:space:]]*trust_level[[:space:]]*[=:] ]] \
               || [[ "$in_policy" == "true" && "$line" =~ (^|[[:space:]\{,])trust_level[[:space:]]*[=:] ]] \
               || [[ "$line" =~ (^|[[:space:]\{,])policy[[:space:]]*=[[:space:]]*\{[^\}]*trust_level[[:space:]]*[=:] ]]; then
                trust_is_policy=true
            fi
            if [[ "$trust_is_policy" == "true" ]] \
               && [[ "$line" =~ trust_level[[:space:]]*[=:][[:space:]]*([^,\}]+) ]]; then
                # Only schema-v1 policy.trust_level is a leash. Legacy
                # pedigree-level trust_level is descriptive metadata.
                has_security_level=true
                security_level_value="$(normalise_level "${BASH_REMATCH[0]}")"
                security_level_line=$line_num
            fi
        fi

        # Signature fields
        if [[ "$line" =~ (^|[[:space:]\{,])(signature|signature_required)[[:space:]]*[=:] ]]; then
            has_signature_field=true
        fi

        if [[ "$in_policy" == "true" ]]; then
            local without_open="${line//\{/}"
            local without_close="${line//\}/}"
            policy_depth=$((policy_depth + ${#line} - ${#without_open} - ${#line} + ${#without_close}))
            if (( policy_depth <= 0 )); then
                in_policy=false
                policy_depth=0
            fi
        fi
    done <<< "$syntax_content"

    if [[ "$has_pedigree" == "false" ]]; then
        report_issue "error" "$file" 1 \
            "Missing pedigree. K9 files need a pedigree section: 'pedigree = { ... }', a pedigree-schema merge, or (plain dialect) a 'metadata:' block"
    else
        if [[ "$has_pedigree_name" == "false" ]]; then
            report_issue "error" "$file" 1 \
                "Pedigree block missing 'name' field (in pedigree.metadata.name or pedigree.name)"
        fi

        if [[ "$has_pedigree_version" == "false" ]]; then
            report_issue "warning" "$file" 1 \
                "Pedigree block missing 'version' or 'schema_version' field"
        fi
    fi

    # --- Check 4: Security level validation ---
    if [[ "$has_security_level" == "true" && "$security_level_value" =~ ^\{\{.*\}\}$ ]]; then
        # Scaffold file: the level is a template placeholder to be filled at
        # instantiation time. Note it, but a template cannot validate as
        # concrete and flagging it every run just trains people to ignore
        # the gate.
        annotate "notice" "$file" "$security_level_line" \
            "Security level is a template placeholder (${security_level_value}); skipping level validation"
    elif [[ "$has_security_level" == "true" ]]; then
        local level_valid=false
        for valid in $VALID_LEVELS; do
            if [[ "$security_level_value" == "$valid" ]]; then
                level_valid=true
                break
            fi
        done

        if [[ "$level_valid" == "false" ]]; then
            report_issue "error" "$file" "$security_level_line" \
                "Invalid security level '${security_level_value}'. Must be one of: kennel, yard, hunt"
        fi
    else
        if [[ "$has_pedigree" == "true" ]]; then
            report_issue "warning" "$file" 1 \
                "No security level (leash/security_level) found in pedigree block"
        fi
    fi

    # --- Check 5: Hunt-level signature requirement ---
    if [[ "$security_level_value" == "hunt" && "$has_signature_field" == "false" ]]; then
        report_issue "error" "$file" "$security_level_line" \
            "Hunt-level K9 file must include a 'signature' or 'signature_required' field"
    fi
}

# ---------------------------------------------------------------------------
# Main: discover and validate K9 files
# ---------------------------------------------------------------------------

echo "::group::K9 Configuration Validation"
echo "Scanning ${SCAN_PATH} for K9 files (.k9, .k9.ncl)..."
echo ""

# Find all K9 files, excluding .git and non-target paths.
mapfile -t k9_candidates < <(find "$SCAN_PATH" \( -name '*.k9' -o -name '*.k9.ncl' \) -not -path '*/.git/*' -type f | sort)

k9_files=()
FILES_SKIPPED=0
FILES_SKIPPED_PATH=0
FILES_SKIPPED_NON_CONTRACT=0
for file in "${k9_candidates[@]}"; do
    if path_ignored "$file"; then
        FILES_SKIPPED=$((FILES_SKIPPED + 1))
        FILES_SKIPPED_PATH=$((FILES_SKIPPED_PATH + 1))
        echo "::notice file=${file}::Skipped non-target K9 path"
        continue
    fi
    if ! is_pedigree_contract "$file"; then
        FILES_SKIPPED=$((FILES_SKIPPED + 1))
        FILES_SKIPPED_NON_CONTRACT=$((FILES_SKIPPED_NON_CONTRACT + 1))
        echo "::notice file=${file}::Skipped K9-suffixed file with no pedigree-contract signal"
        continue
    fi
    k9_files+=("$file")
done

if [[ $FILES_SKIPPED -gt 0 ]]; then
    echo "Skipped ${FILES_SKIPPED} non-target K9 file(s) (${FILES_SKIPPED_PATH} by path, ${FILES_SKIPPED_NON_CONTRACT} without a pedigree signal)"
    echo ""
fi

if [[ ${#k9_files[@]} -eq 0 ]]; then
    echo "::notice::No K9 files found in ${SCAN_PATH}"
    echo "files_scanned=0" >> "$GITHUB_OUTPUT" 2>/dev/null || true
    echo "files_skipped=${FILES_SKIPPED}" >> "$GITHUB_OUTPUT" 2>/dev/null || true
    echo "errors=0" >> "$GITHUB_OUTPUT" 2>/dev/null || true
    echo "warnings=0" >> "$GITHUB_OUTPUT" 2>/dev/null || true
    echo "::endgroup::"
    exit 0
fi

echo "Found ${#k9_files[@]} K9 file(s)"
echo ""

for file in "${k9_files[@]}"; do
    echo "  Validating: ${file}"
    validate_k9 "$file"
done

echo ""
echo "────────────────────────────────────────"
echo "Files scanned: ${FILES_SCANNED}"
echo "Files skipped: ${FILES_SKIPPED}"
echo "Errors:        ${ERRORS}"
echo "Warnings:      ${WARNINGS}"
echo "Strict mode:   ${STRICT}"
echo "────────────────────────────────────────"

# Write outputs for GitHub Actions
{
    echo "files_scanned=${FILES_SCANNED}"
    echo "files_skipped=${FILES_SKIPPED}"
    echo "errors=${ERRORS}"
    echo "warnings=${WARNINGS}"
} >> "$GITHUB_OUTPUT" 2>/dev/null || true

echo "::endgroup::"

# Exit with failure if errors were found
if [[ $ERRORS -gt 0 ]]; then
    echo "::error::K9 validation failed with ${ERRORS} error(s)"
    exit 1
fi

echo "K9 validation passed."
exit 0
