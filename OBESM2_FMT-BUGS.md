# obesm2_fmt bugs

Bugs in obesm2_fmt's own code, numbered, newest last. A problem that
comes from the YAML binding goes in that binding's bugs file, and one in
libfyaml itself in the binding's `LIBFYAML-ISSUES.md`; this file records
only how it shows here, with a pointer.

When one is fixed, replace its "Status" with "Fix" and "Verified". When
one turns out not to be a bug, say so in its section rather than
deleting it.


## 1. An undefined alias prints nothing and exits 0

**Symptom.** A file with an alias that has no anchor, or a cyclic
reference, prints nothing, and the program exits with status 0. Nothing
after that document is read. Found 2026-11-16 by checking the programs
that use olibfyaml after obesm2_fmt2's bug 1.

**Repro** (obesm2_fmt at 4042666, as installed 2026-11-02; libfyaml
0.8-9.fc44):

```sh
printf -- '- name: *nope\n' > alias.yaml
obesm2_fmt alias.yaml; echo "rc=$?"     # prints only rc=0
```

`- &a [*a]` (a cyclic reference) does the same.

**Cause.** Not in this program. `ProcessOne` (`src/Besm2Fmt.Mod`) reads
through `FyamlStreams`, which resolves aliases, and the stream ended
quietly with no error: olibfyaml bug 1 (`OLIBFYAML-BUGS.md`), caused by
libfyaml issue 2 (`fy_diag_got_error` isn't set for a resolve failure;
olibfyaml's `LIBFYAML-ISSUES.md`).

**Fix.** In olibfyaml 078daf0 ("FyamlStreams: report a resolve
failure, not a quiet end"): `FyamlStreams` also checks
`fy_parser_get_stream_error`, so a resolve failure is a `ParseError`.
Nothing changed in this program; it needed only a rebuild against the
fixed library, after `make install` in olibfyaml (its modules are used
from the installed copy; see the GNUmakefile).

**Verified** 2026-11-16:

```sh
obesm2_fmt alias.yaml; echo "rc=$?"
# besm2_fmt: alias.yaml:1:10: error: invalid alias
# rc=1
```

`make test` passes, including three cases added to `test/cli.sh`: an
undefined alias, a cyclic reference, and a document before an undefined
alias still written.


## 2. A customizer whose counts-as isn't a scalar halts the program

**Symptom.** A customizer in `enhancements` or `limiters` whose second
item (its counts-as) is a mapping or a sequence stops the program with
status 62 (voc exits with the `ASSERT` code), instead of an error for
the file. Found 2026-11-16 after the same bug in obesm2_fmt2 (its bug
2), whose `Besm2Entities` came from here.

**Repro** (obesm2_fmt at 4042666, as installed 2026-11-02), `enh.yaml`:

```yaml
- name: Good
  stats: [{name: Body, value: 4, points: 8}]
- name: Short
  attributes: [{name: A, level: 1, points: 2, enhancements: [[Foo, {a: 1}]]}]
```

```sh
obesm2_fmt enh.yaml; echo "rc=$?"     # rc=62
```

`limiters: [[Foo, [1]]]` does the same. The Ada besm2_fmt reports

```
besm2_fmt: error processing enh.yaml: /1/attributes/0/enhancements/0/1: not a scalar
```

and exits with status 1.

**Cause.** `Customizer` (`src/Besm2Entities.Mod:398`) called
`part.IntegerValue` on item 1 without checking that it is a scalar.
`Fyaml.Node.IntegerValue` asserts that (`Fyaml.AssertKind`, 62): the
binding treats a call on the wrong kind of node as a programmer error,
so this is a bug here, not in the binding. Item 0 and the applies-to
items go through `Scalar`, which reports "not a scalar".

**Fix.** `Customizer` checks `part.IsScalar()` before
`IntegerValue`, and reports `not a scalar` with the node's path, in the
Ada wording. `test/cli.sh` has two new cases: an enhancement whose
counts-as is a mapping, and a limiter whose counts-as is a sequence.

**Verified** 2026-11-16: the repro gives

```
besm2_fmt: error processing enh.yaml: /1/attributes/0/enhancements/0/1: not a scalar
```

and status 1, and `limiters: [[Foo, [1]]]` gives
`.../limiters/0/1: not a scalar`. `make test` passes.

The same fix is in obesm2_fmt2 and pobesm2_fmt2 (their bug 2) and
besm2_cg_po (its bug 1).
