MODULE TestLayout; (* Besm2Layout, without YAML *)

(* A port of the Ada test/test_text_layout.adb (PLAN.md, section 8),
   check for check and in the same order, plus a few for the Oberon
   port's own Row2 and EmptyRow.  PutRow and SeparatorLine are checked
   against the real grid-table fragment of enyon-boase-2e's output,
   captured by sending Besm2Out to a file and reading it back.  Run
   from obj/, where the capture files go.

   Each capture has its own file: Files.Old returns the File it cached
   the first time it saw a file (by inode), with its old buffers, and
   Besm2Out rewriting the file in place (O_TRUNC) keeps the inode.
   Reading a rewritten capture with Files gave the first capture's
   lines again (confirmed; Files.Close doesn't drop the cache entry). *)

IMPORT Besm2Config, Besm2Layout, Besm2Out, Besm2Str, Check, Files;

CONST
  Left = Besm2Layout.LeftAlign; Right = Besm2Layout.RightAlign;

VAR
  lines: ARRAY 16 OF Besm2Str.String;
  nlines: INTEGER;
  rocket, rocketBlock, expected: ARRAY 256 OF CHAR;
  s: Besm2Str.String;

PROCEDURE Is(s: Besm2Str.String; t: ARRAY OF CHAR): BOOLEAN;
BEGIN RETURN (s # NIL) & (s^ = t)
END Is;

(* s, then n blanks, then the closing "|" of a table row. *)
PROCEDURE Bordered(s: ARRAY OF CHAR; n: INTEGER): Besm2Str.String;
  VAR b: Besm2Str.Buffer;
BEGIN
  Besm2Str.Reset(b); Besm2Str.Add(b, s); Besm2Str.AddRepeat(b, " ", n); Besm2Str.AddChar(b, "|");
  RETURN Besm2Str.Get(b)
END Bordered;

(* Is, for an expected String built by a function (see Besm2Out.Str). *)
PROCEDURE Same(s, t: Besm2Str.String): BOOLEAN;
BEGIN RETURN (s # NIL) & (t # NIL) & (s^ = t^)
END Same;

(* The lines of text joined with sep, as the Ada test's Joined. *)
PROCEDURE Wrapped(text: ARRAY OF CHAR; width: LONGINT; sep: ARRAY OF CHAR): Besm2Str.String;
  VAR l: Besm2Str.List;
BEGIN
  Besm2Layout.WordWrap(text, width, l);
  RETURN Besm2Str.Join(l, sep)
END Wrapped;

(* Reads the capture file into lines[0 .. nlines-1], without their line
   feeds. *)
PROCEDURE ReadCapture(name: ARRAY OF CHAR);
  VAR f: Files.File; r: Files.Rider; c: CHAR; b: Besm2Str.Buffer;
BEGIN
  nlines := 0;
  f := Files.Old(name);
  IF f = NIL THEN RETURN END;
  Files.Set(r, f, 0); Besm2Str.Reset(b);
  Files.Read(r, c);
  WHILE ~r.eof DO
    IF c = 0AX THEN
      IF nlines < LEN(lines) THEN lines[nlines] := Besm2Str.Get(b); INC(nlines) END;
      Besm2Str.Reset(b)
    ELSE
      Besm2Str.AddChar(b, c)
    END;
    Files.Read(r, c)
  END;
  Files.Close(f)
END ReadCapture;

(* Output written between StartCapture(name) and EndCapture(name)
   goes to the file name and then into lines. *)
PROCEDURE StartCapture(name: ARRAY OF CHAR);
BEGIN
  Check.Check(Besm2Out.ToFile(name) = 0, "Besm2Out.ToFile creates the capture file")
END StartCapture;

PROCEDURE EndCapture(name: ARRAY OF CHAR);
BEGIN
  Check.Check(Besm2Out.Close() = 0, "Besm2Out.Close writes and closes it");
  ReadCapture(name)
END EndCapture;

PROCEDURE Line(i: INTEGER): Besm2Str.String;
BEGIN
  IF i < nlines THEN RETURN lines[i] END;
  RETURN NIL
END Line;

BEGIN
  (* ---- DisplayLength ---- *)
  Check.Check(Besm2Str.DisplayLength("Body") = 4, "DisplayLength of plain ASCII");
  Check.Check(Besm2Str.DisplayLength("“") = 1, "DisplayLength of a 3-byte UTF-8 char (curly quote)");
  Check.Check(Besm2Str.DisplayLength("Shots ×2") = 8,
    "DisplayLength of a 2-byte UTF-8 char (multiplication sign) in context");

  (* ---- Pad ---- *)
  Check.Check(Is(Besm2Layout.Pad("8", 10, Left), "8         "), "Pad left-aligns and fills with spaces");
  Check.Check(Is(Besm2Layout.Pad("8", 10, Right), "         8"), "Pad right-aligns on request");
  Check.Check(Is(Besm2Layout.Pad("POINTS", 6, Left), "POINTS"),
    "Pad passes through unchanged text already at Width");
  Check.Check(Is(Besm2Layout.Pad("ATTRIBUTES TOTAL", 6, Left), "ATTRIBUTES TOTAL"),
    "Pad never truncates text already over Width");
  Check.Check(Is(Besm2Layout.Pad("“ok", 4, Left), "“ok "),
    "Pad counts UTF-8 codepoints, not bytes, toward Width");

  (* ---- WordWrap ---- *)
  Check.Check(Is(Wrapped("", 10, "|"), ""), "WordWrap of an empty string yields one empty line");
  Check.Check(Is(Wrapped("Body", 36, "|"), "Body"), "WordWrap of short text yields one line unchanged");
  rocket := "Weapon: Rocket Pod (Damage 45, Auto-fire, Area Effect, Limited Shots ×2 [3 shots], Stoppable)";
  expected := "Weapon: Rocket Pod (Damage 45,|Auto-fire, Area Effect, Limited|Shots ×2 [3 shots], Stoppable)";
  Check.Check(Is(Wrapped(rocket, 36, "|"), expected),
    'WordWrap greedily fills lines on space boundaries -- matches the golden "Weapon: Rocket Pod" attribute wrap at width 36');
  s := Besm2Str.Concat3("Weapon: Rocket Pod (Damage 45, Auto-fire, Area Effect, Limited Shots ×2 [3 shots],",
                        0AX, "Stoppable)");
  COPY(s^, rocketBlock);
  Check.Check(Is(Wrapped(rocketBlock, 36, "|"), expected),
    'WordWrap treats an embedded newline (from a "details: |" YAML block scalar) as a word break, not literal content');
  Check.Check(Is(Wrapped("Supercalifragilisticexpialidocious", 5, "|"), "Supercalifragilisticexpialidocious"),
    "WordWrap never breaks a single word longer than Width");
  Check.Check(Is(Wrapped("  a   b  ", 10, "|"), "a b"),
    "WordWrap collapses runs of whitespace and drops leading and trailing ones");

  (* ---- Bold / Italics / Bolding / Italicizing / Emphasizing / Hbolding ---- *)
  Check.Check(Is(Besm2Layout.Bold("STAT"), "**STAT**"), "Bold always wraps in **");
  Check.Check(Is(Besm2Layout.Italics("tagline"), "*tagline*"), "Italics always wraps in *");

  Check.Check(~Besm2Config.bolding & Is(Besm2Layout.Bolding("x"), "x"),
    "Bolding off by default leaves text unchanged");
  Besm2Config.bolding := TRUE;
  Check.Check(Is(Besm2Layout.Bolding("x"), "**x**"), "Bolding wraps in ** once -b/--bold is set");
  Check.Check(Is(Besm2Layout.Emphasizing("x"), "**x**"), "Emphasizing prefers Bolding over Italicizing");
  Besm2Config.bolding := FALSE;

  Check.Check(~Besm2Config.italicizing & Is(Besm2Layout.Italicizing("x"), "x"),
    "Italicizing off by default leaves text unchanged");
  Besm2Config.italicizing := TRUE;
  Check.Check(Is(Besm2Layout.Italicizing("x"), "*x*"), "Italicizing wraps in * once -i/--italics is set");
  Check.Check(Is(Besm2Layout.Emphasizing("x"), "*x*"), "Emphasizing falls back to Italicizing when Bolding is off");
  Besm2Config.italicizing := FALSE;
  Check.Check(Is(Besm2Layout.Emphasizing("x"), "x"), "Emphasizing leaves text unchanged when neither flag is set");

  Check.Check(Besm2Config.boldHead & Is(Besm2Layout.Hbolding("VALUE"), "**VALUE**"),
    "Hbolding is on by default (-B/--no-bold-head not given)");
  Besm2Config.boldHead := FALSE;
  Check.Check(Is(Besm2Layout.Hbolding("VALUE"), "VALUE"),
    "Hbolding leaves text unchanged once -B/--no-bold-head is set");
  Besm2Config.boldHead := TRUE;

  (* ---- MinusGlyph: U+2212 (E2 88 92) by default, "-" under -n ---- *)
  Check.Check(Besm2Config.unicodeMinus & Same(Besm2Layout.MinusGlyph(), Besm2Str.Concat3(0E2X, 88X, 92X)),
    "MinusGlyph is Unicode MINUS SIGN (U+2212) by default (-n not given)");
  Besm2Config.unicodeMinus := FALSE;
  Check.Check(Is(Besm2Layout.MinusGlyph(), "-"), "MinusGlyph is ASCII hyphen-minus once -n/--no-unicode-minus is set");
  Besm2Config.unicodeMinus := TRUE;

  (* ---- PutRow / SeparatorLine, against the golden STAT table of
     enyon-boase-2e (table width 60, NumWidth 10) ---- *)
  StartCapture("TestLayout-stat.capture");
  Besm2Layout.SeparatorLine(3, "-");
  Besm2Layout.SeparatorLine(3, "=");
  Besm2Layout.Row3(Besm2Layout.Hbolding("VALUE"), Besm2Layout.Hbolding("POINTS"),
                   Besm2Layout.Hbolding("STAT"));
  Besm2Layout.Row3(Besm2Str.Of("8"), Besm2Str.Of("8"), Besm2Str.Of("Body"));
  EndCapture("TestLayout-stat.capture");
  Check.Check(Is(Line(0), "+----------+----------+------------------------------------+"),
    "SeparatorLine(3) matches the golden STAT table's '-' border");
  Check.Check(Is(Line(1), "+==========+==========+====================================+"),
    "SeparatorLine(3, '=') matches the golden STAT table's header border");
  Check.Check(Is(Line(2), "|**VALUE** |**POINTS**|**STAT**                            |"),
    "PutRow of the hbolded header matches the golden STAT header row");
  Check.Check(Is(Line(3), "|8         |8         |Body                                |"),
    "PutRow of a data row matches the golden STAT data row");
  Check.Check(nlines = 4, "nothing else was written");

  (* ---- Not in the Ada test: a wrapped two-column row, and EmptyRow ---- *)
  StartCapture("TestLayout-row2.capture");
  Besm2Layout.Row2(Besm2Str.Of("9"),
                   Besm2Str.Of("Attack Combat Value, and some more words to wrap it over two lines"));
  Besm2Layout.EmptyRow;
  EndCapture("TestLayout-row2.capture");
  Check.Check(Same(Line(0), Bordered("|9         |Attack Combat Value, and some more words to", 47 - 43)),
    "Row2 wraps its last column to the rest of the width (47)");
  Check.Check(Same(Line(1), Bordered("|          |wrap it over two lines", 47 - 22)),
    "Row2's continuation line is blank in the other column");
  Check.Check(Same(Line(2), Bordered("|", 58)),
    "EmptyRow spans the table width");

  Check.Summary
END TestLayout.
