# besm2_fmt: porting the Ada program to Oberon-2

**Source being ported:** the Ada program `besm2_fmt`
(`~/Repos/RPG/Tools/besm2_fmt`, about 2,460 lines in `src/`), itself a
port of `besm2-rst.scm` from besm-tools. It reads a YAML file (or
standard input) holding a sequence of BESM 2E entities (characters,
templates, items), possibly across several `---`-separated documents,
and writes each entity in one of four formats: reST grid tables (the
default), terse (`-t`), h-m-m outline (`-H`), or raw ms/tbl (`-m`).

**Target:** an Oberon-2 program, compiled with voc under the `-OC`
size model, using `ArgParser` (`~/Repos/Oberon/ArgParser`) for the
command line and olibfyaml (`~/Repos/Oberon/olibfyaml`: `Fyaml`,
`FyamlStreams`) for YAML. The executable is still called `besm2_fmt`.

**Acceptance criterion:** for every test file and flag combination,
standard output is byte-for-byte identical to the Ada binary's, and
the exit status is the same. The Ada binary works and is the oracle;
its own PLAN.md records that it matches the real `besm2-rst` binary on
all four formats.

## 1. What doesn't carry over directly

The Ada design (decode each entity once into typed records, then four
independent format backends over them, plus a small `Text_Layout`
package for grid-table rows) is sound and is kept. What changes is
forced by the language and the libraries:

