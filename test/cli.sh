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

if [ "$failed" -eq 0 ]; then echo "All checks passed."; else echo "$failed check(s) failed."; exit 1; fi
