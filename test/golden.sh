#!/usr/bin/env bash
# Golden-output tests (PLAN.md, section 8).  Run from the repo root.
#
#   test/golden.sh check [PROGRAM]   compare PROGRAM's output (default
#                                    ./obesm2_fmt) with test/golden/
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
prog=${2:-./obesm2_fmt}
ada=${ADA_BESM2_FMT:-$HOME/Repos/RPG/Tools/besm2_fmt/besm2_fmt}
scheme=${SCHEME_BESM2_RST:-besm2-rst}
cases=test/golden.cases
golden=test/golden
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failed=0 count=0

[ "$mode" = generate ] && mkdir -p "$golden"

# run PROGRAM OUT FILES...: run PROGRAM as case $refmodes says, with
# $flags, writing what is compared to OUT, then a "==== exit 1 ===="
# line if it exited 1 (an input error, reported); return its exit
# status.
run() {
  local p=$1 o=$2 st; shift 2
  local in=/dev/null
  if [[ $refmodes == *:stdin:* ]]; then in=$1; set --; fi
  if [[ $refmodes == *:file:* ]]; then
    rm -f "$tmp/o"
    # $flags is split into words on purpose.
    # shellcheck disable=SC2086
    "$p" $flags -o "$tmp/o" "$@" >"$o" 2>&1 <"$in"; st=$?
    { echo "==== -o file ===="; cat "$tmp/o" 2>/dev/null; } >>"$o"
  elif [[ $refmodes == *:stdout:* ]]; then
    # shellcheck disable=SC2086
    "$p" $flags "$@" >"$o" 2>/dev/null <"$in"; st=$?
  else
    # shellcheck disable=SC2086
    "$p" $flags "$@" >"$o" 2>&1 <"$in"; st=$?
  fi
  [ $st -eq 1 ] && echo "==== exit 1 ====" >>"$o"
  return $st
}

# compare LABEL: report ok or FAIL for $tmp/out (exit $status) against
# $out.
compare() {
  local label=$1
  if [ ! -e "$out" ]; then
    echo "FAIL - $label: no golden file (make golden)"; failed=$((failed + 1))
  elif [ $status -gt 1 ]; then
    echo "FAIL - $label ($flags): exit $status"; failed=$((failed + 1))
  elif ! cmp -s "$out" "$tmp/out"; then
    echo "FAIL - $label ($flags)"; diff "$out" "$tmp/out" | head -20 | sed 's/^/    /'
    failed=$((failed + 1))
  else
    echo "ok   - $label ($flags)"
  fi
}

shopt -s extglob
while read -r ref id pattern flags; do
  case $ref in ''|'#'*) continue ;; esac
  refmodes=:${ref#*:}: ; [[ $ref == *:* ]] || refmodes=::
  case ${ref%%:*} in
    ada) refprog=$ada ;;
    scheme) refprog=$scheme ;;
    *) echo "golden.sh: bad reference '$ref' in $cases" >&2; exit 2 ;;
  esac
  # $pattern is a glob on purpose.
  # shellcheck disable=SC2206
  fixtures=(test/data/$pattern.yaml)
  [ -e "${fixtures[0]}" ] || { echo "golden.sh: no fixture matches $pattern" >&2; exit 2; }
  if [[ $refmodes == *:all:* ]]; then
    groups=("${fixtures[*]}")
  else
    groups=("${fixtures[@]}")
  fi
  for g in "${groups[@]}"; do
    # shellcheck disable=SC2206
    files=($g)
    if [[ $refmodes == *:all:* ]]; then
      out=$golden/$id.out; label=$id
    else
      base=$(basename "${files[0]}" .yaml); out=$golden/$base.$id.out; label="$base $id"
    fi
    count=$((count + 1))
    if [ "$mode" = generate ]; then
      run "$refprog" "$out" "${files[@]}"; status=$?
      if [ $status -gt 1 ]; then
        echo "golden.sh: $refprog $flags ${files[*]} ($ref) exited $status" >&2; exit 2
      fi
    else
      run "$prog" "$tmp/out" "${files[@]}"; status=$?
      compare "$label"
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
