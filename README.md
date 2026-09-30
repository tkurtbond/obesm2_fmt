# besm2_fmt — an Oberon-2 port

`besm2_fmt` reads YAML files describing *Big Eyes, Small Mouth* 2nd
Edition characters, templates and items, and writes them as
reStructuredText (grid tables, terse paragraphs, or groff `tbl` tables
in a raw ms block) or as an [h-m-m](https://github.com/nadrad/h-m-m)
outline.

This is a port to Oberon-2, compiled with
[voc](https://github.com/vishaps/voc) (Vishap Oberon), of the Ada
`besm2_fmt` in `~/Repos/RPG/Tools/besm2_fmt`. That program is itself a
port of `besm2-rst.scm` from
[besm-tools](https://github.com/tkurtbond/besm-tools). For every input
the Ada version handles, the port's output is byte-for-byte the same
as the Ada binary's. The golden tests check this. Where they differ
(mostly Ada crashes and error messages), see
[ADA-DIFFERENCES.md](ADA-DIFFERENCES.md).

## Example

```yaml
- name: Lieutenant Enyon Boase
  stats:
    - {name: Body, value: 8, points: 8}
    - {name: Mind, value: 6, points: 6}
    - {name: Soul, value: 6, points: 6}
  derived:
    - {name: ACV, value: 9}
  attributes:
    - name: Extra Actions
      level: 1
      points: 4
      details: +1 Extra Action
  defects:
    - {name: "Conditional Ownership: Army ownership", points: -2}
  skills:
    - {name: Law, level: 1, points: 2, specialisations: [Military]}
```

`besm2_fmt -t -s` (terse, with subtotals) gives

```rst
Lieutenant Enyon Boase (22 CP)
------------------------------

**Statistics** (20 CP)  — 
Body 8 (8 CP), Mind 6 (6 CP), Soul 6 (6 CP)

**Derived Values** — ACV 9

**Attributes** (4 CP) — 
Extra Actions 1 (+1 Extra Action. 4 CP)

**Defects** (2 BP) — 
Conditional Ownership: Army ownership (2 BP)

**Skills** (2 SP) — 
Law 1 (Military.  2 SP)
```

A file holds a YAML sequence of entities, and may hold several
`---`-separated documents. Each entity may have `name`, `tagline`,
`description`, `size`, `mecha` (a boolean), `stats`, `derived`,
`attributes`, `defects` and `skills`. Attributes and defects can also
have `enhancements`, `limiters`, `elements`, `effective` and
`details`. `test/data/synthetic-2e.yaml` uses every field.

## Usage

```
besm2_fmt [options] [files...]
```

With no files, standard input is read. Output goes to standard output,
or to the file given by `-o`.

| Format | Option |
|---|---|
| reST grid tables (the default) | |
| terse reST paragraphs | `-t`, `--terse` |
| groff `tbl` in a `.. raw:: ms` block | `-m`, `--raw-ms-tables` |
| h-m-m outline | `-H`, `--hmm` |

If more than one format option is given, the last one wins. Other
options:

- `-s`: show subtotals.
- `-1`: put each entity in one table.
- `-w N`: table width, 25 or more; the default is 60.
- `-u C` and `-U C`: the underline characters for the first entity and
  for the ones after it.
- `-n`: use an ASCII hyphen-minus instead of the Unicode minus sign.
- `-D`: leave out descriptions.
- `-b`, `-i`, `-l`, `-M`, `-p`: emphasis and layout for the terse
  format.
- `-L N`, `-R TEXT`, `-S`: indentation depth, root node and separate
  nodes for h-m-m.

`besm2_fmt -h` lists every option.

Exit status:

- 0 when the run finishes, even if some input was bad. A bad entity is
  reported on standard error, and the rest of its file is skipped.
- 1 for `-h`, or when output can't be written.
- 2 for a mistake on the command line.

## Building

You need:

- voc, by default at `/usr/local/sw/versions/voc/git/bin/voc`
  (override with `VOC=`).
- libfyaml, found through `pkg-config`.
- `ArgParser.Mod` and `Err.Mod` from
  [ArgParser](https://github.com/tkurtbond/ArgParser), installed into
  `OBERON_MODULES` (default `/usr/local/sw/versions/oberon/include`).
- A checkout of olibfyaml at `OLIBFYAML` (default
  `~/Repos/Oberon/olibfyaml`).

```sh
make                # ./besm2_fmt
make test           # unit tests, command-line checks, golden-output tests
make install        # to $(PREFIX)/bin, default ~/local/bin
make uninstall
make rst            # build/*.gen.rst from the test fixtures
make pdf            # build/*.ms.pdf from those, via pandoc and the tkb ms template
make clean          # everything built; make testclean removes only build/
```

`make install` puts the program in `$HOME/local/bin` by default, the
same place as the Ada version. Any Ada `besm2_fmt` already there is
replaced. Set `PREFIX` (and `DESTDIR` for staging) to install
elsewhere.

`make golden` regenerates the golden test files from the Ada binary
and `besm2-rst`. It's needed only when test cases are added.

## Documents

- [AGENTS.md](AGENTS.md): working notes on the build, the tests and
  voc.
- [PLAN.md](PLAN.md): the design of the port, the build order and the
  findings of each step.
- [ADA-DIFFERENCES.md](ADA-DIFFERENCES.md): every known way the Ada
  version differs from the port or is defective.
