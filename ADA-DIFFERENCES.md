# How the Ada besm2_fmt differs from this port, and where it is defective

This lists every known way the Ada `besm2_fmt`
(`~/Repos/RPG/Tools/besm2_fmt`) behaves differently from this Oberon-2
port, and every known defect in either, whether or not the other
copies it. Each entry was confirmed by running both programs; the
"Found" column names the PLAN.md step with the details.

The Ada binary is this port's reference: its standard output is
matched byte for byte (see `test/golden.cases`). So everything below is
either a deliberate departure, recorded in PLAN.md, or a defect the port
copies to keep that match.

**Keep this up to date**: add an entry whenever a new difference or
defect is found (AGENTS.md, Conventions).

## 1. Defects the Ada version had, now fixed there too

The port was written to avoid these. The Ada version fixed them in
besm2_fmt `8308c10`, with alibfyaml `3053d06` (1.6, 1.7) and a change
to Arg_Parser (1.8, and the option messages) not yet committed there
(step 14). The two programs now behave the same way here, except for
the wording of some messages (section 3).

| # | Ada behaviour before `8308c10` | Both now | Found |
|---|---|---|---|
| 1.1 | **A bad option value was ignored, and the program carried on.** `-u xx`, `-U ab` or `-w 0` printed `Invalid value for option ...`, stopped parsing the command line there, then processed the files named before the bad option, or read standard input if there were none, and exited 0. (Already fixed in the Ada source by Arg_Parser `8528c2a`; the binary was older.) | Error message, exit 2, nothing processed. | Step 3 |
| 1.2 | **`-w` from 1 to 24 was accepted, then aborted the run.** The first three-column row has no room for its wrapped column: after writing the entity's name and underline, the program stopped with the misleading `besm2_fmt: invalid numeric option argument`, status 2, and later files were never processed. | `-w` must be 25 or more; a smaller value is rejected before anything is read, status 2. | Step 3 |
| 1.3 | **YAML of the wrong shape crashed the program.** An entity that isn't a mapping, `stats: 5`, `stats:` with no value (null), a list item that isn't a mapping or a scalar, `enhancements: Area`, a customizer of one item (`[Range]`), or an applies-to that is a sequence each ended the run with `raised ADA.ASSERTIONS.ASSERTION_ERROR : failed precondition from libfyaml-nodes.ads:NNN`, status 1, without naming the file. Later files were never processed. | Reported like any other bad data, with the node's path, in the same words (`besm2_fmt: error processing FILE: /0/stats: not a sequence`); the rest of that file is skipped and the run goes on, status 0. Now golden cases (`test/data/shape-*.yaml`). | Step 4; step 9 |
| 1.4 | **Names equal but for case sorted in an arbitrary order** (GNAT's `Generic_Sorting` isn't stable): `armour 1, Armour 2, ARMOUR 3, armour 4` came out as `ARMOUR 3, armour 1, Armour 2, armour 4`. | Document order, as `besm2-rst` (a stable insertion sort in both). `test/data/sort-ties.yaml`'s golden files now come from the Ada binary, and match what `besm2-rst` gave. | Step 5 |
| 1.5 | **`-o` to a path that couldn't be created died with an unhandled exception**: `raised ADA.IO_EXCEPTIONS.NAME_ERROR : PATH: No such file or directory`, status 1. | `besm2_fmt: can't create PATH: No such file or directory`, status 1. | Step 3 |
| 1.6 | **A missing or unreadable file was reported as a parse error**: libfyaml's own `[ERR]: failed to open nosuch.yaml`, then `besm2_fmt: error processing nosuch.yaml: document failed to parse`, with no reason given. | The OS reason (wording differs, 3.4). | Step 3 |
| 1.7 | **YAML errors on standard input named the wrong file**: `(string-in-memory):2:1: error: ...`. | Named for standard input: `(stdin)` in Ada, `<stdin>` here (3.2). | This document |
| 1.8 | **A negative `-w` or `-L` was taken for an option**: `-w -5` gave `Argument Required for option -w`. | `-5` is taken as the value and rejected as out of range. Status 2 in both. | Step 3 |
| 1.9 | **`-u=` took the next argument as its value.** (Already fixed in the Ada source by Arg_Parser `264a098`.) | `-u=` sets the underliner to `=`, as getopt would. | Step 3 |
| 1.10 | **A write error was an unhandled exception.** With output to a full device (`-o /dev/full`, or standard output redirected there) the run ended with `raised ADA.IO_EXCEPTIONS.DEVICE_ERROR : No space left on device`, status 1. | `besm2_fmt: error writing output: No space left on device`, status 1. Ada stops at the first failed write; the port reports it once the run is over. | Step 9 |
| 1.11 | **The GNUmakefile's `-unicode-minus` files had ASCII minus signs.** `make rst` built `build/*-unicode-minus.gen.rst` and `*-tbl-unicode-minus.gen.rst` with `-n`, a name and comment carried over from `besm2-rst`, where `-n` turns the Unicode minus on; in the Ada version it turns it off. | Called `*-ascii-minus.gen.rst` and `*-tbl-ascii-minus.gen.rst`, built with `-n`. | Step 10 |

## 2. Defects in the Ada version that the port copies

Kept so that the port's output matches the Ada binary. Each departs
from `besm2-rst.scm`, whose behaviour is arguably the right one.

| # | Ada behaviour | `besm2-rst` behaviour | Found |
|---|---|---|---|
| 2.1 | **Case-insensitive sorting folds bytes, not characters.** `Ada.Characters.Handling.To_Lower` lowers `A`..`Z` and Latin-1 bytes `C0`..`DE` (except `D7`). In UTF-8 those are lead bytes, so non-ASCII letters aren't lowered at all, and names starting with some of them move: `élan vital` sorts after `“Quoted” Power`. The result is neither ASCII-only nor Unicode folding. | Folds by Unicode character: `élan vital` sorts before `“Quoted” Power`. | Steps 2, 6 (all formats; seen in h-m-m and raw ms in steps 7, 8); PLAN.md open question |
| 2.2 | **Header underlines are as long as the name in bytes**, so a name with non-ASCII characters gets a longer underline than it needs (21 characters for the 16 of `Rana “Frog” Élan`). Harmless in reST. | As long as the name in characters. | Step 6 (grid, terse); step 8 (raw ms) |

## 3. Deliberate differences between the Ada version and the port

Neither is wrong; the port chose differently, and golden tests don't
compare these.

| # | Ada | Port | Why |
|---|---|---|---|
| 3.1 | Errors from the YAML library: `besm2_fmt: error processing FILE: MESSAGE`, where MESSAGE may itself name the file | `besm2_fmt: ` then olibfyaml's gcc-style message, `FILE:LINE:COLUMN: error: TEXT` | The file was named twice. Errors the port finds itself keep the Ada wording. |
| 3.2 | Standard input is called `(stdin)` in messages | `<stdin>` | olibfyaml's name, as gcc's. |
| 3.3 | Usage text and command-line error messages in Ada arg_parser's words (`Invalid value for option -w: "24" is not in range 25..2147483647`), usage not repeated after an error | ArgParser's (`Error: Value out of range for option -w, --width.`, then the usage) | Different library. Same exit statuses. |
| 3.4 | A file that can't be opened: `besm2_fmt: nosuch.yaml: No such file or directory` | `besm2_fmt: nosuch.yaml: error: No such file or directory` | As 3.1. |
| 3.5 | Bad data found by the YAML library (a missing key, a bad integer) is reported without a path or position: `error processing FILE: missing required key "points"` | With both: `FILE: error: /1/stats/0: missing required key "points"` | As 3.1; the shape errors the programs find themselves (1.3) read the same in both. |

## 4. Where the Ada version departs from `besm2-rst`, and the port follows Ada

Not defects: the Ada version's own choices or fixes. Listed so they
aren't mistaken for port bugs when comparing with `besm2-rst`.

| # | Ada (and port) | `besm2-rst` | Found |
|---|---|---|---|
| 4.1 | Unicode MINUS SIGN (U+2212) by default; `-n`/`--no-unicode-minus` gives ASCII | ASCII by default; `-n` gives U+2212 | The Ada port's own choice (its PLAN.md) |
| 4.2 | `effective: ""` adds nothing to the level | Writes `1 ()` | Step 6 (grid, terse); steps 7, 8 (h-m-m, raw ms) |
| 4.3 | Level and `(effective)` joined by an ordinary space | Joined by a no-break space (`C2 A0`) | Step 6 (grid, terse); steps 7, 8 (h-m-m, raw ms) |
| 4.4 | Reads every document of a multi-document file | Loses documents (a `besm2-rst.scm` bug) | Steps 6, 7; the Ada PLAN.md |
| 4.5 | `mecha: false` turns mecha off; `level` is required for attributes; h-m-m skills emphasize only name and level | Same now: these were `besm2-rst.scm` bugs, fixed upstream (besm-tools `8da3e95`, `6139f21`, `b04abb5`) and ported to Ada | The Ada PLAN.md |

## 5. Quirks kept on purpose

Faithful to `besm2-rst.scm` in the Ada version and the port, so not
differences, but they look like bugs:

- `-d`/`--debug` is accepted and does nothing.
- `-R`/`--hmm-root`'s line goes to standard output even under `-o`.
- `--help` exits 1, not 0.
- `-p`/`--page` affects only the terse format.
- In terse and h-m-m, the Statistics subtotal is followed by a space
  that the other subtotals don't have; defect details are followed by
  two spaces, attribute details by one.
- In grid and raw ms, the skill points total is always shown, the
  other subtotals only under `-s`; in raw ms, the grand total is shown
  only when positive, so an entity whose defects outweigh the rest has
  no TOTAL row.
- In raw ms, each line between sections is the three-blank indent
  alone (trailing blanks), and there is no blank line between one
  entity's `.TE` and the next entity's name. (Step 8.)
- A limiter with a negative counts-as value is written `+-1`.
- An error in an entity ends the rest of its file, not just that
  entity, and the run's exit status is still 0.

## 6. Defects in the port that the Ada version doesn't have

| # | Port behaviour | Ada behaviour | Found |
|---|---|---|---|
| 6.1 | **A directory given as a file is silently taken for an empty file**: nothing is written, no error, status 0. olibfyaml's `Fyaml.Unreadable` only checks that the path opens for reading, which a directory does, and libfyaml then finds no documents in it. Not fixed yet: the fix belongs in olibfyaml. | `besm2_fmt: test: Is a directory`, and the run goes on (alibfyaml `3053d06`). | Step 14 |
