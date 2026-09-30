#!/usr/bin/env bash
# Checks that no object in DIR (default obj) uses the callee-saved
# registers rbx, r12, r13, r14 or r15, which the GNUmakefile's CFLAGS
# forbid: voc's garbage collector can't see a pointer kept only in one
# of them (GNUmakefile, CFLAGS; PLAN.md, step 11).  Prints ok/FAIL per
# object and exits 1 if any uses them.

dir=${1:-obj}
failed=0
regs='%(rbx|ebx|bx|bl|r1[2-5][dwb]?)\b'
for o in "$dir"/*.o; do
  uses=$(objdump -d --no-show-raw-insn "$o" | grep -E -- "$regs")
  if [ -n "$uses" ]; then
    echo "FAIL - $(basename "$o") uses a callee-saved register (rebuild with the GNUmakefile's CFLAGS)"
    echo "$uses" | head -5 | sed 's/^/    /'; failed=$((failed + 1))
  else
    echo "ok   - $(basename "$o")"
  fi
done
if [ "$failed" -eq 0 ]; then echo "All checks passed."; else echo "$failed check(s) failed."; exit 1; fi
