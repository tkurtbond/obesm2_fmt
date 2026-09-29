#!/usr/bin/env bash
# Golden-output tests (PLAN.md, section 8).  Run from the repo root.
#
#   test/golden.sh check [PROGRAM]   compare PROGRAM's output (default
#                                    ./besm2_fmt) with test/golden/
#   test/golden.sh generate          rewrite test/golden/ from the
#                                    reference programs
#
# The cases are in test/golden.cases.  generate runs each case's
# reference program: $ADA_BESM2_FMT (default
# ~/Repos/RPG/Tools/besm2_fmt/besm2_fmt) or $SCHEME_BESM2_RST (default
# besm2-rst on PATH).  Never edit a golden file by hand.
#
# check prints ok/FAIL per case, with a diff for a failure, and exits 1
# if any failed.

set -u
mode=${1:-check}
prog=${2:-./besm2_fmt}
ada=${ADA_BESM2_FMT:-$HOME/Repos/RPG/Tools/besm2_fmt/besm2_fmt}
scheme=${SCHEME_BESM2_RST:-besm2-rst}
cases=test/golden.cases
golden=test/golden
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failed=0 count=0

[ "$mode" = generate ] && mkdir -p "$golden"

while read -r ref id pattern flags; do
  case $ref in ''|'#'*) continue ;; esac
  case $ref in
    ada) refprog=$ada ;;
    scheme) refprog=$scheme ;;
    *) echo "golden.sh: bad reference '$ref' in $cases" >&2; exit 2 ;;
  esac
  for f in test/data/$pattern.yaml; do
    [ -e "$f" ] || { echo "golden.sh: no fixture matches $pattern" >&2; exit 2; }
    base=$(basename "$f" .yaml)
    out=$golden/$base.$id.out
    count=$((count + 1))
    if [ "$mode" = generate ]; then
      # $flags is split into words on purpose.
      # shellcheck disable=SC2086
      "$refprog" $flags "$f" >"$out" 2>&1 </dev/null
      status=$?
      if [ $status -ne 0 ]; then
        echo "golden.sh: $refprog $flags $f exited $status" >&2; exit 2
      fi
    else
      # shellcheck disable=SC2086
      "$prog" $flags "$f" >"$tmp/out" 2>&1 </dev/null
      status=$?
      if [ ! -e "$out" ]; then
        echo "FAIL - $base $id: no golden file (make golden)"; failed=$((failed + 1))
      elif [ $status -ne 0 ]; then
        echo "FAIL - $base $id ($flags): exit $status"; failed=$((failed + 1))
      elif ! cmp -s "$out" "$tmp/out"; then
        echo "FAIL - $base $id ($flags)"; diff "$out" "$tmp/out" | head -20 | sed 's/^/    /'
        failed=$((failed + 1))
      else
        echo "ok   - $base $id ($flags)"
      fi
    fi
  done
done <"$cases"

if [ "$mode" = generate ]; then
  echo "Wrote $count golden files to $golden/."
elif [ $failed -eq 0 ]; then
  echo "All checks passed."
else
  echo "$failed check(s) failed."; exit 1
fi
