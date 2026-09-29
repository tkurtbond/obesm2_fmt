MODULE Besm2Layout; (* Padding, word wrapping, grid-table rows, emphasis *)

(* The Ada BESM2_Fmt.Text_Layout: fixed-width padding, greedy word
   wrap, and the bordered "|...|...|" rows of a reST grid table, which
   besm2-rst.scm builds from SRFI 166's padded, wrapped and columnar.
   The Scheme only ever uses a narrow slice of those -- plain,
   fixed-width, single-font text, with bold and italics as literal "**"
   and "*" in the string -- so this is a small purpose-built module, not
   a general formatting library.

   Rows and separators are written to Besm2Out.  Only the emphasis
   procedures and MinusGlyph depend on Besm2Config. *)

IMPORT Besm2Config, Besm2Out, Besm2Str;

CONST
  LeftAlign* = 0; RightAlign* = 1;

  (* besm2-rst.scm's *num-width*: the widest of "LEVEL", "VALUE" and
     "POINTS" (6), plus the 4 its main always adds for the "**" around
     a bold header cell -- even under -B/--no-bold-head, when the
     header just gets some slack.  Ported as is. *)
  NumWidth* = 10;

TYPE
  String* = Besm2Str.String;

VAR
  unicodeMinus, asciiMinus: String;

