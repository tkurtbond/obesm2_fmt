MODULE Besm2Fmt; (* besm2_fmt: BESM 2E YAML to reStructuredText *)

(* Oberon-2 port of the Ada besm2_fmt, itself a port of besm2-rst.scm.
   See PLAN.md.

   For now a stub (PLAN.md, section 9, step 1): it imports ArgParser
   and FyamlStreams so that building it proves the whole toolchain --
   the Args shim, ArgParser, olibfyaml and libfyaml -- links under -OC.
   It counts the top-level items of each document of each file named on
   the command line. *)

IMPORT ArgParser, Err, Fyaml, FyamlStreams, Out;

VAR
  parser: ArgParser.Parser;

PROCEDURE CountFile(VAR path: ARRAY OF CHAR);
  VAR s: FyamlStreams.Stream; d: Fyaml.Document; root: Fyaml.Node;
    err: Fyaml.Error;
BEGIN
  s := FyamlStreams.OpenFile(path, err);
  IF s = NIL THEN Err.String(err.msg^); RETURN END;
  d := s.Next(err);
  WHILE d # NIL DO
    root := d.Root();
    Out.String(path); Out.String(": ");
    IF (root # NIL) & root.IsSequence() THEN
      Out.Int(root.Length(), 0); Out.String(" entities")
    ELSE
      Out.String("not a sequence")
    END;
    Out.Ln;
    d.Close;
    d := s.Next(err)
  END;
  IF err # NIL THEN Err.String(err.msg^) END;
  s.Close
END CountFile;

PROCEDURE DoArgument(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  CountFile(arg);
  RETURN TRUE
END DoArgument;

PROCEDURE DoHelp(): BOOLEAN;
BEGIN
  parser.Usage;
  RETURN FALSE
END DoHelp;

BEGIN
  parser := ArgParser.NewParser("besm2_fmt [options] [files...]", DoArgument);
  parser.AddOption(ArgParser.MakeOption("h", "help", "Display this text.", DoHelp));
  parser.ParseArguments(1)
END Besm2Fmt.
