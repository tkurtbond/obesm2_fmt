MODULE Besm2Fmt; (* besm2_fmt: BESM 2E YAML to reStructuredText *)

(* Oberon-2 port of the Ada besm2_fmt (besm2_fmt_main.adb), itself a
   port of besm2-rst.scm.  See PLAN.md, section 7.

   Of the output formats, only terse is ported so far (PLAN.md, section
   9); the others write each entity as one line, its number and
   name. *)

IMPORT Besm2Cli, Besm2Config, Besm2Entities, Besm2Out, Besm2Str, Besm2Terse,
  Err, Fyaml, FyamlStreams, Out, Platform, SYSTEM;

(* strerror, for an -o/--output file that can't be created. *)
PROCEDURE -AincludeString '#include <string.h>';
PROCEDURE -strerror(e: INTEGER): SYSTEM.ADDRESS "(ADDRESS)strerror((int)e)";

(* The OS's text for error code e, from strerror. *)
PROCEDURE ErrorText(e: Platform.ErrorCode): Besm2Str.String;
  VAR p: SYSTEM.ADDRESS; c: CHAR; b: Besm2Str.Buffer;
BEGIN
  Besm2Str.Reset(b);
  p := strerror(e);
  IF p # 0 THEN
    SYSTEM.GET(p, c);
    WHILE c # 0X DO Besm2Str.AddChar(b, c); INC(p); SYSTEM.GET(p, c) END
  END;
  RETURN Besm2Str.Get(b)
END ErrorText;

(* Reports an error this program found in processing source, in the
   Ada version's words: "besm2_fmt: error processing SOURCE: MESSAGE".
   Output so far is flushed first, so it comes before the error when
   both go to the terminal. *)
PROCEDURE Report(source, msg: ARRAY OF CHAR);
BEGIN
  Besm2Out.Flush;
  Err.String("besm2_fmt: error processing "); Err.String(source); Err.String(": ");
  Err.String(msg); Err.Ln
END Report;

(* Reports an error from olibfyaml.  Its message already names the file,
   gcc style ("FILE:LINE:COLUMN: error: TEXT", one line per error, each
   ending in a newline), so it gets only the program's name in front:
   a deliberate difference from the Ada wording (PLAN.md, section 5). *)
PROCEDURE ReportYaml(err: Fyaml.Error);
BEGIN
  Besm2Out.Flush;
  Err.String("besm2_fmt: "); Err.String(err.msg^)
END ReportYaml;

(* The entities of one document.  count runs on across the documents of
   a file: 1 for the file's first entity, whichever document it is in.
   Each entity is loaded completely before any of it is written, so one
   that fails writes nothing; those before it are already written.
   FALSE after reporting an error, which ends the file, as in the Ada
   version. *)
PROCEDURE ProcessDocument(d: Fyaml.Document; VAR source: ARRAY OF CHAR;
                          VAR count: INTEGER): BOOLEAN;
  VAR root, item: Fyaml.Node; it: Fyaml.ItemIter; e: Besm2Entities.Entity;
    yerr: Fyaml.Error; msg: Besm2Str.String;
BEGIN
  root := d.Root();
  IF (root = NIL) OR ~root.IsSequence() THEN
    msg := Besm2Str.Concat("expected a top-level YAML sequence of entities in ", source);
    Report(source, msg^);
    RETURN FALSE
  END;
  root.Items(it);
  WHILE it.Next(item) DO
    IF ~Besm2Entities.Load(item, e, yerr, msg) THEN
      IF yerr # NIL THEN ReportYaml(yerr) ELSE Report(source, msg^) END;
      RETURN FALSE
    END;
    INC(count);
    CASE Besm2Config.format OF
      Besm2Config.Terse: Besm2Terse.ProcessEntity(e, count)
    ELSE
      (* Stand-in for the formats not ported yet (PLAN.md, section 9). *)
      Besm2Out.Str(Besm2Str.Int(count)); Besm2Out.String(": ");
      IF e.name # NIL THEN Besm2Out.Str(e.name) END;
      Besm2Out.Ln
    END
  END;
  RETURN TRUE
END ProcessDocument;

(* One file, or standard input if stdin.  As besm2-rst.scm's
   process-file: an error ends this file, not the run. *)
PROCEDURE ProcessOne(VAR name: ARRAY OF CHAR; stdin: BOOLEAN);
  VAR s: FyamlStreams.Stream; d: Fyaml.Document; err: Fyaml.Error;
    source: Besm2Str.String; count: INTEGER; ok: BOOLEAN;
BEGIN
  IF stdin THEN source := Besm2Str.Of(Fyaml.stdinName); s := FyamlStreams.OpenStdin(err)
  ELSE source := Besm2Str.Of(name); s := FyamlStreams.OpenFile(name, err)
  END;
  IF s = NIL THEN ReportYaml(err); RETURN END;
  count := 0; ok := TRUE;
  d := s.Next(err);
  WHILE ok & (d # NIL) DO
    ok := ProcessDocument(d, source^, count);
    d.Close;
    IF ok THEN d := s.Next(err) END
  END;
  IF ok & (err # NIL) THEN ReportYaml(err) END;
  s.Close
END ProcessOne;

PROCEDURE ProcessAll;
  VAR i: INTEGER; none: ARRAY 1 OF CHAR;
BEGIN
  IF Besm2Cli.files.n = 0 THEN
    none := ""; ProcessOne(none, TRUE)
  ELSE
    FOR i := 0 TO Besm2Cli.files.n - 1 DO ProcessOne(Besm2Cli.files.items[i]^, FALSE) END
  END
END ProcessAll;

PROCEDURE Main;
  VAR e: Platform.ErrorCode; reason: Besm2Str.String;
BEGIN
  Besm2Cli.Parse;   (* exits with status 2 on a command-line mistake *)
  IF Besm2Cli.helpShown THEN
    (* besm2-rst.scm's usage always exits 1, even for --help. *)
    Out.Flush; Platform.Exit(1)
  END;

  (* The -R/--hmm-root line: once per run, not per entity, and -- as in
     besm2-rst.scm's main, which writes it before redirecting output
     for -o -- always to standard output, even under -o/--output.
     Confirmed against the real besm2-rst binary by the Ada port, and
     kept. *)
  IF Besm2Config.hmmOutput & (Besm2Config.hmmRoot # NIL) THEN
    Besm2Out.Repeat(09X, Besm2Config.hmmDepth);
    Besm2Out.Str(Besm2Config.hmmRoot); Besm2Out.Ln;
    Besm2Out.Flush
  END;

  IF Besm2Config.outputFile # NIL THEN
    e := Besm2Out.ToFile(Besm2Config.outputFile^);
    IF e # 0 THEN
      (* The Ada version dies here with an unhandled Name_Error, status
         1; this reports the same OS reason and status. *)
      Err.String("besm2_fmt: can't create "); Err.String(Besm2Config.outputFile^);
      reason := ErrorText(e); Err.String(": "); Err.String(reason^); Err.Ln;
      Platform.Exit(1)
    END
  END;

  ProcessAll;

  e := Besm2Out.Close();
  IF e # 0 THEN
    reason := ErrorText(e);
    Err.String("besm2_fmt: error writing output: "); Err.String(reason^); Err.Ln;
    Platform.Exit(1)
  END
END Main;

BEGIN
  Main
END Besm2Fmt.
