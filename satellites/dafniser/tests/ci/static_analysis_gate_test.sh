#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Negative and positive controls for the static-analysis gate workflow steps.
# Run from the repository root. Needs bash, jq and yq (preinstalled on GitHub runners).
set -uo pipefail
# Bash 5.2 treats & in a replacement as the matched text; keep it literal.
shopt -u patsub_replacement 2>/dev/null || true

wf=.github/workflows/static-analysis-gate.yml
step() { # job, step name -> run script text
  yq -r ".jobs[\"$1\"].steps[] | select(.name == \"$2\") | .run" "$wf"
}
assail=$(step panic-attack-assail 'Run panic-attack assail')
build=$(step hypatia-scan 'Clone and build Hypatia')
[ -n "$assail" ] && [ -n "$build" ] || { echo 'could not extract workflow steps' >&2; exit 1; }

dir=$(mktemp -d -t scanner-gate-XXXXXX)
trap 'rm -rf "$dir"' EXIT
bin="$dir/bin"
mkdir -p "$bin"
output="$dir/outputs"

cat > "$bin/panic-attack" <<'SH'
#!/bin/bash
printf '%s' "$REPORT"
printf '%s\n' 'scanner diagnostic' >&2
SH
cat > "$bin/git" <<'SH'
#!/bin/bash
test "$FAIL_STAGE" != clone || exit 71
mkdir -p "${@: -1}"
touch "${@: -1}/mix.exs" "${@: -1}/hypatia-cli.sh"
chmod +x "${@: -1}/hypatia-cli.sh"
SH
cat > "$bin/mix" <<'SH'
#!/bin/bash
test "$FAIL_STAGE" != "$1" || exit 72
SH
chmod 755 "$bin"/*

# jq and yq may live outside /usr/bin on a dev machine; keep their directory on PATH.
tools=$(dirname "$(command -v jq)")
stub_path="$bin:/usr/bin:/bin:$tools"

# run <script> [VAR=value ...]: run a workflow step in the scratch dir, merged output in $log.
run() {
  local script=$1; shift
  log=$(cd "$dir" && env PATH="$stub_path" GITHUB_OUTPUT="$output" RUNNER_TEMP="$dir" "$@" \
    bash -e -o pipefail -c "$script" 2>&1)
}
fail() { printf '%s\n' "$1" >&2; exit 1; }

for report in '[]' '[{"severity":"critical"}]'; do
  : > "$output"
  run "$assail" REPORT="$report" || fail "$log"
  if [[ $report == *critical* ]] && ! grep -qx 'critical=1' "$output"; then
    fail 'critical finding was lost'
  fi
done

for report in '' '{}' 'null' '"text"' 'broken JSON'; do
  if run "$assail" REPORT="$report"; then
    fail "invalid payload accepted: $report"$'\n'"$log"
  fi
done

contaminated=${assail/> panic-attack-findings.json/> panic-attack-findings.json 2>&1}
[ "$contaminated" != "$assail" ] || fail 'stderr redirection control did not match the workflow'
if run "$contaminated" REPORT='[]'; then
  fail "stderr contamination was accepted: $log"
fi

for stage in '' clone deps.get escript.build; do
  rm -rf "$dir/hypatia"
  : > "$output"
  if run "$build" FAIL_STAGE="$stage"; then ok=1; else ok=0; fi
  if [ -z "$stage" ]; then want=1; else want=0; fi
  [ "$ok" = "$want" ] || fail "unexpected build result for ${stage:-none}: $log"
  if [ -n "$stage" ] && grep -q 'ready=true' "$output"; then
    fail 'failed setup reported ready'
  fi
done

echo 'PASS: valid reports, critical finding, malformed payloads, and clone/dependency/build failure controls'