(* s padded with blanks to width characters (DisplayLength, not bytes),
   on the right for LeftAlign, on the left for RightAlign.  s is
   returned unchanged if it is already that wide or wider: like SRFI
   166's padded, this never truncates. *)
PROCEDURE Pad*(s: ARRAY OF CHAR; width: LONGINT; align: INTEGER): String;
  VAR b: Besm2Str.Buffer; fill: LONGINT;
BEGIN
  fill := width - Besm2Str.DisplayLength(s);
  Besm2Str.Reset(b);
  IF align = RightAlign THEN Besm2Str.AddRepeat(b, " ", fill) END;
  Besm2Str.Add(b, s);
  IF align = LeftAlign THEN Besm2Str.AddRepeat(b, " ", fill) END;
  RETURN Besm2Str.Get(b)
END Pad;

(* Every whitespace character separates words, newlines included: a
   YAML literal block scalar ("details: |") carries its own line breaks
   into the text, and the real besm2-rst.scm output re-fills them as
   ordinary text (FV2021-Coleopteran-2e.yaml's "Weapon: Rocket Pod"
   attribute).  Printing the newline instead would break the row's
   "|...|" borders -- a bug the Ada port found and fixed. *)
PROCEDURE IsBreak(c: CHAR): BOOLEAN;
BEGIN RETURN (c = " ") OR (c = 0AX) OR (c = 0DX) OR (c = 09X)
END IsBreak;

(* Sets lines to s wrapped greedily to width characters: words
   separated by runs of whitespace, joined by one blank.  A word longer
   than width is not broken; it gets a line of its own and overruns.
   An empty s gives one empty line, not none, since a table row needs
   a line even when its wrapped column is "". *)
PROCEDURE WordWrap*(s: ARRAY OF CHAR; width: LONGINT; VAR lines: Besm2Str.List);
  VAR cur, word: Besm2Str.Buffer; w: String; i, n, curLen, wordLen: LONGINT;
BEGIN
  Besm2Str.Clear(lines);
  Besm2Str.Reset(cur); curLen := 0;
  n := Besm2Str.Length(s); i := 0;
  WHILE i < n DO
    Besm2Str.Reset(word);
    WHILE (i < n) & ~IsBreak(s[i]) DO Besm2Str.AddChar(word, s[i]); INC(i) END;
    (* word may be empty, for leading whitespace: Ada treats it the
       same way, as a word that fits on the current empty line. *)
    w := Besm2Str.Get(word); wordLen := Besm2Str.DisplayLength(w^);
    IF Besm2Str.BufLength(cur) = 0 THEN
      Besm2Str.Add(cur, w^); curLen := wordLen
    ELSIF curLen + 1 + wordLen <= width THEN
      Besm2Str.AddChar(cur, " "); Besm2Str.Add(cur, w^);
      INC(curLen, 1 + wordLen)
    ELSE
      Besm2Str.Append(lines, Besm2Str.Get(cur));
      Besm2Str.Reset(cur); Besm2Str.Add(cur, w^); curLen := wordLen
    END;
    WHILE (i < n) & IsBreak(s[i]) DO INC(i) END
  END;
  Besm2Str.Append(lines, Besm2Str.Get(cur))
END WordWrap;

(* The width of the last, wrapped, column of a row of numColumns
   columns: whatever the fixed-width columns and the borders leave of
   the table width: table width - 2 - (columns - 1) * (NumWidth + 1),
   as besm2-rst.scm's separator-line computes it. *)
PROCEDURE WrapWidth(numColumns: INTEGER): LONGINT;
BEGIN RETURN Besm2Config.tableWidth - 2 - (numColumns - 1) * (NumWidth + 1)
END WrapWidth;

(* Writes one row of a grid table: one or more "|...|...|" lines.  All
   columns but the last are NumWidth characters wide; the last is
   wrapped to the rest of the table width, and on its continuation
   lines the other columns are blank.  besm2-rst.scm's row2 and row3,
   for cols.n = 2 and 3.  Callers apply Hbolding and friends to the
   column text first, as the Scheme callers do. *)
PROCEDURE PutRow*(VAR cols: Besm2Str.List);
  VAR lines: Besm2Str.List; wrap: LONGINT; l, c: INTEGER;
BEGIN
  wrap := WrapWidth(cols.n);
  WordWrap(cols.items[cols.n - 1]^, wrap, lines);
  FOR l := 0 TO lines.n - 1 DO
    Besm2Out.Char("|");
    FOR c := 0 TO cols.n - 2 DO
      IF l = 0 THEN Besm2Out.Str(Pad(cols.items[c]^, NumWidth, LeftAlign))
      ELSE Besm2Out.Repeat(" ", NumWidth)
      END;
      Besm2Out.Char("|")
    END;
    Besm2Out.Str(Pad(lines.items[l]^, wrap, LeftAlign));
    Besm2Out.Char("|"); Besm2Out.Ln
  END
END PutRow;

(* Row2 and Row3 take Strings, not ARRAY OF CHAR, so that a call like
   Row3(Hbolding("VALUE"), ...) needs no variables: voc won't pass a
   dereferenced function result, F()^, as an open array. *)
PROCEDURE Row2*(a, b: String);
  VAR cols: Besm2Str.List;
BEGIN
  Besm2Str.Clear(cols);
  Besm2Str.Append(cols, a); Besm2Str.Append(cols, b);
  PutRow(cols)
END Row2;

PROCEDURE Row3*(a, b, c: String);
  VAR cols: Besm2Str.List;
BEGIN
  Besm2Str.Clear(cols);
  Besm2Str.Append(cols, a); Besm2Str.Append(cols, b); Besm2Str.Append(cols, c);
  PutRow(cols)
END Row3;

(* Writes one "+---+---+...+" line: numColumns - 1 segments of NumWidth
   fill characters, then one taking the rest of the table width.
   besm2-rst.scm's separator-line: sep1/sep2/sep3 with fill "-", and
   headsep2/headsep3 with Besm2Config.headSep. *)
PROCEDURE SeparatorLine*(numColumns: INTEGER; fill: CHAR);
  VAR c: INTEGER;
BEGIN
  Besm2Out.Char("+");
  FOR c := 1 TO numColumns - 1 DO
    Besm2Out.Repeat(fill, NumWidth); Besm2Out.Char("+")
  END;
  Besm2Out.Repeat(fill, WrapWidth(numColumns));
  Besm2Out.Char("+"); Besm2Out.Ln
END SeparatorLine;

(* Writes one "| ... |" line spanning the table: besm2-rst.scm's empty,
   used between sections under -1/--one.  No Ada golden fixture used
   -1, so this was ported by reading the Scheme. *)
PROCEDURE EmptyRow*;
BEGIN
  Besm2Out.Char("|");
  Besm2Out.Repeat(" ", Besm2Config.tableWidth - 2);
  Besm2Out.Char("|"); Besm2Out.Ln
END EmptyRow;

(* ---- Emphasis ---- *)

(* Always "**...**" and "*...*": besm2-rst.scm's bold and italics. *)
PROCEDURE Bold*(s: ARRAY OF CHAR): String;
BEGIN RETURN Besm2Str.Concat3("**", s, "**")
END Bold;

PROCEDURE Italics*(s: ARRAY OF CHAR): String;
BEGIN RETURN Besm2Str.Concat3("*", s, "*")
END Italics;

(* Bold under -b/--bold: besm2-rst.scm's bolding. *)
PROCEDURE Bolding*(s: ARRAY OF CHAR): String;
BEGIN
  IF Besm2Config.bolding THEN RETURN Bold(s) END;
  RETURN Besm2Str.Of(s)
END Bolding;

(* Italic under -i/--italics: besm2-rst.scm's italicizing. *)
PROCEDURE Italicizing*(s: ARRAY OF CHAR): String;
BEGIN
  IF Besm2Config.italicizing THEN RETURN Italics(s) END;
  RETURN Besm2Str.Of(s)
END Italicizing;

(* Bold under -b, else italic under -i: besm2-rst.scm's emphasizing,
   for the names of attributes, defects and skills. *)
PROCEDURE Emphasizing*(s: ARRAY OF CHAR): String;
BEGIN
  IF Besm2Config.bolding THEN RETURN Bold(s)
  ELSIF Besm2Config.italicizing THEN RETURN Italics(s)
  END;
  RETURN Besm2Str.Of(s)
END Emphasizing;

(* Bold unless -B/--no-bold-head: besm2-rst.scm's hbolding, for grid
   table header cells. *)
PROCEDURE Hbolding*(s: ARRAY OF CHAR): String;
BEGIN
  IF Besm2Config.boldHead THEN RETURN Bold(s) END;
  RETURN Besm2Str.Of(s)
END Hbolding;

(* The sign for a negative number this program writes itself: U+2212
   MINUS SIGN, or "-" under -n/--no-unicode-minus.  besm2-rst.scm's
   minus-glyph, with the Ada version's default.  Used for the
   enhancement signs in attribute details (all formats) and the defect
   points and totals of the grid and raw ms formats.  Terse and h-m-m
   write defect points as "N BP", with no sign. *)
PROCEDURE MinusGlyph*(): String;
BEGIN
  IF Besm2Config.unicodeMinus THEN RETURN unicodeMinus END;
  RETURN asciiMinus
END MinusGlyph;

BEGIN
  unicodeMinus := Besm2Str.Of("−");   (* U+2212, UTF-8 E2 88 92 *)
  asciiMinus := Besm2Str.Of("-")
END Besm2Layout.
