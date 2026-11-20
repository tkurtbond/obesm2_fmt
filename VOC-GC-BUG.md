# voc's collector and the callee-saved registers

Found in step 11 of `PLAN.md` (the valgrind pass and benchmark), where
the full account is. This file is the summary that `obesm2_fmt2` and
`pobesm2_fmt2` point to. Upstream, it is vishap-bugs 14
(`~/Repos/Oberon/vishap-bugs/issues/14-gc-callee-saved-registers.md`).

## What went wrong

On 2000-entity inputs, about 1 grid or raw ms table header in 400 came
out as garbage. It was always the last cell of a call such as
`Row3(H("LEVEL"), H("POINTS"), H("ATTRIBUTE"))`. valgrind saw nothing
wrong, because the freed memory was still in voc's own heap chunk.

## Why

- voc compiles its C without optimization. gcc evaluates the arguments
  right to left, and keeps each one it has finished only in a
  callee-saved register (`r12`, `rbx`) while the next `H` allocates.
- voc's collector finds pointers only on the stack. Its "register
  pressure" loop, meant to push the callee-saved registers there, does
  nothing at `-O0`, and nothing else on the allocation path saves them.
- So when that allocation starts a collection, the string held only in
  a register is freed while it is still in use.

## The workaround here

- The `GNUmakefile` builds every module with `CFLAGS=-ffixed-rbx
  -ffixed-r12 -ffixed-r13 -ffixed-r14 -ffixed-r15`. voc appends
  `$CFLAGS` to its cc command, so gcc never uses those registers.
  `obj/cflags` rebuilds every object when `CFLAGS` changes.
- The flags name x86-64's registers, so the `GNUmakefile` stops on any
  other machine.
- `test/regs.sh` (in `make test`) fails if any object uses those
  registers.
- `test/cli.sh` checks that 1000 copies of an entity come out as 1000
  copies of its output, in five flag sets. It fails on the old build
  for grid, raw ms and `-1`.
- Checked both ways on 2000- and 5000-entity inputs in six flag sets:
  before the fix, 12 of 24 runs differed from the Ada binary's output;
  after it, none did.

## What it doesn't cover

voc's runtime library itself (`libvoc-OC.so`) is built without these
flags, so the hazard remains inside it. This program calls it little.
Anything else built with voc may have the same bug.

The other cure is to have the collector store the callee-saved
registers on the stack before it scans. That is vishap-bugs 14's patch,
and what Peaseblossom's Stage 0 and opp link in
(`voc-heap-gc-spill.c`). poc's collector stores those registers
before it scans (`GarbageCollectedHeap.Collect`), so `pobesm2_fmt2`
needs neither.
