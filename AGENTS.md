# AGENTS.md

Working notes for an agent in this repo, which holds `besm2_fmt`, an
Oberon-2 port (compiled with voc, Vishap Oberon) of the Ada program in
`~/Repos/RPG/Tools/besm2_fmt`. That program is itself a port of
`besm2-rst.scm` from [besm-tools](https://github.com/tkurtbond/besm-tools).
It reads YAML files describing BESM 2nd Edition characters, templates
and items, and writes them as reStructuredText (grid tables, terse,
raw ms/tbl) or as an h-m-m outline.

See PLAN.md for the design, the module layout, the build order and
open questions. This file is operational notes, not a design doc.

## Reference material

| What | Where |
|---|---|
| Ada program being ported | `~/Repos/RPG/Tools/besm2_fmt/` (`src/`, `PLAN.md`, `GNUmakefile`) |
| Ada binary (the golden-output oracle) | `~/Repos/RPG/Tools/besm2_fmt/besm2_fmt` (build with `make` there) |
| Original Scheme program | `besm2-rst.scm` in besm-tools |
| ArgParser (command-line parsing) | `~/Repos/Oberon/ArgParser/` (`AGENTS.md`, `ArgParser.Mod`, `Err.Mod`); installed copies in `$OBERON_MODULES` (default `/usr/local/sw/versions/oberon/include`) |
| olibfyaml (YAML) | `~/Repos/Oberon/olibfyaml/` (`AGENTS.md`, `README.md`, `src/FyThin.Mod`, `src/Fyaml.Mod`, `src/FyamlStreams.Mod`) |
| voc compiler | `/usr/local/sw/versions/voc/git/bin/voc`; not on the default `PATH` |
| voc source and runtime | `/usr/local/sw/src/lang/Oberon/vishap/compiler/` (`src/runtime/`, `src/library/`) |
| Oberon-2 report | `~/Reference/Computer/Languages/Oberon/Oberon2.pdf` |

Read olibfyaml's and ArgParser's `AGENTS.md` before working around
either library. Most of what they say about voc applies here too.

## Build / test

```sh
export PATH=/usr/local/sw/versions/voc/git/bin:$PATH
make            # obj/ (voc output) and ./besm2_fmt
make test       # unit tests (golden-output comparison to come)
make clean      # rm -rf obj besm2_fmt
make print-VAR  # show a makefile variable
```

Planned, not yet written (PLAN.md, section 9): `make golden` to
regenerate `test/golden/` from the Ada binary, and `make rst pdf
install` as in the Ada `GNUmakefile`. Update this list as they land.

- **Everything is compiled with `-OC`**, as the first voc option,
  because olibfyaml requires it: its `.sym` files and runtime library
  differ between voc's size models, and mixing models fails. Under
  `-OC`, `INTEGER` is 32 bits and `LONGINT` 64.
- **voc's `Args` module exists only in the `-O2` library**
  (`/usr/local/sw/versions/voc/git/2/sym/Args.sym`), not in `-OC`'s,
  but `ArgParser` imports it. This repo supplies `rtl/Args.Mod`, the
  same shim over `Modules` as ArgParser's `poc-rtl/Args.Mod`. Confirmed
  live: with it, `ArgParser` compiles under `-OC` and parses short,
  long, `--name=value` and ranged integer options correctly.
- **Don't copy `ArgParser.Mod`, `Err.Mod` or olibfyaml's modules into
  this repo.** The makefile finds `ArgParser.Mod`/`Err.Mod` through
  `vpath` in `OBERON_MODULES` (as ArgParser's AGENTS.md asks) and
  olibfyaml's through `OLIBFYAML` (default `~/Repos/Oberon/olibfyaml`),
  and voc compiles them into `obj/`.
- voc writes `Mod.c`/`.h`/`.sym`/`.o` into the current directory, so
  every voc call runs inside `obj/`. Modules must be compiled in import
  order. Make targets are the `.o` files, not the `.sym` files (voc
  leaves an unchanged `.sym`'s mtime alone). **Adding a module means
  adding it to the makefile's module list in import order and adding
  an `obj/New.o: obj/Imported.o` line for each import.**
- `LDLIBS=$(pkg-config --libs libfyaml)` must be exported for the link
  of the main module; voc reads it from the environment.
- The main module is `Besm2Fmt` (an Oberon identifier can't contain
  `_`); the makefile copies `obj/Besm2Fmt` to `./besm2_fmt`.
- Link main modules with `-m`, not `-M`: `-M` links fully statically,
  and there is no static `libfyaml`. `libvoc-OC.so` is found at run
  time through the system `ld.so` cache.
- A new library module goes in `PROGMODS` (in import order), a unit
  test in `TESTS`.

## Testing policy

- **The Ada binary is the reference.** Output on standard output must
  match it byte for byte for every fixture and flag combination in
  `test/golden/`. Where PLAN.md records a deliberate difference (error
  message text on standard error, the usage text), the golden test
  checks exit status only, not the text.
- **Regenerate golden files from the Ada binary with `make golden`;
  never hand-edit one.** If a golden file looks wrong, the bug is in the
  Ada program: report it rather than making the port disagree.
- A new behaviour worth testing gets a fixture in `test/data/` and a
  line in the golden flag matrix, not a one-off manual diff.
- Unit tests (`test/Test*.Mod`) print `ok   - <label>` / `FAIL -
  <label>` and end with `All checks passed.` or `<N> check(s) failed.`,
  exiting 1 on failure (olibfyaml's `Check.Mod` convention). Never end
  a passing test with `Platform.Exit(0)`: it skips finalizers.

## voc / Oberon-2 facts this port depends on

Confirmed in olibfyaml or ArgParser unless noted.

- **No exceptions.** The Ada version raises `Missing_Key`,
  `Data_Error` and `Program_Error` from deep inside `Load_Entity` and
  catches them once per file. Here every loader returns `BOOLEAN` and
  passes an error message back; see PLAN.md, "Errors". `ASSERT`/`HALT`
  are for programmer errors only, never bad input.
- **No generics, closures or call chaining.** `root.Value("a").Value("b")`
  doesn't compile; use a variable per step. Nested procedures can't be
  passed as procedure values, so iterate with `Fyaml.ItemIter` rather
  than callbacks.
- **olibfyaml indexes sequences from 0**; Ada's `Item (1)` is `Item(0)`
  here.
- **Function procedures can't return arrays or records**: strings are
  `POINTER TO ARRAY OF CHAR`, 0X-terminated.
- **`Out` can't be redirected**, unlike Ada's `Set_Output`. All program
  output goes through `Besm2Out` so `-o` can send it to a file. The one
  exception, the `-R`/`--hmm-root` line, goes to standard output even
  under `-o`, as in the Ada version.
- **`Out` buffers until `Out.Ln`/`Out.Flush`, and `Platform.Exit`
  doesn't flush it.** Flush before exiting.
- **Argument evaluation order is unspecified** (voc compiles to C). Don't
  pass `err` in the same call that sets it.
- **`*)` ends a comment anywhere, and `(*` inside a comment opens a
  nested one.** Write "and friends", not a C wildcard, before a `)`.
- **UTF-8 in string literals passes through unchanged** (confirmed
  live: `"em dash: —"` prints correctly). `CHAR` is a byte, so `LEN`
  and `Strings.Length` count bytes, not characters.
- **Allocation is what makes voc programs slow** (olibfyaml's PLAN.md,
  Phase 6). BESM files are small, so clarity wins here, but don't
  allocate per character in inner loops.

## Conventions

- Keep each Oberon module traceable to its Ada counterpart (PLAN.md has
  the mapping). Keep the Ada comments that explain *why* something
  matches `besm2-rst.scm` (the Unicode minus, the `mecha` fix, the
  unconditional skill total, ...), adapted to Oberon; they record
  behaviour that was confirmed against the real Scheme binary.
- Comments explain why, and only claim what has been verified. If a
  comment depends on how voc, libfyaml or ArgParser behaves, test it
  with a throwaway program in the scratchpad first.
- Record decisions and findings in PLAN.md as they happen. Mark a
  finished step `[done]` and strike through an open question once it's
  decided.
