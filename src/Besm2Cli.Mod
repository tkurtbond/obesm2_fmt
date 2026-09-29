MODULE Besm2Cli; (* The command line: options into Besm2Config, file names into files *)

(* The Ada BESM2_Fmt.Cli, a port of besm2-rst.scm's
   +command-line-options+, on ArgParser.  The options are added in the
   Ada order, with its descriptions, so the usage lists them the same
   way (its layout is ArgParser's, not Ada arg_parser's).

   ArgParser has no options that just set a variable (the Ada
   Make_Set_Boolean_True_Option and friends), so each option has its own
   handler.  Oberon has no closures, so the handlers are module-level
   procedures setting Besm2Config's variables. *)

IMPORT ArgParser, Besm2Config, Besm2Str, Err, Out, Platform;

VAR
  (* The file names on the command line, in order.  None means
     standard input, as in besm2-rst.scm. *)
  files-: Besm2Str.List;

  (* -h/--help was given: the usage has been written, and parsing
     stopped there.  The caller exits with status 1, as besm2-rst.scm's
     usage always does, even for --help. *)
  helpShown-: BOOLEAN;

  parser: ArgParser.Parser;

(* -u/--underliner and -U/--subunderliner take one character.  Anything
   else is an error, with ArgParser's status for command-line mistakes.
   (The Ada version prints its message but then carries on, with status
   0, processing the files named so far or reading standard input; its
   main's handler for this very error exits 2, so that is taken to be
   the intent.  PLAN.md, step 3.) *)
PROCEDURE OneChar(VAR arg: ARRAY OF CHAR; names: ARRAY OF CHAR; VAR c: CHAR);
BEGIN
  IF Besm2Str.Length(arg) # 1 THEN
    Out.Flush;
    Err.String("besm2_fmt: "); Err.String(names);
    Err.String(' takes exactly one character, got "'); Err.String(arg); Err.String('"'); Err.Ln;
    Platform.Exit(ArgParser.UsageErrorStatus)
  END;
  c := arg[0]
END OneChar;

(* ---- Handlers, in option order ---- *)

PROCEDURE DoOne(): BOOLEAN;
BEGIN
  Besm2Config.oneTable := TRUE;
  (* Repeated header-separator lines don't bother pandoc, but in HTML
     output they make the first table's header look like the only one
     when there is really just one table. *)
  Besm2Config.headSep := "-";
  RETURN TRUE
END DoOne;

PROCEDURE DoNoBoldHead(): BOOLEAN;
BEGIN Besm2Config.boldHead := FALSE; RETURN TRUE
END DoNoBoldHead;

PROCEDURE DoBold(): BOOLEAN;
BEGIN Besm2Config.bolding := TRUE; RETURN TRUE
END DoBold;

PROCEDURE DoOmitDescription(): BOOLEAN;
BEGIN Besm2Config.omitEntityDescription := TRUE; RETURN TRUE
END DoOmitDescription;

PROCEDURE DoDebug(): BOOLEAN;
BEGIN Besm2Config.debugging := TRUE; RETURN TRUE
END DoDebug;

PROCEDURE DoHmm(): BOOLEAN;
BEGIN Besm2Config.format := Besm2Config.Hmm; Besm2Config.hmmOutput := TRUE; RETURN TRUE
END DoHmm;

PROCEDURE DoHmmDepth(val: LONGINT): BOOLEAN;
BEGIN Besm2Config.hmmDepth := SHORT(val); RETURN TRUE
END DoHmmDepth;

PROCEDURE DoHmmRoot(VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN Besm2Config.hmmRoot := Besm2Str.Of(arg); RETURN TRUE
END DoHmmRoot;

PROCEDURE DoHmmSeparate(): BOOLEAN;
BEGIN Besm2Config.hmmSeparate := TRUE; RETURN TRUE
END DoHmmSeparate;

PROCEDURE DoHelp(): BOOLEAN;
BEGIN parser.Usage; helpShown := TRUE; RETURN FALSE
END DoHelp;

PROCEDURE DoItalics(): BOOLEAN;
BEGIN Besm2Config.italicizing := TRUE; RETURN TRUE
END DoItalics;

PROCEDURE DoLevel(): BOOLEAN;
BEGIN Besm2Config.level := TRUE; RETURN TRUE
END DoLevel;

PROCEDURE DoEmDash(): BOOLEAN;
BEGIN Besm2Config.emDash := TRUE; RETURN TRUE
END DoEmDash;

PROCEDURE DoRawMs(): BOOLEAN;
BEGIN Besm2Config.format := Besm2Config.RawMs; RETURN TRUE
END DoRawMs;

PROCEDURE DoNoUnicodeMinus(): BOOLEAN;
BEGIN Besm2Config.unicodeMinus := FALSE; RETURN TRUE
END DoNoUnicodeMinus;

PROCEDURE DoOutput(VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN Besm2Config.outputFile := Besm2Str.Of(arg); RETURN TRUE
END DoOutput;

PROCEDURE DoPage(): BOOLEAN;
BEGIN Besm2Config.pageAfterDescription := TRUE; RETURN TRUE
END DoPage;

PROCEDURE DoSubtotals(): BOOLEAN;
BEGIN Besm2Config.showSubtotals := TRUE; RETURN TRUE
END DoSubtotals;

PROCEDURE DoTerse(): BOOLEAN;
BEGIN Besm2Config.format := Besm2Config.Terse; RETURN TRUE
END DoTerse;

PROCEDURE DoSubunderliner(VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN OneChar(arg, "-U/--subunderliner", Besm2Config.subunderliner); RETURN TRUE
END DoSubunderliner;

PROCEDURE DoUnderliner(VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN OneChar(arg, "-u/--underliner", Besm2Config.underliner); RETURN TRUE
END DoUnderliner;

PROCEDURE DoWidth(val: LONGINT): BOOLEAN;
BEGIN Besm2Config.tableWidth := SHORT(val); RETURN TRUE
END DoWidth;

PROCEDURE DoArgument(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN Besm2Str.Append(files, Besm2Str.Of(arg)); RETURN TRUE
END DoArgument;

(* ---- Parse ---- *)

PROCEDURE Opt(o: ArgParser.Option);
BEGIN parser.AddOption(o)
END Opt;

(* Parses the command line into Besm2Config and files.  A mistake on the
   command line ends the program with ArgParser.UsageErrorStatus (2),
   from ArgParser or OneChar.  Check helpShown afterwards. *)
PROCEDURE Parse*;
BEGIN
  Opt(ArgParser.MakeOption("1", "one", "Use only one table.", DoOne));
  Opt(ArgParser.MakeOption("B", "no-bold-head",
    "Turns OFF bolding of headers in plain reST output.", DoNoBoldHead));
  Opt(ArgParser.MakeOption("b", "bold",
    "Turn on bolding of names and levels of attributes, defects, and skills in terse mode. Overrides italicizing (-i/--italics).",
    DoBold));
  Opt(ArgParser.MakeOption("D", "omit-description", "Omit the entity description.", DoOmitDescription));
  Opt(ArgParser.MakeOption("d", "debug", "Turn on debugging.", DoDebug));
  Opt(ArgParser.MakeOption("H", "hmm", "Output in h-m-m format.", DoHmm));
  Opt(ArgParser.MakeIntOption("L", "hmm-depth", "Depth (Level) of h-m-m output.",
    DoHmmDepth, 0, MAX(INTEGER)));
  Opt(ArgParser.MakeStringOption("R", "hmm-root", "Text for root node of h-m-m output.", DoHmmRoot));
  Opt(ArgParser.MakeOption("S", "hmm-separate", "Output subitems as separate h-m-m nodes.", DoHmmSeparate));
  Opt(ArgParser.MakeOption("h", "help", "Display this text.", DoHelp));
  Opt(ArgParser.MakeOption("i", "italics",
    "Turn on italicizing of names and levels of attributes and defects in terse mode.", DoItalics));
  Opt(ArgParser.MakeOption("l", "level",
    'Output the word "Level" before the level number in terse mode.', DoLevel));
  Opt(ArgParser.MakeOption("M", "em-dash",
    "Separate the attribute name and the level with an em dash in terse mode.", DoEmDash));
  Opt(ArgParser.MakeOption("m", "raw-ms-tables", "Use groff tbl output in a raw ms block.", DoRawMs));
  Opt(ArgParser.MakeOption("n", "no-unicode-minus",
    "Turns OFF Unicode MINUS SIGN (U+2212) for negative numbers, reverting to ASCII hyphen-minus.",
    DoNoUnicodeMinus));
  Opt(ArgParser.MakeStringOption("o", "output", "Output file.", DoOutput));
  Opt(ArgParser.MakeOption("p", "page", "Page after description. (Only for ms output!)", DoPage));
  Opt(ArgParser.MakeOption("s", "subtotals", "Show subtotals for stats, attributes, and defects.", DoSubtotals));
  Opt(ArgParser.MakeOption("t", "terse", "Use terse output.", DoTerse));
  Opt(ArgParser.MakeStringOption("U", "subunderliner",
    "Entities after the first are subentities, and use a different character for underlining the subheader.",
    DoSubunderliner));
  Opt(ArgParser.MakeStringOption("u", "underliner", "Character to use for underlining the header.", DoUnderliner));
  (* 25 at least: a narrower table leaves no room for the wrapped column
     of a three-column row.  The Ada version accepts 1 and then fails on
     the first such row, with status 2 (PLAN.md, section 5). *)
  Opt(ArgParser.MakeIntOption("w", "width", "Width of table in characters.", DoWidth, 25, MAX(INTEGER)));
  parser.ParseArguments(1)
END Parse;

BEGIN
  Besm2Str.Clear(files);
  helpShown := FALSE;
  parser := ArgParser.NewParser("besm2_fmt [options] [files...]", DoArgument)
END Besm2Cli.
