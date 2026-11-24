# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# idris2-undefined.awk: print each top-level Idris2 type signature that has
# no clauses in the same file, as "FILE:LINE: NAME". Idris2 accepts such a
# declaration even under --total and treats it as a postulate, so a green
# type-check does not show the proofs are complete.
#
# Adapted from hyperpolymath/mathesis scripts/census/idris2-undefined.awk.
# One change: a signature after %foreign is an FFI binding and is skipped,
# but %extern is not skipped (the gate's audit refuses %extern outright).
#
# Usage: awk -f idris2-undefined.awk FILE...
function kw(n) { return n ~ /^(data|record|interface|implementation|module|import|namespace|parameters|mutual|total|partial|covering|public|export|private|infix|infixl|infixr|prefix|failing|using|where|let|in|do|if|then|else|case|of|with|rewrite|auto|default)$/ }
function flush(   n) { for (n in sig) if (!(n in def)) print FILENAME_PREV ":" sig[n] ": " n; delete sig; delete def }
FNR == 1 { if (NR > 1) flush(); FILENAME_PREV = FILENAME; depth = 0; ffi = 0 }
{
  # Blank comments: {- ... -} blocks (nesting counted per line), and -- or
  # ||| to end of line. A name in a doc comment must not count as defined.
  line = $0; out = ""
  while (length(line) > 0) {
    if (depth > 0) {
      o = index(line, "{-"); c = index(line, "-}")
      if (c > 0 && (o == 0 || c < o)) { depth--; line = substr(line, c + 2) }
      else if (o > 0) { depth++; line = substr(line, o + 2) }
      else line = ""
    } else {
      o = index(line, "{-"); d = match(line, /(^|[ \t(])(--|\|\|\|)/)
      if (o > 0 && (d == 0 || o < d)) { out = out substr(line, 1, o - 1); depth++; line = substr(line, o + 2) }
      else if (d > 0) { out = out substr(line, 1, d - 1 + (substr(line, d, 1) ~ /[ \t(]/)); line = "" }
      else { out = out line; line = "" }
    }
  }
  $0 = out
}
/^[ \t]*$/ { next }
/^%foreign/ { ffi = 1; next }
/^[ \t]/ { next }                                   # continuation / nested
/^((public[ \t]+)?export|private|covering|total|partial)[ \t]*$/ { next }
{
  s = $0
  sub(/^(public[ \t]+)?export[ \t]+/, "", s); sub(/^private[ \t]+/, "", s)
  sub(/^(covering|total|partial)[ \t]+/, "", s)
  sub(/^[01][ \t]+/, "", s)
  if (match(s, /^[A-Za-z_][A-Za-z0-9_']*[ \t]*:/) && substr(s, RLENGTH + 1, 1) != ":") {
    n = s; sub(/[ \t]*:.*/, "", n)
    if (!kw(n) && !ffi) sig[n] = FNR
  } else if (match($0, /^[A-Za-z_][A-Za-z0-9_']*/)) {
    def[substr($0, 1, RLENGTH)] = 1
  }
  t = $0  # infix clause: a `name` b = ...
  while (match(t, /`[A-Za-z_][A-Za-z0-9_']*`/)) { def[substr(t, RSTART + 1, RLENGTH - 2)] = 1; t = substr(t, RSTART + RLENGTH) }
  ffi = 0
}
END { if (NR > 0) flush() }
