# Performance: the Oberon-2 port vs the Ada besm2_fmt

- Date: 2026-09-30
- CPU: 13th Gen Intel(R) Core(TM) i9-13900HX
- Port: `./besm2_fmt`; Ada: `/home/tkb/Repos/RPG/Tools/besm2_fmt/besm2_fmt`
- `BENCH_N`=200, `BENCH_ENTITIES`=2000, `BENCH_SOURCE`=`test/data/enyon-boase-2e.yaml`
- The two programs' outputs were checked to be identical on every
  input and format first.

## Per-invocation time (200 runs of `enyon-boase-2e.yaml`)

| Format | Ada (ms) | Port (ms) | Port / Ada |
|---|---|---|---|
| grid | 2.14 | 3.35 | 1.57 |
| terse | 1.98 | 1.83 | 0.92 |
| h-m-m | 1.69 | 1.89 | 1.12 |
| raw ms | 2.04 | 1.96 | 0.96 |

## Throughput: 2000 entities in one document

| Format | Ada (s) | Port (s) | Port / Ada | Ada max RSS (KB) | Port max RSS (KB) |
|---|---|---|---|---|---|
| grid | 0.32 | 0.81 | 2.53 | 135532 | 135376 |
| terse | 0.19 | 0.69 | 3.63 | 135748 | 134912 |
| h-m-m | 0.19 | 0.49 | 2.58 | 135684 | 135392 |
| raw ms | 0.20 | 0.54 | 2.70 | 136252 | 134616 |

## Throughput: 2000 documents of one entity each

| Format | Ada (s) | Port (s) | Port / Ada | Ada max RSS (KB) | Port max RSS (KB) |
|---|---|---|---|---|---|
| grid | 0.30 | 0.82 | 2.73 | 5884 | 5576 |
| terse | 0.17 | 0.65 | 3.82 | 5912 | 5384 |
| h-m-m | 0.18 | 0.35 | 1.94 | 5896 | 5024 |
| raw ms | 0.17 | 0.61 | 3.59 | 5636 | 5248 |
