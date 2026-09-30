#!/usr/bin/env bash
# tools/perfdata.sh -- measure this repo's besm2_fmt and write the
# results as tab-separated data, for tools/perfcompare.sh in obesm2_fmt2
# to compare with another build (make perfdata; make perfcompare there).
#
# THIS FILE IS SHARED: an identical copy lives in obesm2_fmt and in
# obesm2_fmt2, so both programs are measured the same way.  Change
# both, and bump FORMAT_VERSION if the data format changes;
# perfcompare.sh refuses data files whose versions differ.
#
# Run from the repo root.  Inputs are made in $PERF_DIR from two
# fixtures both repos have (checked by checksum in the data), each on
# its own ("small") and repeated $PERF_COPIES times, as one YAML
# document ("doc") and as that many documents ("docs"), and every input
# is run in the four formats.  For each, the program is run once
# unmeasured (a warm-up, and the checksum of its output, so the
# comparison can confirm both programs wrote the same thing), then
# $PERF_RUNS_SMALL or $PERF_RUNS_BIG times under perf stat, pinned to
# CPU $PERF_CPU, then once under GNU time for its peak memory.
#
# Metrics, each as median, minimum and maximum over the runs:
#   instructions   user-mode instructions retired (perf): barely moves
#                  between runs (about 0.03%), so it compares two
#                  programs measured minutes apart, or on a busy machine
#   cpu_ms         the program's CPU time, user and system (task-clock)
#   wall_ms        elapsed time (duration_time)
# plus maxrss_kb, from one run.  Without a usable perf, instructions is
# NA and the times come from GNU time, at 10 ms resolution.
#
# Environment (all optional):
#   BESM2_FMT        the program to measure       (default ./besm2_fmt)
#   PERF_LABEL       its name in the report       (default: the repo's directory name)
#   PERF_OUT         where the data goes          (default build/perfdata.tsv)
#   PERF_DIR         where the inputs are made    (default build/perf)
#   PERF_COPIES      copies in the big inputs     (default 2000)
#   PERF_RUNS_SMALL  measured runs, small inputs  (default 31)
#   PERF_RUNS_BIG    measured runs, big inputs    (default 7)
#   PERF_CPU         CPU to pin to with taskset, or empty for none
#                    (default 2: a performance core on the i9-13900HX
#                    this was written on; E-cores are much slower)

set -euo pipefail

FORMAT_VERSION=1
prog=${BESM2_FMT:-./besm2_fmt}
label=${PERF_LABEL:-$(basename "$PWD")}
out=${PERF_OUT:-build/perfdata.tsv}
dir=${PERF_DIR:-build/perf}
copies=${PERF_COPIES:-2000}
runs_small=${PERF_RUNS_SMALL:-31}
runs_big=${PERF_RUNS_BIG:-7}
cpu=${PERF_CPU-2}
sources=(test/data/enyon-boase-2e.yaml test/data/synthetic-2e.yaml)
formats=("grid:" "terse:-t" "hmm:-H" "rawms:-m")

log() { echo "perfdata: $*" >&2; }
die() { log "$*"; exit 2; }

[ -x "$prog" ] || die "not executable: $prog (make first)"
/usr/bin/time -f '%M' true 2>/dev/null || die "GNU time (/usr/bin/time -f) not found"
pin=()
if [ -n "$cpu" ]; then
  command -v taskset >/dev/null || die "taskset not found (set PERF_CPU= to not pin)"
  pin=(taskset -c "$cpu")
fi
use_perf=no
if command -v perf >/dev/null \
   && "${pin[@]}" perf stat -x, -e instructions:u -e task-clock -e duration_time true 2>&1 >/dev/null \
      | grep -q 'instructions'; then
  use_perf=yes
else
  log "perf stat isn't usable here: no instruction counts, and times from GNU time"
fi

mkdir -p "$dir" "$(dirname "$out")"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# The inputs.  A fixture's body is everything after its first "---"
# line (the whole file if it has none): a top-level sequence, so copies
# of it concatenate into one longer sequence.
body() { awk 'seen { print; next } /^---$/ { seen = 1; next } END { }' "$1" >"$tmp/body"
         [ -s "$tmp/body" ] || cp "$1" "$tmp/body"; }
cases=()
for src in "${sources[@]}"; do
  [ -r "$src" ] || die "missing fixture: $src"
  name=$(basename "$src" -2e.yaml)
  cases+=("small-$name:$src")
  body "$src"
  f=$dir/$name-doc-$copies.yaml
  { echo ---; for ((i = 0; i < copies; i++)); do cat "$tmp/body"; done; } >"$f"
  cases+=("doc-$name:$f")
  f=$dir/$name-docs-$copies.yaml
  for ((i = 0; i < copies; i++)); do echo ---; cat "$tmp/body"; done >"$f"
  cases+=("docs-$name:$f")
