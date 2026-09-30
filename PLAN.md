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
    golden/                       -- expected output, generated from the Ada binary (or besm2-rst)
    golden.cases, golden.sh       -- the flag matrix, and the script that checks or regenerates it
    cli.sh                        -- command-line checks: exit statuses, messages
  GNUmakefile
  AGENTS.md, PLAN.md, README.md
  ADA-DIFFERENCES.md    -- every known way the Ada version differs or is defective
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

Ada behaviour to match (as of Ada `8308c10`, step 14; the notes in
brackets are where the Ada version differed before that):

| Case | Ada | Status |
|---|---|---|
| Bad YAML, missing key, malformed number, top level not a sequence, bad customizer | `besm2_fmt: error processing FILE: MESSAGE` on stderr, skip the rest of that file, continue with the next | 0 |
| A list or item of the wrong shape (`stats: 5`, an entity that isn't a mapping) | Reported like the row above, with the node's path (step 4) [Ada: unhandled assertion failure, status 1] | 0 |
| A file that can't be opened | `besm2_fmt: FILE: REASON`, continue with the next | 0 |
| Unknown option, missing option argument, bad `-u`/`-U` | diagnostic on stderr | 2 [Ada: 0 for bad `-u`/`-U`; see step 3] |
| Non-numeric or out-of-range `-w`/`-L` | diagnostic on stderr | 2 |
| `-o` file can't be created, or output can't be written | `besm2_fmt: can't create PATH: REASON`, `besm2_fmt: error writing output: REASON` | 1 |
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

`-w` values below 25 made the Ada program fail with "invalid numeric
option argument" (status 2) as soon as it built a 3-column row, since
the wrapped column would have no width (confirmed: `-w 24` failed).
The port declares `-w` with range `25 .. MAX(INTEGER)` in
`MakeIntOption`, so ArgParser rejects it up front with the same
status 2. The Ada version now does the same (step 14).

Step 3 found that a bad option *value* (`-u xx`, `-w 0`) didn't give
status 2 in the Ada version, as the table above expected, but status 0
after carrying on; the port exits 2. See step 3. The Ada version now
exits 2 too (step 14).

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

`-L`'s range is `0 .. MAX(INTEGER)`; `-o` and `-R` copy their argument into a
`Besm2Str.String` (ArgParser truncates arguments at 4095 characters,
which is harmless here).

## 7. Main module (`Besm2Fmt`)

1. `Besm2Cli.Parse`; exit 1 if help was shown.
2. If `-H` and `-R`: write `-L` tabs and the root text **to standard
   output via `Out`**, before any `-o` redirection (Ada and Scheme both
   do this).
3. If `-o`: `Besm2Out.ToFile(path)`; if the file can't be created,
   report and exit 1 (the Ada version raises an unhandled
   `Name_Error` here, which also exits 1).
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
  `golden.sh` runs each fixture through a flag matrix
  (`test/golden.cases`, built up format by format from step 5 on): none, `-s`,
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
3. [done] **`Besm2Cli`** and the main module's option handling: check the
   exit statuses of `-h`, bad options, bad `-u`, bad `-w`.
   `Besm2Cli` adds the 22 options in the Ada order with the Ada
   descriptions. The main module now has its final shape (parse; exit 1
   after help; the `-R` line to standard output; `-o`; files or standard
   input through `FyamlStreams`; a per-file error ends that file only;
   `Besm2Out.Close`). An entity count stands in for the formats until
   step 5. `test/cli.sh` (run by `make test`) checks 20 cases: status,
   plus a line of output or error each must contain. `test/data/` now
   holds copies of the four Ada `test-data` files. Findings, from
   running the same cases against the Ada binary first:
   - **The Ada version mishandles a bad option value.** `-u xx`,
     `-U ab` and `-w 0` print "Invalid value for option ..." and then
     parsing stops but the program carries on: it processes the files
     named before the bad option, or, if there were none, reads
     standard input (confirmed by feeding a YAML file on stdin), and
     exits 0. Its main has a handler that exits 2 for exactly this
     error, which is apparently never reached. **The port exits 2**,
     the evident intent and ArgParser's status for every other
     command-line mistake. Deliberate difference, not ported.
   - `-w` is `25 .. MAX(INTEGER)`: the Ada version accepts `-w 1` and
     fails at `-w 24` and below with "invalid numeric option argument",
     status 2, once it writes a three-column row; `-w 25` works (a
     one-character wrapped column). Same status, earlier and clearer.
     `-L` is `0 .. MAX(INTEGER)`.
   - `-w -5` and `-L -1`: Ada says "Argument Required" (it takes `-5`
     for an option), status 2; ArgParser takes `-5` as the value and
     says it is out of range, status 2.
   - `-u=` sets the underliner to `=` (ArgParser takes the rest of the
     cluster as the value); Ada took the next argument instead. Not
     worth matching.
   - **`-o` to a path that can't be created**: the Ada version dies with
     an unhandled `NAME_ERROR`, status 1, showing the OS reason. The
     port writes `besm2_fmt: can't create PATH: REASON` (from
     `strerror`, through a private code procedure in `Besm2Fmt`) and
     exits 1. (Closes the open question.)
   - Errors from olibfyaml are written as `besm2_fmt: ` plus its
     message, which already names the file, instead of
     `besm2_fmt: error processing FILE: ...` (which named it twice).
     Errors the port finds itself keep the Ada wording. Standard input
     is `<stdin>` in both.
4. [done] **`Besm2Entities`**, checked by `TestEntities` rather than
   by a debug dump under `-d` as first planned: the Ada version never
   reads `-d`/`Debugging`, so making `-d` print something would be a
   behaviour it doesn't have. `TestEntities` (52 checks) loads the real
   `enyon-boase-2e` and `FV2021-Coleopteran-2e` fixtures and made-up
   ones, with expected values taken from the fixtures and the Ada
   binary's terse output: fields, absent fields as NIL, document order
   for stats and derived values, sorting of attributes, defects and
   skills, trimming, the embedded newline kept in `Rocket Pod`'s
   details, every subtotal and the entity total, `mecha: false`, and
   every customizer shape, whose details string (`air, Fire; Area −1,
   Big: b, c −3, Range −5, Short +-1, Slow +1, Zone: a −2; hi`, also
   with `-n`) was copied from the Ada output. A deliberately broken sort
   made three checks fail, so they bite. The main module now loads each
   entity and writes a placeholder line (number and name); `cli.sh`
   checks that a bad entity writes nothing, ends its file but not the
   run, with status 0. Findings:
   - **YAML of the wrong shape crashes the Ada version**: an entity
     that isn't a mapping, `stats: 5`, a list item that isn't a mapping
     or a scalar, `enhancements: Area`, a customizer `[Range]` (it reads
     item 2 before checking the length), an applies-to that is a
     sequence. Each dies with `ADA.ASSERTIONS.ASSERTION_ERROR`, a failed
     precondition in alibfyaml, status 1, and no file name. olibfyaml
     would halt the same way (an `ASSERT` on the node kind), so the
     port checks shapes first and reports them as input errors, with
     the node's path: `besm2_fmt: error processing FILE: /0/stats: not
     a sequence`, status 0, like any other bad data. Deliberate
     difference.
   - Values of the right shape but wrong content (a missing key,
     `points: x`, `mecha: yes`, a non-scalar `name`) are reported by
     olibfyaml, as the Ada version reports them through alibfyaml.
   - All five item kinds extend `NamedDesc` (a `name` field), so one
     `List` type and one stable insertion sort serve all of them; a
     backend takes an item out with a type guard, `items[i](Stat)`.
   - **Oberon-2 needs every `CONST`/`TYPE`/`VAR` before the first
     procedure** of a module, and **a read-only exported field
     (`stats-`) can't be passed as a `VAR` parameter** outside its
     module; pass it by value (`List` is a pointer and a count, so
     copying is cheap).
5. [done] **`Besm2Terse`** first (no column layout), then golden tests for it,
   as the Ada port did. Its output was byte-identical to the Ada
   binary's on the first build, on all four real fixtures with and
   without `-s`, and on a new made-up fixture, `synthetic-2e.yaml`
   (every customizer shape, elements, effective levels, alternatives,
   specialisations, `mecha: true` and `false`, an unnamed entity, a
   tagline and size, UTF-8 names in the sort, a multi-line block
   scalar in defect details), under `-b -l -M`, `-i -n`, `-b -i`, `-p`,
   `-p -D`, `-u = -U ~` and `-H -m -t` (the last format flag wins).
   The golden framework is in place:
   - `test/golden.cases` lists cases as `REF ID FIXTURES FLAGS`;
     `test/golden.sh check` compares standard output and error together
     with `test/golden/FIXTURE.ID.out` and requires status 0, and `make
     golden` (`test/golden.sh generate`) rewrites the files from the
     reference program. `make test` runs the check. 46 cases so far, all
     passing. As a control, checking `besm2-rst` itself against them
     fails 18 (its minus sign differs), so the comparison bites.
   - **The Ada sort isn't stable**, answering the open question.
     `sort-ties.yaml` (names equal but for case) comes out of the Ada
     binary as `ARMOUR 3, armour 1, Armour 2, armour 4`, an artifact of
     GNAT's `Generic_Sorting`; the real `besm2-rst`
     (`~/local/bin/besm2-rst`, Chicken's merge sort) keeps document
     order, `armour 1, Armour 2, ARMOUR 3, armour 4`, as the port's
     insertion sort does. The port keeps its stable sort, and
     `golden.cases` takes that fixture's golden file from `besm2-rst`
     (`REF` = `scheme`), not the Ada binary. The Ada fixtures are
     `*-2e.yaml`; `sort-ties.yaml` has no `-2e` so they don't pick it
     up. (`besm2-rst -t` also matches the port on `enyon-boase-2e`.)
   - `Besm2Str.Join` now takes its `List` by value, so a read-only
     `List` field of an item can be joined directly.
6. [done] **`Besm2Grid`**, golden tests. Byte-identical to the Ada
   binary on the first successful build, for all five `-2e` fixtures
   under 11 flag sets (none, `-s`, `-1`, `-B`, `-D`, `-n`, `-w 72`,
   `-w 25`, `-u = -U ~`, `-b -i -l -M`, `-1 -s -B`); 10 grid cases in
   `golden.cases`, 96 golden files in all, all passing (the 46 from
   step 5 regenerated unchanged). The only compile error was `F()^`
   again. Findings:
   - **`-1`/`--one` is now verified.** The Ada port wrote `Empty_Row`
     from the Scheme's definition with no fixture; the port's `-1` and
     `-1 -s` output matches the Ada binary and also `besm2-rst` (run
     with `-n` here, since `besm2-rst` defaults to the ASCII minus).
   - **Where the Ada version departs from `besm2-rst`**, found by
     diffing grid output of `synthetic-2e.yaml` against `besm2-rst`.
     The port follows Ada in each (the Ada binary is the reference),
     but they are recorded here so they aren't rediscovered as port
     bugs:
     - Header underlines: `besm2-rst` counts characters (16 for
       `Rana “Frog” Élan`), Ada counts bytes (21). Longer is harmless
       in reST.
     - `effective: ""`: `besm2-rst` writes `1 ()`, Ada skips the empty
       value.
     - The level and `(effective)` are joined by a no-break space
       (`C2 A0`) in `besm2-rst`, an ordinary space in Ada.
     - Case-insensitive order of non-ASCII names: `besm2-rst` folds by
       Unicode character and puts `élan vital` before `“Quoted” Power`;
       Ada's byte-wise Latin-1 fold puts it after. (See the open
       question on this.)
     - `composite-multi-doc-2e.yaml`: `besm2-rst` loses documents of a
       multi-document file (the bug the Ada PLAN mentions); Ada and the
       port read them all.
7. [done] **`Besm2Hmm`**, golden tests, including `-R` with `-o`.
   Byte-identical to the Ada binary on the first successful build, for
   all five `-2e` fixtures under 10 flag sets (`-H`, `-H -s`, `-H -S`,
   `-H -s -S`, `-H -b`, `-H -i -l -M`, `-H -L 2`, `-H -D -n`,
   `-H -R Root -L 1`, `-t -H`); 10 h-m-m cases in `golden.cases`, 146
   golden files in all, all passing (the 96 from steps 5 and 6
   regenerated unchanged). Findings:
   - **`-R` with `-o`** can't be a golden case (the output goes to a
     file), so it was checked by hand: `-H -R Root -o FILE` writes the
     root line to standard output and the entities to FILE, and both
     match the Ada binary's. `-R` without `-H` is ignored by both.
   - **No new departures from `besm2-rst`.** Diffing `./besm2_fmt -n -H`
     against `besm2-rst -H` shows only those found in step 6: the
     no-break space before `(effective)`, `effective: ""` as `()`, the
     sort position of `élan vital`, and the documents `besm2-rst` loses
     from `composite-multi-doc-2e.yaml`. The byte-counted underline
     doesn't arise: an outline has no underlines.
8. [done] **`Besm2RawMs`**, golden tests. Byte-identical to the Ada
   binary on the first successful build, for all five `-2e` fixtures
   under 9 flag sets (`-m`, `-m -s`, `-m -n`, `-m -s -n`, `-m -D`,
   `-m -b -i -l -M -p`, `-m -u = -U ~`, `-m -1 -B -w 30`, `-H -t -m`);
   8 raw ms cases in `golden.cases`, 223 golden files in all, all
   passing (the 146 from steps 5 to 7 regenerated unchanged). Findings:
   - **A new fixture, `sections-2e.yaml`**, because none of the others
     reach part of the section bookkeeping: tables that start with
     derived values, defects or skills rather than stats, and totals of
     zero or below (no TOTAL row). Its output matches the Ada binary in
     every format, and `besm2-rst` too (with `-n`).
   - **No new departures from `besm2-rst`.** Diffing `./besm2_fmt -n -m`
     against `besm2-rst -m` shows only those found in step 6: the
     byte-counted underline, `effective: ""` as `()`, the no-break space
     before `(effective)`, the sort position of `élan vital`.
   - Two more quirks kept, added to ADA-DIFFERENCES.md, section 5: the
     lines between sections are the three-blank indent alone, and one
     entity's `.TE` runs straight into the next entity's name.
9. [done] **Error handling** golden tests, `-o`, standard input, several files.
   `golden.sh` now takes modes after the reference (`ada:stdout`,
   `ada:all`, `ada:stdin`, `ada:file`; see `test/golden.cases`), so
   these are golden cases too, compared with the Ada binary: for bad
   input, standard output only, since the messages differ on purpose
   (section 5); `test/cli.sh` checks the messages. 20 cases, 282 golden
   files in all, all passing (the 223 from steps 5 to 8 regenerated
   unchanged). New fixtures: `bad-*.yaml` (errors), `edge-*.yaml`
   (empty input that isn't an error), `shape-*.yaml` (errors that halt
   the Ada version, so `cli.sh` only). Findings:
   - **The port matches the Ada binary** on everything that isn't an
     Ada crash: what is written before an error in every format, that
     nothing of the file is written after it, entity numbering (for
     `-U`) starting again with each file, a bad file not ending the
     run, standard input (including several documents), `-o` (a new
     file, or an existing one, which is truncated; with several files;
     with `-R`), and exit status 0 for bad input.
   - **Empty input:** a file with no documents writes nothing and isn't
     an error, in both. An empty document (`---` with nothing after
     it) is an error, "expected a top-level YAML sequence", in both;
     `besm2-rst` fails on it too.
   - **Two more Ada crashes:** `stats:` with no value, and a customizer
     of one item (already in ADA-DIFFERENCES.md, 1.3), halt on an
     assertion with status 1; the port reports them as bad input.
   - **Write errors** (ADA-DIFFERENCES.md, 1.10): output to a full
     device raises an unhandled `DEVICE_ERROR` in Ada, status 1; the
     port reports `error writing output: REASON`, status 1. A closed
     pipe kills both with SIGPIPE (status 141).
   - A customizer sequence of five or more items is accepted by both
     (and by `besm2-rst`): the items after the counts-as value are all
     applies-to text.
10. [done] **Makefile parity**: `rst`, `pdf`, `install` (to `$HOME/local/bin`)
    targets matching the Ada `GNUmakefile`; README. Also `uninstall`
    and `testclean`; `clean` now removes `build/` too. Findings:
    - `make rst` builds the Ada `GNUmakefile`'s five variants (grid,
      `-terse`, `-tbl`, and `-n` of grid and tbl, all with `-s`) from
      `test/data/*-2e.yaml`: 30 files, each identical to the Ada
      binary's output for the same flags. `make pdf` renders all 30
      through `pandoc -w ms --template=tkb` without warnings; the tbl
      tables render.
    - **The Ada `-unicode-minus` files are misnamed** (ADA-DIFFERENCES.md,
      1.11): built with `-n`, which turns the Unicode minus *off* in
      the Ada version. Here they are `-ascii-minus`.
    - Not ported: the Ada `benchmark`, `benchmark-alibfyaml-liveness`,
      `pdf-comparison` and `html-comparison` targets, which belong to
      the Ada repo's own documents and tools (step 11 may add a
      benchmark).
    - `install` uses `install(1)` to `$(DESTDIR)$(PREFIX)/bin`, with
      `PREFIX` defaulting to `$HOME/local` as the Ada `besm2_fmt.gpr`
      does. That is where the Ada binary is installed now, so it would
      be replaced; checked only with `DESTDIR` into a scratch directory.
    - README.md: what the program is, an example checked against the
      program, usage, exit statuses, building and the documents.
11. [done] Valgrind pass. Optionally, a benchmark against the Ada binary with
    the Ada repo's `tools/benchmark.sh` inputs. Findings:
    - **`make valgrind`**: 123 runs (every fixture in five formats,
      several files, standard input, empty standard input, `-o`, and
      the early exits), each with no errors, nothing lost, and nothing
      still reachable but voc's 256,024-byte heap chunk. It uses
      olibfyaml's `test/voc-gc.supp` (the GC's conservative stack scan)
      and `test/libfyaml.supp` (libfyaml's `realloc(buf, 0)` on empty
      input) from its checkout. Also clean by hand on 650 KB and 970 KB
      inputs (2000 entities and more), where the GC runs many times.
      Control: without the suppressions, 12 runs fail.
    - **The benchmark found a real bug that valgrind can't see: the GC
      freed strings still in use.** In 2000-entity inputs about 1 grid
      or raw ms header in 400 came out as garbage, always the last
      cell of `Row3(H("LEVEL"), H("POINTS"), H("ATTRIBUTE"))` and the
      like. The disassembly shows why: voc compiles C without
      optimization, gcc evaluates the arguments right to left and keeps
      each finished one only in a callee-saved register (`r12`, `rbx`)
      while the next `H` allocates. voc's GC finds pointers on the stack
      only; its "register pressure" loop, meant to push the callee-saved
      registers there, does nothing at `-O0`, and nothing else on the
      allocation path saves them. So a collection during that call
      frees the string. (valgrind sees nothing wrong: the memory is
      voc's own heap chunk.) Fixed for every call at once by building
      with `CFLAGS=-ffixed-rbx -ffixed-r12 -ffixed-r13 -ffixed-r14
      -ffixed-r15` (voc appends `$CFLAGS` to its cc command), so gcc
      never uses them; `obj/cflags` rebuilds every object when CFLAGS
      changes. Checked both ways on 2000- and 5000-entity inputs in six
      flag sets: 12 of 24 runs differed from the Ada binary before, 0
      after. `test/regs.sh` (in `make test`) fails if any object uses
      those registers, and `cli.sh` checks that 1000 copies of an
      entity come out as 1000 copies of its output in five flag sets
      (it fails on the old build for grid, raw ms and `-1`). The
      voc runtime library itself (`libvoc-OC.so`) is built without
      these flags, so the hazard remains inside it; this program calls
      it little. Anything else built with voc -- olibfyaml's own tests,
      ArgParser's users -- may have the same bug.
    - **Benchmark** (`make benchmark`, `tools/benchmark.sh`, report in
      `PERFORMANCE-COMPARISON.md`): outputs are checked identical
      first. One small file per run takes about as long as the Ada
      binary (about 2 ms). On 2000 entities, as one document or as 2000,
      the port takes 2 to 4 times as long (0.35 to 0.8 s against 0.17
      to 0.32 s), with the same peak memory. A short `perf` profile of
      terse on 2000 entities shows most samples in libfyaml's scanner
      and `malloc`, few in the Oberon code; not investigated further.
12. [done] **Lists of only empty strings, and empty strings**, found
    while rewriting this program on Ropes (`~/Repos/RPG/Tools/obesm2_fmt2`,
    its PLAN.md, step 7). Findings:
    - **A defect, fixed**: with `alternatives: [""]` or
      `specialisations: [""]`, a list whose items are all empty, the
      grid and raw ms formats wrote `Attack Combat Value` where the Ada
      binary and `besm2-rst` write `Attack Combat Value ()`. They
      tested whether the joined text was empty (`WithParens`); the Ada
      version tests whether the list is (`Is_Empty`). `Besm2Grid` and
      `Besm2RawMs` now use `WithList`, which tests the number of items;
      `WithParens` is left for details, where the Ada version does test
      the text. Terse and h-m-m already tested the list. No golden case
      caught it, since no fixture had such a list.
    - Two new fixtures, with golden files from the Ada binary in every
      per-fixture case (356 golden files now; the old ones regenerated
      unchanged but for the five several-files cases, whose glob now
      picks up the new fixtures): `empty-items-2e.yaml` for the defect
      (its grid and raw ms cases failed before the fix), and
      `empty-strings-2e.yaml`, for `name`, `tagline`, `description` and
      `size` present but empty, blank-only taglines and details, an
      empty `effective`, and empty stat names and values, on which this
      port already matched the Ada binary.
13. [done] **`make perfdata`**, for comparing this program with its
    rewrite on Ropes (`~/Repos/RPG/Tools/obesm2_fmt2`, whose `make
    perfcompare` runs it here and writes the report). It runs
    `tools/perfdata.sh`, a file shared with that repo, which times this
    program alone (instruction counts, CPU and wall time, peak memory)
    and writes `build/perfdata.tsv`. The rewrite's PLAN.md, step 9, has
    the results: on big inputs this program executes 1.25 to 2 times
    the rope version's instructions in most cases, because `Buffer`
    allocates at every `Reset` and copies at every `Get`, and it
    collects garbage more often (672 collections against 255, terse
    on 2,000 entities); on one small file it is
    faster, since it doesn't allocate enough to trigger a collection.
14. [done] **The Ada version fixed ADA-DIFFERENCES.md's section 1.**
    Every defect there is fixed in the Ada version too: besm2_fmt
    `8308c10`, with alibfyaml `3053d06` (a file that can't be opened
    raises `Name_Error`/`Use_Error` with the OS reason; string input
    can be named) and a change to Arg_Parser not yet committed there
    (an option's next argument is taken even if it starts with `-`;
    all its messages go to standard error). The Ada repo gained a test
    suite adapted from this one (`test/golden.sh`, `test/cli.sh`, the
    same fixtures and golden files).
    - `make golden` from the fixed Ada binary rewrote all 356 golden
      files unchanged, so the fixes changed no standard output this
      port is compared on.
    - `sort-ties` is now an `ada` case, not `scheme`: the Ada sort is
      stable, and its output is byte-identical to `besm2-rst`'s golden
      file. A grid case for it was added. No `scheme` cases remain;
      the mechanism stays in `golden.sh` in case one is needed again.
    - `test/data/shape-*.yaml` are now golden cases (`ada:stdout`, in
      the `bad` globs), since the Ada version no longer halts on them:
      363 golden files. Its messages for them are word for word the
      port's.
    - What still differs is only message wording (ADA-DIFFERENCES.md,
      3.3 to 3.5), and one defect found in the port while comparing:
      a directory given as a file was silently read as empty
      (ADA-DIFFERENCES.md, 6.1), since olibfyaml's `Fyaml.Unreadable`
      checked only that the path opens. The Ada version now reports
      `Is a directory`, and so does the port, after a fix in olibfyaml
      (`FyThin.OpenErrno` `fstat`s the file; reading it instead would
      lose input from a pipe given as a path). `test/cli.sh` checks
      both.

## Open questions

- **Where should the `Args` shim live?** This plan keeps it in
  `rtl/Args.Mod` here. It would be better installed with ArgParser
  (say as `oc-rtl/Args.Mod`, installed to `OBERON_MODULES/oc/`) so any
  `-OC` program, including olibfyaml users, can use ArgParser. That is
  a change to the ArgParser repo, so it needs the user's go-ahead.
- **Case-insensitive sort beyond ASCII.** (Step 6 confirmed that
  `besm2-rst` does order such names differently from Ada:
  `élan vital` sorts before `“Quoted” Power` there, after it in Ada and
  the port.) Ada's `To_Lower` also folds
  bytes `C0X..DEX` (Latin-1 capitals, except `D7X`), which in UTF-8
  are lead bytes, so it can order some non-ASCII names differently
  from ASCII-only folding (`besm2-rst.scm` folds by Unicode character).
  Plan: copy Ada's folding exactly, so the output matches; revisit
  only if the Ada behaviour is declared a bug.
- ~~**Sort stability.**~~ Resolved in step 5: the Ada sort isn't
  stable, `besm2-rst`'s is, and the port follows `besm2-rst`. The Ada
  sort is stable now too (step 14).
- ~~**`-o` to an unwritable path**~~: Resolved in step 3. Ada exits 1
  (unhandled `Name_Error`); the port reports the OS reason and exits 1.
  The Ada version now reports it the same way (step 14).
