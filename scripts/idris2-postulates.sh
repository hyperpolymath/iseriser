#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# idris2-postulates.sh DIR: run after the package in DIR has type-checked.
# Idris2 0.8.0 accepts a signature with no clauses (a postulate) and a
# %extern declaration even under --total, so a green type-check does not
# show that every proof has a body. This asks Idris2 itself: every name
# declared with a signature in each module is looked up with the REPL's
# :di command, which reports "undefined" for a postulate and "External
# definition" for %extern. %foreign bindings report "Foreign definition"
# and pass. Printing each offending name, it exits 1 if there is any.
#
# Names are taken from every "name :" line at any indentation, so
# declarations inside namespace, parameters and mutual blocks, and names
# that are operators or not ASCII, are all checked. Over-matching is
# harmless: a candidate that is not a name prints nothing. Names local to
# a where block cannot be looked up through the REPL and are not checked
# (known gap). Block comments that share a line with code, and %foreign
# outside Foreign.idr/Types.idr, are refused rather than parsed.
set -euo pipefail

dir=${1:?usage: idris2-postulates.sh DIR}
cd "$dir"
fail=0
set -f  # names such as (*) must not glob
while IFS= read -r -d '' file; do
  # Fail closed on a block comment that shares a line with code: Idris2
  # allows {- -} between any two tokens, which would hide a name from the
  # scan below. Whole-line {- ... -} comments are fine and are skipped.
  inline=$(grep -nE '[^[:space:]].*\{-|\{-.*-\}[[:space:]]*[^[:space:]]' "$file" | grep -vE '^[0-9]+:[[:space:]]*--' || true)
  if [ -n "$inline" ]; then
    printf '%s\n' "$inline" | sed "s|^|$dir/$file: block comment shares a line with code: |"
    fail=1
  fi
  # %foreign trusts the C side and is not checked by the type-checker, so it
  # may only appear in the FFI binding modules.
  case ${file##*/} in
    Foreign.idr|Types.idr) ;;
    *)
      if grep -qE '^[[:space:]]*%foreign' "$file"; then
        echo "$dir/$file: %foreign outside Foreign.idr/Types.idr"
        fail=1
      fi ;;
  esac
  names=$(awk '
    { s = $0; sub(/^[ \t]+/, "", s) }
    s ~ /^(--|\|\|\||\{-)/ { next }
    {
      while (match(s, /^(public|export|private|total|partial|covering|0|1)[ \t]+/))
        s = substr(s, RLENGTH + 1)
      if (match(s, /^[^ \t:]+[ \t]*:/) && substr(s, RLENGTH + 1, 1) != ":") {
        n = substr(s, 1, RLENGTH - 1); sub(/[ \t]+$/, "", n)
        if (n !~ /^\(/ || n ~ /\)$/) print n
      }
    }' "$file" | sort -u)
  [ -n "$names" ] || continue
  out=$(printf ':di %s\n' $names | idris2 --no-banner --find-ipkg "$file" 2>&1)
  # Each definition :di prints starts with a header line naming it
  # ("Mod.name", "0 Mod.name"), after the prompt for the first one and on
  # its own line for the rest (an overloaded name such as (<+>) prints the
  # Prelude's definition too). The line after the header says "undefined"
  # for a postulate and "External definition:" for %extern.
  bad=$(printf '%s\n' "$out" | awk '
    { l = $0; sub(/^[^ ]*> /, "", l) }
    (l == "undefined" || l == "External definition:") && n != "" { print n ": " l; n = ""; next }
    l ~ /^([01] )?[^ ]+$/ && l !~ /:$/ { n = l; sub(/^[01] /, "", n); next }
    { n = "" }')
  if [ -n "$bad" ]; then
    printf '%s\n' "$bad" | sed "s|^|$dir/$file: |"
    fail=1
  fi
done < <(find . -name '*.idr' -not -path './build/*' -print0)
exit "$fail"