done

# stats: median, minimum and maximum of the numbers on standard input.
stats() { sort -g | awk '{ v[NR] = $1 } END {
  if (NR == 0 || v[1] == "NA") { print "NA\tNA\tNA"; exit }
  m = (NR % 2) ? v[(NR + 1) / 2] : (v[NR / 2] + v[NR / 2 + 1]) / 2
  printf "%.10g\t%.10g\t%.10g\n", m, v[1], v[NR] }'; }

# measure FLAGS INPUT: one run; appends "INSTRUCTIONS CPU_MS WALL_MS"
# to $tmp/runs.
measure() {
  local flags=$1 input=$2
  if [ $use_perf = yes ]; then
    # $flags is split into words on purpose.
    # shellcheck disable=SC2086
    "${pin[@]}" perf stat -x, -o "$tmp/perf" -e instructions:u -e task-clock -e duration_time \
      "$prog" $flags "$input" >/dev/null 2>&1 || true
    # A hybrid CPU reports cpu_core/ and cpu_atom/ instructions; one is
    # "<not counted>".  Sum what was counted.
    awk -F, '$3 ~ /instructions/ && $1 ~ /^[0-9]/ { i += $1 }
             $3 ~ /task-clock/ { c = $1 }
             $3 ~ /duration_time/ { w = $1 / 1e6 }
             END { printf "%d %.6f %.6f\n", i, c, w }' "$tmp/perf" >>"$tmp/runs"
  else
    # shellcheck disable=SC2086
    "${pin[@]}" /usr/bin/time -f '%e %U %S' -o "$tmp/time" "$prog" $flags "$input" >/dev/null 2>&1 || true
    awk '{ printf "NA %.6f %.6f\n", ($2 + $3) * 1000, $1 * 1000 }' "$tmp/time" >>"$tmp/runs"
  fi
}

{
  printf '# version\t%s\n' "$FORMAT_VERSION"
  printf '# label\t%s\n' "$label"
  printf '# program\t%s\n' "$(realpath "$prog")"
  printf '# program_sha256\t%s\n' "$(sha256sum <"$prog" | cut -d' ' -f1)"
  printf '# commit\t%s%s\n' "$(git rev-parse --short HEAD 2>/dev/null || echo unknown)" \
    "$(git diff --quiet HEAD -- src 2>/dev/null || echo ' (src modified)')"
  printf '# date\t%s\n' "$(date -u '+%Y-%m-%d %H:%M UTC')"
  printf '# cpu\t%s\n' "$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//')"
  printf '# pinned_cpu\t%s\n' "${cpu:-none}"
  printf '# perf\t%s\n' "$use_perf"
  printf '# copies\t%s\n' "$copies"
  printf 'case\tformat\tinput_sha256\tinput_bytes\truns\toutput_sha256\tinstr_median\tinstr_min\tinstr_max\tcpu_ms_median\tcpu_ms_min\tcpu_ms_max\twall_ms_median\twall_ms_min\twall_ms_max\tmaxrss_kb\n'
} >"$tmp/data"

for c in "${cases[@]}"; do
  case_name=${c%%:*} input=${c#*:}
  if [[ $case_name == small-* ]]; then runs=$runs_small; else runs=$runs_big; fi
  in_sha=$(sha256sum <"$input" | cut -d' ' -f1)
  in_bytes=$(wc -c <"$input")
  for m in "${formats[@]}"; do
    fmt=${m%%:*} flags=${m#*:}
    log "$case_name $fmt ($runs runs)"
    # shellcheck disable=SC2086
    out_sha=$("$prog" $flags "$input" 2>&1 | sha256sum | cut -d' ' -f1)
    : >"$tmp/runs"
    for ((r = 0; r < runs; r++)); do measure "$flags" "$input"; done
    instr=$(awk '{ print $1 }' "$tmp/runs" | stats)
    cpums=$(awk '{ print $2 }' "$tmp/runs" | stats)
    wallms=$(awk '{ print $3 }' "$tmp/runs" | stats)
    # shellcheck disable=SC2086
    /usr/bin/time -f '%M' -o "$tmp/rss" "$prog" $flags "$input" >/dev/null 2>&1 || true
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$case_name" "$fmt" "$in_sha" "$in_bytes" \
      "$runs" "$out_sha" "$instr" "$cpums" "$wallms" "$(tail -n 1 "$tmp/rss")" >>"$tmp/data"
  done
done

mv "$tmp/data" "$out"
log "wrote $out"