| Ada | Oberon-2 replacement |
|---|---|
| Exceptions (`Missing_Key`, `Data_Error`, `Program_Error`) raised in `Load_Entity`, caught per file in main | Loaders return `BOOLEAN` with a `VAR msg` out parameter; see §5 |
| `Ada.Containers.Vectors` of records | Dynamic arrays (`POINTER TO ARRAY OF ...`) grown by doubling, with a count; see §3 |
| `Generic_Sorting` with a case-insensitive `"<"` | One hand-written stable sort over items that extend a common named-item base type; see §3 |
| `Unbounded_String` | `Besm2Str`: `String = POINTER TO ARRAY OF CHAR` plus a growable `Buffer` for building text |
| `Integer'Image`, `Trim` | `Besm2Str.AppendInt`, `Besm2Str.Trim` (space, tab, LF, CR, as Ada's explicit `Whitespace` set) |
| `Ada.Text_IO.Set_Output` for `-o` | `Besm2Out`, an output sink over either `Out` or a `Files.Rider`; every backend writes through it |
| `Node.Iterate (Callback'Access)` with nested procedures | `Fyaml.ItemIter` loops (Oberon can't pass nested procedures as values) |
| `Node.Item (1)` (1-based) | `Node.Item(0)` (olibfyaml is 0-based) |
| `N.String_Value ("k")`, `N.Integer_Value ("k")`, `Boolean_Value (.., Default)` | `StringField`, `IntegerField`, `BooleanFieldOr`, each `BOOLEAN` + `VAR err` |
| `Arg_Parser.Make_Set_Boolean_True_Option (Variable => X'Access)` | ArgParser has no "set a variable" options: one small handler procedure per flag, setting a `Besm2Config` variable |
| `Make_Set_Natural_Option` / `Make_Set_Positive_Option` | `MakeIntOption` with a range; ArgParser itself reports a bad or out-of-range value and exits 2 |
| Package hierarchy `BESM2_Fmt.*` | Flat modules prefixed `Besm2` |

Two library gaps, both confirmed live:

- **voc's `Args` is only in the `-O2` library**, not `-OC`'s, and
  `ArgParser` imports it. A shim `rtl/Args.Mod` over `Modules`
  (identical to ArgParser's `poc-rtl/Args.Mod`: `argc-` and `Get`)
  fixes it: compiled with `-OC`, a test program using `ArgParser` with
  it parsed `-w 70 foo --width=5 bar` correctly and rejected `-w 0`
  with ArgParser's range error and exit status 2.
- **`Out` has no redirection**, hence `Besm2Out`.

## 2. Module layout

```
obesm2_fmt/
  rtl/Args.Mod          -- voc Args interface over Modules, for -OC (see §1)
  src/
    Besm2Str.Mod        -- String, Buffer, Append/AppendInt/Trim/Join/CompareCI/DisplayLength
    Besm2Config.Mod     -- CLI-settable globals          (Ada: besm2_fmt-config.ads)
    Besm2Out.Mod        -- output sink: stdout or a file (Ada: Text_IO.Set_Output)
    Besm2Layout.Mod     -- Pad, WordWrap, PutRow, SeparatorLine, EmptyRow,
                           Bold/Italics/Bolding/Italicizing/Emphasizing/Hbolding,
                           MinusGlyph                    (Ada: besm2_fmt-text_layout.*)
    Besm2Entities.Mod   -- Stat, Derived, Attribute, Defect, Skill, Entity;
                           Load; FormatCustomizers; MakeAttributeDetails
                                                         (Ada: besm2_fmt-entities.*)
    Besm2Grid.Mod       -- reST grid tables, the default (Ada: besm2_fmt-format_grid.*)
    Besm2Terse.Mod      -- terse                         (Ada: besm2_fmt-format_terse.*)
    Besm2Hmm.Mod        -- h-m-m outline                 (Ada: besm2_fmt-format_hmm.*)
    Besm2RawMs.Mod      -- raw ms / tbl                  (Ada: besm2_fmt-format_raw_ms.*)
    Besm2Cli.Mod        -- options, handlers, file list  (Ada: besm2_fmt-cli.*)
    Besm2Fmt.Mod        -- main module                   (Ada: besm2_fmt_main.adb)
  test/
    TestStr.Mod, TestLayout.Mod   -- unit tests (TestLayout ports test_text_layout.adb)
    Check.Mod                     -- ok/FAIL reporting, as olibfyaml's
    data/                         -- YAML fixtures: copies of the Ada test-data plus synthetic ones
    golden/                       -- expected output, generated from the Ada binary
    run-golden.sh                 -- runs the flag matrix and compares
  GNUmakefile
  AGENTS.md, PLAN.md, README.md
```

Compile order (each depends only on earlier ones): `Args`, `Err`,
`ArgParser`, `FyThin`, `Fyaml`, `FyamlStreams`, `Besm2Str`,
`Besm2Config`, `Besm2Out`, `Besm2Layout`, `Besm2Entities`, `Besm2Grid`,
`Besm2Terse`, `Besm2Hmm`, `Besm2RawMs`, `Besm2Cli`, then `Besm2Fmt -m`.

`Besm2Str` and `Besm2Layout` don't import `Fyaml`, so they can be
tested without YAML, like the Ada `Text_Layout`. `Besm2Str.String` is
its own type rather than an alias of `Fyaml.String`, for the same
reason; `Besm2Entities` copies scalars across. (A scalar with an
embedded 0X would be cut short there; no BESM file has one.)

Ropes (`OBERON_MODULES/Ropes.Mod`) was considered for strings and
rejected: every string here is short and built once, and a flat buffer
is simpler to pad, wrap and measure.

## 3. Data types (`Besm2Entities`)

Mirrors the Ada records field for field:

```oberon
TYPE
  String = Besm2Str.String;
  Strings = POINTER TO ARRAY OF String;       (* alternatives, specialisations, elements *)

  Named = POINTER TO NamedDesc;               (* base for sorting by name *)
  NamedDesc = RECORD name: String END;
  Attribute = POINTER TO AttributeDesc;
  AttributeDesc = RECORD (NamedDesc) level: String; points: INTEGER; details: String END;
  Defect   = ... (NamedDesc) points, details
  Skill    = ... (NamedDesc) level, points, specialisations: Strings; nspec: INTEGER
  Stat     = ... name, value, points           (document order, never sorted)
  Derived  = ... name, value, alternatives     (document order, never sorted)

  NamedList = RECORD items: POINTER TO ARRAY OF Named; n: INTEGER END;

  Entity = POINTER TO EntityDesc;
  EntityDesc = RECORD
    name, tagline, description, size: String;  (* NIL = absent; replaces Has_* flags *)
    mecha: BOOLEAN;
    stats, derived, attributes, defects, skills: ...;
    statsTotal, attributesTotal, defectsTotal, skillsTotal, entityTotal: INTEGER
  END;
```

NIL for an absent optional string replaces the Ada `Has_Name`/
`Has_Tagline`/... flags. An empty string still means "present but
empty", as `Has_Key` does in Ada.

Sorting: attributes, defects and skills are sorted case-insensitively
by name, and so are elements and the combined enhancement/limiter list
inside `MakeAttributeDetails`. One stable insertion sort over
`POINTER TO ARRAY OF Named` covers the first three (they extend
`NamedDesc`); a second over `Strings` covers the other two. Lists are
short, so insertion sort is fine.

Everything else in `Besm2Entities` ports line by line: `Trim` on
`details` and `tagline`; `level (effective)` joined at load time;
`FormatCustomizers` (scalar gives `name -1`/`name +1`; a sequence gives
`name ±N`, or `name: a, b ±N` with three or more items; anything else is
an error); `MakeAttributeDetails` joining sorted elements, sorted
customizers and details with `"; "`; `mecha` read with
`BooleanFieldOr("mecha", FALSE, ...)` (the besm-tools `8da3e95` fix, not
`HasKey`); `level` required for attributes (besm-tools `6139f21`);
`entityTotal = stats + attributes + defects` (skills excluded).

## 4. Output (`Besm2Out`, `Besm2Layout`, the four backends)

`Besm2Out` exports `String(s)`, `Str(s: String)`, `Char(c)`, `Ln`,
`Repeat(c, n)` (tabs for h-m-m are `Repeat(09X, n)`; numbers go through
`Besm2Str.Int`), plus `ToFile(path)` and `Close`, which return a
`Platform.ErrorCode`, and `Flush`. It buffers, and writes with
`Platform.Write` to standard output or, after `ToFile`, to a file made
by `Platform.New` (see step 2 for why not `Out` or `Files`). Only the
backends and main write output, and only through `Besm2Out`.

`Besm2Layout` is a direct port of `Text_Layout`:

- `DisplayLength` counts UTF-8 lead bytes (bytes outside
  `80X..0BFX`), as the Ada version does, so columns with `×`, `—` or
  curly quotes line up.
- `WordWrap(s, width)` breaks on space, LF, CR and tab (the Ada fix for
  `details: |` block scalars), never breaks a word longer than the
  width, and yields one empty line for an empty string. It returns a
  `Strings` array and count.
- `PutRow` takes 2 or 3 columns (Oberon has no aggregates: `Row2(a, b)`
  and `Row3(a, b, c)` in `Besm2Layout` directly, instead of Ada's
  vector-building wrappers in `Format_Grid`). `numWidth = 10`; the last
  column is `tableWidth - 2 - (cols - 1) * 11` wide.
- `MinusGlyph` is U+2212 by default and `-` under `-n`.

Things to port exactly as the Ada version does them, each confirmed
there against the real Scheme binary:

- Header underlines use the name's **byte** length (`Name'Length`), not
  its display length. Port with `Besm2Str.Length`, not `DisplayLength`.
- Grid: defect points always get `\` + minus glyph; the skills total
  row and the grand TOTAL row are unconditional; `derived` abbreviations
  (`ACV` to `Attack Combat Value`, ...) are expanded only in grid and
  raw-ms.
- Terse/h-m-m: `Label_Points` suffixes `CP`/`BP`/`MP`/`MBP`; the
  Statistics subtotal has a trailing space the others don't; defect
  details are followed by `".  "` (two spaces) but attribute details by
  `". "`.
- h-m-m: indentation starts from `-L` for every entity; `-S` puts items
  on separate lines; newlines in tagline, description and details become
  spaces; only name and level are emphasized in skills (besm-tools
  `b04abb5`).
- Raw ms: `paragraphSeen`/`firstSectionSeen` bookkeeping; `.T&` before
  every section but the first; the TOTAL row only when the total is
  positive; `-p` has no effect here (it is terse-only).

## 5. Errors

Ada behaviour to match:

| Case | Ada | Status |
|---|---|---|
| Bad YAML, missing key, malformed number, top level not a sequence, bad customizer | `besm2_fmt: error processing FILE: MESSAGE` on stderr, skip the rest of that file, continue with the next | 0 |
| Unknown option, missing option argument, bad `-u`/`-U` | diagnostic on stderr | 2 |
| Non-numeric or out-of-range `-w`/`-L` | diagnostic on stderr | 2 |
| `-h`/`--help` | usage on stdout | 1 |

In Oberon, `Besm2Entities.Load(node, entity, msg): BOOLEAN` and each
per-item loader return FALSE with a message on the first error; the
main module prints it and moves on to the next file. As in Ada, an
entity is fully loaded before any of it is written, so a failing entity
writes nothing, while entities before it in the same file are already
written.

The Ada and Oberon **messages will differ**, and that is accepted:
olibfyaml's `err.msg` is gcc-style (`file:line:column: error: missing
required key "points"`), better than the Ada text. The main module
prints `besm2_fmt: ` followed by it. For errors the port detects itself
(top level not a sequence, bad customizer), it uses the Ada wording.
The file name for standard input becomes olibfyaml's `<stdin>` rather
than Ada's `(stdin)`. The usage text also differs (ArgParser's format,
not Ada arg_parser's). Golden tests check exit status only for these.

`-u`/`-U` with other than one character: the handler writes the Ada
message to `Err`, flushes `Out`, and calls `Platform.Exit(2)`, since
ArgParser's own error exit isn't exported. `-h`: the handler calls
`parser.Usage` and returns FALSE; the main module then exits 1.

`-w` values below 25 make the Ada program fail with "invalid numeric
option argument" (status 2) as soon as it builds a 3-column row, since
the wrapped column would have no width (confirmed: `-w 24` fails).
The port declares `-w` with range `25 .. 32767` in `MakeIntOption`, so
ArgParser rejects it up front with the same status 2.

## 6. Command line (`Besm2Cli`)

A direct port of the Ada option table, in the same order (so the usage
lists them the same way): `-1`, `-B`, `-b`, `-D`, `-d`, `-H`, `-L`,
`-R`, `-S`, `-h`, `-i`, `-l`, `-M`, `-m`, `-n`, `-o`, `-p`, `-s`,
`-t`, `-U`, `-u`, `-w`. Each option gets a handler procedure; handlers
for `-1` (also sets `headSep := "-"`), `-H` (format and `hmmOutput`),
`-t`, `-m` keep the Ada "last format flag wins" behaviour. The
argument handler appends file names to a list in `Besm2Cli`. Defaults:
`boldHead` and `unicodeMinus` TRUE, `tableWidth` 60, `underliner` `-`,
`subunderliner` 0X (unset), `headSep` `=`.

`-L`'s range is `0 .. 32767`; `-o` and `-R` copy their argument into a
`Besm2Str.String` (ArgParser truncates arguments at 4095 characters,
which is harmless here).

## 7. Main module (`Besm2Fmt`)

1. `Besm2Cli.Parse`; exit 1 if help was shown.
2. If `-H` and `-R`: write `-L` tabs and the root text **to standard
   output via `Out`**, before any `-o` redirection (Ada and Scheme both
   do this).
3. If `-o`: `Besm2Out.ToFile(path)`; if the file can't be created,
   report and exit 1 (the Ada version would raise an unhandled
   `Name_Error` here; check what status it gives and match it).
4. For each file (or standard input if none): open a `FyamlStreams`
   stream; for each document, check the root is a sequence, and for
   each item `Load` it and call the selected backend with a running
   entity count that continues across the documents of one file. On
   error: report, close the stream, continue with the next file.
   Close each document when done with it.
5. `Besm2Out.Close`; flush `Out`; return normally (exit 0).

## 8. Testing

- **Unit tests.** `TestLayout` ports all 30 checks of
  `test/test_text_layout.adb`, including the golden STAT-table fragment
  from `enyon-boase-2e`, the `Rocket Pod` two-line block scalar wrap
  at width 36, and both `MinusGlyph` states. To capture `PutRow`
  output it points `Besm2Out` at a scratch file and reads it back.
  `TestStr` covers `Trim`, `AppendInt` (negative, zero, `MIN(INTEGER)`),
  `CompareCI`, `Join`.
- **Golden tests.** `test/data/` holds the four Ada `test-data/*.yaml`
  files plus synthetic fixtures for what they don't cover:
  enhancements and limiters in every shape (scalar, `[name, n]`,
  `[name, n, a]`, `[name, n, a, b]`), `elements`, `effective`, derived
  `alternatives`, skill `specialisations`, `mecha: true`/`false`/absent,
  an entity with no name, UTF-8 names that sort differently by byte and
  by case-folding, and error cases (missing key, bad integer, non-sequence
  root, bad customizer, bad YAML, a missing file among good ones).
  `run-golden.sh` runs each fixture through a flag matrix: none, `-s`,
  `-1`, `-B`, `-D`, `-n`, `-w 72`, `-u = -U ~`, `-t`, `-s -t`,
  `-t -b -l -M`, `-t -i`, `-t -p`, `-H`, `-H -s -S`, `-H -b`,
  `-H -R Root -L 1`, `-m`, `-s -m`, `-m -n`. Plus: standard input vs a
  file argument, `-o` vs standard output, several files in one run, and
  exit statuses for the error and bad-option cases. `make golden`
  regenerates `test/golden/` from the Ada binary (`ADA_BESM2_FMT`,
  default `~/Repos/RPG/Tools/besm2_fmt/besm2_fmt`); `make test`
  compares against the committed files, so it doesn't need the Ada
  checkout.
- **Valgrind.** Run the golden matrix under valgrind once the port
  works, with olibfyaml's `test/voc-gc.supp` and `test/libfyaml.supp`,
  to catch a document or stream left open.

## 9. Build order

Each step ends with its tests passing and PLAN.md updated.

1. [done] **Scaffolding.** `GNUmakefile` (`obj/` for voc output, `build/` for
   rendered reST/PDF as in the Ada makefile, `vpath` for
   `OBERON_MODULES`, `OLIBFYAML`, `-OC`, exported `LDLIBS`, copying
   `obj/Besm2Fmt` to `besm2_fmt`), `rtl/Args.Mod`, `.gitignore`,
   `test/Check.Mod`, and a stub `Besm2Fmt` that imports `ArgParser` and
   `FyamlStreams`, to prove the whole toolchain links under `-OC`.
   The stub counts the entities in each document of each file; on the
   four Ada test files it reports 2, 1+1 (two documents), 1 and 1, as
   expected. `-h` prints ArgParser's usage; `--bogus` gives ArgParser's
   error and status 2; a missing file gives olibfyaml's
   `nosuch.yaml: error: No such file or directory`. A second `make`
   does nothing. Findings:
   - The makefile's single `$(OBJ)/%.o: %.Mod` rule finds each module
     through `vpath` in `rtl`, `src`, `test`, `OBERON_MODULES` and
     `$(OLIBFYAML)/src`, and passes voc the absolute path.
   - **voc's `-M` (fully static link) doesn't work here**: there is no
     static `libfyaml` (`ld: cannot find -lfyaml`). The program is
     linked with `-m`, dynamically against `libfyaml.so.0` and
     `libvoc-OC.so`. The binary has no rpath; `libvoc-OC.so` is found
     through the system `ld.so` cache (`ldconfig -p` lists it under
     `/usr/local/sw/versions/voc/git/lib`), so an installed copy runs
     wherever that cache is set up the same way. Revisit in step 10 if
     `make install` needs to work elsewhere (a custom link with
     `libvoc-OC.a` and a shared `libfyaml` would do it).
2. [done] **`Besm2Str`, `Besm2Config`, `Besm2Out`, `Besm2Layout`** with
   `TestStr` and `TestLayout`. This is where the UTF-8 width and wrapping
   rules get pinned down. `TestLayout` ports all 30 checks of the Ada
   `test_text_layout.adb`, in order, and all pass, including the golden
   STAT-table rows and the `Rocket Pod` wrap with and without the
   embedded newline. It adds checks for whitespace runs in `WordWrap`, a
   wrapped `Row2` with its continuation line, and `EmptyRow`. `TestStr`
   covers lengths, `Trim`, `Int` down to `MIN(INTEGER)`, `Buffer`,
   `List`, `Join`, `LessCI` (including the Ada fold of lead byte
   `C3X`) and the stability of `SortCI`. Design changes and findings:
   - **voc won't pass a dereferenced function result, `F()^`, to an
     open-array parameter** (`err 59 illegal open array parameter`).
     So `Row2`/`Row3` take `String`s, not `ARRAY OF CHAR`, and
     `Besm2Out.Str(s: String)` sits beside `Besm2Out.String`, letting
     `Row3(Hbolding("VALUE"), ...)` and `Besm2Out.Str(Bold("Size:"))`
     be written without temporaries. Procedures that mostly take
     literals keep `ARRAY OF CHAR`.
   - **voc doesn't zero local records**: a local `Buffer`'s pointer is
     garbage before first use, not NIL. `Besm2Str.Reset` always
     allocates; `Buffer` and `List` must be `Reset`/`Clear`ed before
     use. (Found when "allocate only if NIL" halted with "Index out of
     range".)
   - **`Besm2Out` writes through `Platform`, not `Files`**:
     `Platform.New` returns an error code for a file it can't create,
     while `Files` creates the file only at `Register` and halts on
     failure. It keeps its own 8 KB buffer for standard output too
     (voc's `Out.Ln` flushes on every line), so it must be flushed
     before anything else is written to the same place.
   - **voc's `Files` caches files by inode**: `Files.Old` returns the
     cached `File`, with its old buffers, and `Files.Close` doesn't
     drop it. A capture file rewritten in place (same inode, since
     `Platform.New` truncates) read back as the first capture's text.
     `TestLayout` uses one file per capture.
   - `AddInt` takes `INTEGER` and works in `LONGINT` (64 bits under
     `-OC`), so negating `MIN(INTEGER)` can't overflow and `DIV`/`MOD`
     see only non-negative values.
   - Oberon-2 has no string concatenation operator and no `CHAR` `FOR`
     loops; `(*` in a comment (a quoted Scheme expression) opens a
     nested comment. All three came up.
3. **`Besm2Cli`** and the main module's option handling: check the
   exit statuses of `-h`, bad options, bad `-u`, bad `-w`.
4. **`Besm2Entities`** plus a debug dump (under `-d`) to check loading
   before any backend exists.
5. **`Besm2Terse`** first (no column layout), then golden tests for it,
   as the Ada port did.
6. **`Besm2Grid`**, golden tests.
7. **`Besm2Hmm`**, golden tests, including `-R` with `-o`.
8. **`Besm2RawMs`**, golden tests.
9. **Error handling** golden tests, `-o`, standard input, several files.
10. **Makefile parity**: `rst`, `pdf`, `install` (to `$HOME/local/bin`)
    targets matching the Ada `GNUmakefile`; README.
11. Valgrind pass. Optionally, a benchmark against the Ada binary with
    the Ada repo's `tools/benchmark.sh` inputs.

## Open questions

- **Where should the `Args` shim live?** This plan keeps it in
  `rtl/Args.Mod` here. It would be better installed with ArgParser
  (say as `oc-rtl/Args.Mod`, installed to `OBERON_MODULES/oc/`) so any
  `-OC` program, including olibfyaml users, can use ArgParser. That is
  a change to the ArgParser repo, so it needs the user's go-ahead.
- **Case-insensitive sort beyond ASCII.** Ada's `To_Lower` also folds
  bytes `C0X..DEX` (Latin-1 capitals, except `D7X`), which in UTF-8
  are lead bytes, so it can order some non-ASCII names differently
  from ASCII-only folding (`besm2-rst.scm` folds by Unicode character).
  Plan: copy Ada's folding exactly, so the output matches; revisit
  only if the Ada behaviour is declared a bug.
- **Sort stability.** GNAT's `Generic_Sorting` isn't documented as
  stable; this port's insertion sort is. The two differ only for
  entries whose names are equal ignoring case, which no fixture has.
  A synthetic fixture will show whether the Ada order is stable in
  practice; if not, decide which to follow.
- **`-o` to an unwritable path**: find the Ada exit status and message
  (step 7 of §7) before fixing the Oberon behaviour.
