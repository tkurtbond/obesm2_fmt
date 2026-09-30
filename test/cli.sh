#!/usr/bin/env bash
# Command-line handling of besm2_fmt: exit statuses, and a line of the
# output or error each case must contain.  Run from the repo root by
# `make test`, as test/cli.sh [program]; prints ok/FAIL per case, as the
# unit tests do, and exits 1 if any failed.
#
# Statuses follow the Ada version (help 1, command-line mistakes 2, bad
# input files 0), except where PLAN.md, step 3, records a deliberate
# difference: -u/-U with more than one character and -w below 25 exit 2
# here.

prog=${1:-./besm2_fmt}
data=test/data
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failed=0

# check LABEL STATUS PATTERN [ARGS...]: run prog ARGS with stdin from
# /dev/null, stdout and stderr together; require exit STATUS and a line
# matching the grep -E PATTERN (skipped if PATTERN is empty).
check() {
  local label=$1 want=$2 pattern=$3; shift 3
  "$prog" "$@" </dev/null >"$tmp/out" 2>&1
  local got=$?
  if [ "$got" -ne "$want" ]; then
    echo "FAIL - $label: exit $got, not $want"; sed 's/^/    /' "$tmp/out"; failed=$((failed + 1))
  elif [ -n "$pattern" ] && ! grep -qE -- "$pattern" "$tmp/out"; then
    echo "FAIL - $label: no line matching /$pattern/"; sed 's/^/    /' "$tmp/out"; failed=$((failed + 1))
  else
    echo "ok   - $label"
  fi
}

f=$data/enyon-boase-2e.yaml

check "-h shows the usage and exits 1" 1 '^  -w <arg>, --width <arg>$' -h
check "--help after a file still exits 1" 1 '^besm2_fmt \[options\] \[files\.\.\.\]$' "$f" --help
check "an unknown long option exits 2" 2 '^Error: Unknown option --bogus$' --bogus "$f"
check "an unknown short option exits 2" 2 '^Error: Unknown option -x$' -x "$f"
check "a missing option argument exits 2" 2 '^Error: Argument required for option -u, --underliner$' -u
check "-u with two characters exits 2" 2 'underliner takes exactly one character, got "xx"' -u xx "$f"
check "-U with two characters exits 2" 2 'subunderliner takes exactly one character, got "ab"' -U ab "$f"
check "-u with an empty argument exits 2" 2 'got ""$' -u "" "$f"
check "-u= sets the underliner to =" 0 '' -u= "$f"
check "-w that isn't a number exits 2" 2 'Invalid integer value for option -w, --width: abc' -w abc "$f"
check "-w 24 is too narrow and exits 2" 2 'Value out of range for option -w, --width' -w 24 "$f"
check "-w 25 is accepted" 0 '' -w 25 "$f"
check "-w=72 is accepted" 0 '' --width=72 "$f"
check "-L -1 exits 2" 2 'Value out of range for option -L, --hmm-depth' -L -1 "$f"
check "-L that isn't a number exits 2" 2 'Invalid integer value for option -L' -L x "$f"
check "-o to a directory that doesn't exist exits 1 with the OS reason" 1 \
  '^besm2_fmt: can.t create /nonexistent/dir/out: No such file or directory$' -o /nonexistent/dir/out "$f"
check "a missing file is reported and the run goes on, exit 0" 0 \
  '^besm2_fmt: nosuch\.yaml: error: No such file or directory$' "$f" nosuch.yaml "$f"
check "-- ends the options" 0 '^besm2_fmt: -t: error: No such file or directory$' -- -t

# A bad entity is reported, writes nothing, and ends its file; entities
# before it are written, and the run goes on with the next file.  Its
# number counts on across the documents of a file.
printf -- '- name: Good\n- name: Bad\n  stats: [{name: B}]\n- name: Never\n' >"$tmp/bad.yaml"
"$prog" "$tmp/bad.yaml" "$data/composite-multi-doc-2e.yaml" >"$tmp/out" 2>&1
status=$?
if [ $status -eq 0 ] && grep -q 'Good' "$tmp/out" && ! grep -q 'Bad\|Never' "$tmp/out" \
   && grep -q 'bad.yaml: error: /1/stats/0: missing required key "value"' "$tmp/out" \
   && grep -q 'Coleopteran' "$tmp/out"; then
  echo "ok   - a bad entity ends its file, not the run, with status 0"
else
  echo "FAIL - a bad entity ends its file, not the run, with status 0"; sed 's/^/    /' "$tmp/out"; failed=$((failed + 1))
fi
printf -- '- 5\n' >"$tmp/shape.yaml"
check "YAML of the wrong shape is an input error, not a halt" 0 \
  'error processing .*shape\.yaml: /0: not a mapping$' "$tmp/shape.yaml"
