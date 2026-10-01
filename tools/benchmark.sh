#!/usr/bin/env bash
# tools/benchmark.sh -- time this port of besm2_fmt against the Ada
# besm2_fmt (PLAN.md, step 11), with the inputs of the Ada repo's
# tools/benchmark.sh: one small file run many times (per-invocation
# overhead), and one entity repeated BENCH_ENTITIES times, as one YAML
# document and as that many documents (throughput).
#
# Run from the repo root (make benchmark).  Progress goes to standard
# error, a Markdown report to standard output.  Before timing, each
# input's output from the two programs is compared, and the run stops
# if they differ.
#
# Environment (all optional):
#   BESM2_FMT       this program             (default ./obesm2_fmt)
#   ADA_BESM2_FMT   the Ada program          (default ~/Repos/RPG/Tools/besm2_fmt/besm2_fmt)
#   BENCH_N         runs for the per-invocation mean   (default 200)
#   BENCH_ENTITIES  entities in the throughput inputs  (default 2000)
#   BENCH_SOURCE    the one-entity input, starting with "---"
#                   (default test/data/enyon-boase-2e.yaml)
#
# Needs GNU time (/usr/bin/time -f) and GNU date (+%s%N).

set -euo pipefail

port=${BESM2_FMT:-./obesm2_fmt}
ada=${ADA_BESM2_FMT:-$HOME/Repos/RPG/Tools/besm2_fmt/besm2_fmt}
n=${BENCH_N:-200}
entities=${BENCH_ENTITIES:-2000}
source=${BENCH_SOURCE:-test/data/enyon-boase-2e.yaml}
dir=build
modes=("grid:" "terse:-t" "h-m-m:-H" "raw ms:-m")

log() { echo "benchmark: $*" >&2; }
die() { log "$*"; exit 2; }

[ -x "$port" ] || die "not executable: $port (make first)"
[ -x "$ada" ] || die "not executable: $ada"
[ "$(head -n 1 "$source")" = "---" ] || die "$source must start with ---"
/usr/bin/time -f '%e %M' true 2>/dev/null || die "GNU time (/usr/bin/time -f) not found"

mkdir -p "$dir"
entity_file=$dir/bench-entities-$entities.yaml
docs_file=$dir/bench-docs-$entities.yaml
log "writing $entity_file and $docs_file"
{ echo ---; for ((i = 0; i < entities; i++)); do tail -n +2 "$source"; done; } >"$entity_file"
for ((i = 0; i < entities; i++)); do cat "$source"; done >"$docs_file"

# Identical output first: a benchmark of programs that disagree means
# nothing.
for m in "${modes[@]}"; do
  flags=${m#*:}
  for f in "$source" "$entity_file" "$docs_file"; do
    # $flags is split into words on purpose.
    # shellcheck disable=SC2086
    cmp -s <("$ada" $flags "$f" 2>&1) <("$port" $flags "$f" 2>&1) \
      || die "outputs differ: $flags $f"
  done
done
log "outputs identical"

# mean_ms PROG FLAGS: mean wall time of BENCH_N runs on $source, in ms.
mean_ms() {
  local prog=$1 flags=$2 start end i
  start=$(date +%s%N)
  for ((i = 0; i < n; i++)); do
    # shellcheck disable=SC2086
    "$prog" $flags "$source" >/dev/null
  done
  end=$(date +%s%N)
  awk -v s="$start" -v e="$end" -v n="$n" 'BEGIN { printf "%.2f", (e - s) / n / 1e6 }'
}

# once PROG FLAGS FILE: "SECONDS MAXRSS_KB" for one run.
once() {
  local prog=$1 flags=$2 file=$3 t
  t=$(mktemp)
  # shellcheck disable=SC2086
  /usr/bin/time -f '%e %M' -o "$t" "$prog" $flags "$file" >/dev/null
  cat "$t"; rm -f "$t"
}

ratio() { awk -v a="$1" -v b="$2" 'BEGIN { if (b > 0) printf "%.2f", a / b; else print "-" }'; }

echo "# Performance: the Oberon-2 port vs the Ada besm2_fmt"
echo
echo "- Date: $(date -u +%Y-%m-%d)"
echo "- CPU: $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//')"
echo "- Port: \`$port\`; Ada: \`$ada\`"
echo "- \`BENCH_N\`=$n, \`BENCH_ENTITIES\`=$entities, \`BENCH_SOURCE\`=\`$source\`"
echo "- The two programs' outputs were checked to be identical on every"
echo "  input and format first."
echo
echo "## Per-invocation time ($n runs of \`$(basename "$source")\`)"
echo
echo "| Format | Ada (ms) | Port (ms) | Port / Ada |"
echo "|---|---|---|---|"
for m in "${modes[@]}"; do
  name=${m%%:*} flags=${m#*:}
  log "per-invocation: $name"
  a=$(mean_ms "$ada" "$flags"); p=$(mean_ms "$port" "$flags")
  echo "| $name | $a | $p | $(ratio "$p" "$a") |"
done

for f in "$entity_file" "$docs_file"; do
  echo
  if [ "$f" = "$entity_file" ]; then
    echo "## Throughput: $entities entities in one document"
  else
    echo "## Throughput: $entities documents of one entity each"
  fi
  echo
  echo "| Format | Ada (s) | Port (s) | Port / Ada | Ada max RSS (KB) | Port max RSS (KB) |"
  echo "|---|---|---|---|---|---|"
  for m in "${modes[@]}"; do
    name=${m%%:*} flags=${m#*:}
    log "throughput: $name, $(basename "$f")"
    read -r as ar < <(once "$ada" "$flags" "$f")
    read -r ps pr < <(once "$port" "$flags" "$f")
    echo "| $name | $as | $ps | $(ratio "$ps" "$as") | $ar | $pr |"
  done
done
