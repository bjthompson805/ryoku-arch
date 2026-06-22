#!/usr/bin/env bash
# Run the shell's pure-JS unit tests: the *.test.mjs files that exercise the
# logic helpers behind the Quickshell surfaces (the launcher fuzzy ranker and the
# ryoshot coordinate/keymap/annotation libs). These have no Quickshell or display
# dependency, so they run anywhere node is present, and unlike the advisory
# qmllint job this is a real gate. Nothing to maintain here: the runner discovers
# every ryoku/shell/**/*.test.mjs automatically, so a new test file is picked up
# the moment it lands next to the code it covers.
set -euo pipefail

ROOT=${RYOKU_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}

if ! command -v node >/dev/null 2>&1; then
  echo "::error::node is required to run the shell unit tests" >&2
  exit 1
fi

mapfile -d '' tests < <(find "$ROOT/ryoku/shell" -name '*.test.mjs' -type f -print0 | sort -z)

if (( ${#tests[@]} == 0 )); then
  echo "::error::no shell unit tests found under ryoku/shell" >&2
  exit 1
fi

failed=()
for t in "${tests[@]}"; do
  echo "== ${t#"$ROOT/"} =="
  node "$t" || failed+=("${t#"$ROOT/"}")
  echo
done

if (( ${#failed[@]} )); then
  echo "::error::shell unit tests failed:" >&2
  printf '  %s\n' "${failed[@]}" >&2
  exit 1
fi

echo "shell-unit-tests: all ${#tests[@]} test file(s) passed"