check "a customizer of one item is an input error, not a halt" 0 \
  'error processing .*shape-customizer-short\.yaml: /1/attributes/0/enhancements/0: customizer sequence too short$' \
  "$data/shape-customizer-short.yaml"
check "stats: with no value is an input error, not a halt" 0 \
  'error processing .*shape-null-stats\.yaml: /1/stats: not a sequence$' "$data/shape-null-stats.yaml"
check "YAML that doesn't parse is reported gcc style" 0 \
  '^besm2_fmt: .*bad-yaml\.yaml:6:1: error: missing comma in flow mapping$' "$data/bad-yaml.yaml"
check "a bad integer is reported with its position and path" 0 \
  '^besm2_fmt: .*bad-int\.yaml:5:42: error: /1/stats/0/points: not a valid integer: "lots"$' "$data/bad-int.yaml"
check "a missing key is reported with its path" 0 \
  '^besm2_fmt: .*bad-missing-key\.yaml: error: /1/stats/0: missing required key "points"$' "$data/bad-missing-key.yaml"
check "a bad customizer is reported in the Ada wording, with its path" 0 \
  'error processing .*bad-customizer-map\.yaml: /1/attributes/0/limiters/0: do not understand customizer$' \
  "$data/bad-customizer-map.yaml"
check "a file with no documents is not an error" 0 '' "$data/edge-empty.yaml"
check "an empty document is an error" 0 \
  'expected a top-level YAML sequence of entities in .*bad-empty-doc\.yaml$' "$data/bad-empty-doc.yaml"
check "-o to /dev/full exits 1 with the OS reason" 1 \
  '^besm2_fmt: error writing output: No space left on device$' -o /dev/full "$f"
"$prog" "$f" >/dev/full 2>"$tmp/err"
if [ $? -eq 1 ] && grep -q '^besm2_fmt: error writing output: No space left on device$' "$tmp/err"; then
  echo "ok   - a full standard output exits 1 with the OS reason"
else
  echo "FAIL - a full standard output exits 1 with the OS reason"; sed 's/^/    /' "$tmp/err"; failed=$((failed + 1))
fi
"$prog" <"$data/bad-int.yaml" >/dev/null 2>"$tmp/err"
if grep -q '^besm2_fmt: <stdin>:5:42: error: /1/stats/0/points: not a valid integer: "lots"$' "$tmp/err"; then
  echo "ok   - errors in standard input name it <stdin>"
else
  echo "FAIL - errors in standard input name it <stdin>"; sed 's/^/    /' "$tmp/err"; failed=$((failed + 1))
fi
printf -- 'a: 1\n' >"$tmp/map.yaml"
check "a top level that isn't a sequence is reported" 0 \
  'expected a top-level YAML sequence of entities in .*map\.yaml$' "$tmp/map.yaml"

# -R/--hmm-root goes to standard output even under -o, as in the Ada
# version and besm2-rst.scm; everything else goes to the file.
"$prog" -H -R Root -L 2 -o "$tmp/file" "$f" >"$tmp/stdout" 2>&1
if [ "$(cat "$tmp/stdout")" = "$(printf '\t\tRoot')" ] && [ -s "$tmp/file" ] \
   && ! grep -q Root "$tmp/file"; then
  echo "ok   - -R goes to standard output under -o, the rest to the file"
else
  echo "FAIL - -R goes to standard output under -o, the rest to the file"; failed=$((failed + 1))
fi

# With no file names, standard input is read.
if "$prog" <"$f" | cmp -s - <("$prog" "$f" | sed "s|$f|<stdin>|"); then
  echo "ok   - no file names reads standard input"
else
  echo "FAIL - no file names reads standard input"; failed=$((failed + 1))
fi

# Enough entities for many garbage collections: each copy of an entity
# must come out the same as the first.  Before the GNUmakefile's CFLAGS,
# the collector freed strings kept only in registers, and about 1 grid
# header in 400 came out as garbage (PLAN.md, step 11).
n=1000
{ echo ---; for ((i = 0; i < n; i++)); do tail -n +2 "$f"; done; } >"$tmp/many.yaml"
for flags in "" "-t" "-H" "-m" "-s -1"; do
  # $flags is split into words on purpose.
  # shellcheck disable=SC2086
  "$prog" $flags "$f" >"$tmp/one"
  for ((i = 0; i < n; i++)); do cat "$tmp/one"; done >"$tmp/expected"
  # shellcheck disable=SC2086
  if "$prog" $flags "$tmp/many.yaml" 2>&1 | cmp -s - "$tmp/expected"; then
    echo "ok   - $n entities come out as $n copies of one ($flags)"
  else
    echo "FAIL - $n entities come out as $n copies of one ($flags)"; failed=$((failed + 1))
  fi
done

if [ "$failed" -eq 0 ]; then echo "All checks passed."; else echo "$failed check(s) failed."; exit 1; fi
