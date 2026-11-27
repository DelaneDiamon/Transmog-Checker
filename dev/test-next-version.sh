#!/usr/bin/env bash
# Runs the "Determine next version" step of .github/workflows/release-on-push.yml
# against fake tag lists. The real repo's tags are never read or changed.
# Usage, from the repo root: bash dev/test-next-version.sh
set -u
workflow=".github/workflows/release-on-push.yml"

# The step's shell, taken from the workflow itself so the test cannot drift from it
step=$(awk '
  /- name: Determine next version/ { in_step = 1; next }
  in_step && /^      - name:/ { exit }
  in_step && /run: \|/ { in_run = 1; next }
  in_run { sub(/^          /, ""); print }
' "$workflow")
[ -n "$step" ] || { echo "version step not found in $workflow" >&2; exit 1; }

real_tags="0.0.1 0.0.2 0.0.3 0.0.4 0.0.5 0.0.6 0.0.7 0.0.8 0.0.9 0.0.11 0.0.12 0.0.13 0.0.14 0.0.15 0.0.16 0.0.17 0.0.18 0.0.19 0.0.20 0.0.21 0.0.22 v0.0.8 v0.0.8.1 v0.0.9 v0.0.10"

failed=0
check() {  # check <label> <expected> <tags...>
  local label="$1" expected="$2"; shift 2
  local out got
  out=$(mktemp)
  FAKE_TAGS="$*" GITHUB_OUTPUT="$out" bash -c '
    git() {  # shim: "fetch" does nothing, "tag -l" lists the fake tags
      case "$1" in
        fetch) ;;
        tag) for t in $FAKE_TAGS; do echo "$t"; done ;;
      esac
    }
    '"$step"
  got=$(sed -n 's/^next_tag=//p' "$out")
  rm -f "$out"
  if [ "$got" = "$expected" ]; then
    echo "ok   $label: $got"
  else
    echo "FAIL $label: got '$got', expected '$expected'"; failed=1
  fi
}

check "real tags today"   1.1.0  $real_tags
check "plus 1.0.0"        1.1.0  $real_tags 1.0.0
check "plus 1.0.9"        1.1.0  $real_tags 1.0.0 1.0.9
check "plus 1.2.3"        1.2.4  $real_tags 1.0.0 1.0.9 1.2.3
check "no tags"           1.1.0
exit $failed
