MODULE Besm2RawMs; (* raw groff tbl tables: -m/--raw-ms-tables *)

(* The Ada BESM2_Fmt.Format_Raw_Ms, a port of besm2-rst.scm's
   process-entity-raw-ms and its process-stat-raw-ms and friends.  The
   name, tagline, description and size are plain reST, as in the grid
   format; the sections are then one groff tbl table in a ".. raw:: ms"
   block, with tbl's own markup ("\fB" bold, "T{"/"T}" text blocks).
   tbl lays out and wraps the columns itself (the "x" column modifier),
   so none of Besm2Layout's column layout is used here. *)

IMPORT Besm2Config, Besm2Entities, Besm2Layout, Besm2Out, Besm2Str;

TYPE
  String = Besm2Str.String;
  Buffer = Besm2Str.Buffer;

CONST
  (* Indents the groff lines into the ".. raw:: ms" block. *)
  RawPrefix = "   ";

(* ---- Output ---- *)

(* RawPrefix, then s, then a newline.  Line("") writes the prefix
   alone, trailing blanks and all, as the Ada version and besm2-rst.scm
   do between sections. *)
PROCEDURE Line(s: ARRAY OF CHAR);
BEGIN Besm2Out.String(RawPrefix); Besm2Out.String(s); Besm2Out.Ln
END Line;

(* troff bold, for the table: besm2-rst.scm's tbold.  Not
   Besm2Layout.Bold, which is reST's "**", used only before the table.
   (besm2-rst.scm also defines titalics, but never calls it.) *)
PROCEDURE Tbold(s: ARRAY OF CHAR): String;
BEGIN
  IF Besm2Str.Length(s) = 0 THEN RETURN Besm2Str.Of(s) END;
  RETURN Besm2Str.Concat3("\fB", s, "\fP")
END Tbold;

(* The cells of a row, joined with tbl's "#" separator; c is NIL for a
   two-column row.  a may be empty, for a row whose first column is
   blank. *)
PROCEDURE Row(a, b, c: String);
  VAR r: Buffer; s: String;
BEGIN
  Besm2Str.Reset(r);
  Besm2Str.Add(r, a^); Besm2Str.AddChar(r, "#"); Besm2Str.Add(r, b^);
  IF c # NIL THEN Besm2Str.AddChar(r, "#"); Besm2Str.Add(r, c^) END;
  s := Besm2Str.Get(r); Line(s^)
END Row;

(* A total row: blank first column, then bold points and bold label. *)
PROCEDURE TotalRow(points: String; label: ARRAY OF CHAR);
BEGIN Row(Besm2Str.Empty(), Tbold(points^), Tbold(label))
END TotalRow;

(* A row whose last cell is a "T{ ... T}" text block, so tbl can wrap
   it; b is NIL for a two-column row. *)
PROCEDURE TextRow(a, b, text: String);
  VAR r: Buffer; s: String;
BEGIN
  Besm2Str.Reset(r);
  Besm2Str.Add(r, a^); Besm2Str.AddChar(r, "#");
  IF b # NIL THEN Besm2Str.Add(r, b^); Besm2Str.AddChar(r, "#") END;
  Besm2Str.Add(r, "T{");
  s := Besm2Str.Get(r); Line(s^);
  Line(text^);
  Line("T}")
END TextRow;

(* The start of a section: ".T&" before every section but the first,
   which gets the "=" rule above the table instead, then the column
   format. *)
PROCEDURE StartSection(format: ARRAY OF CHAR; VAR firstSectionSeen: BOOLEAN);
BEGIN
  IF firstSectionSeen THEN Line(".T&") END;
  Line(format);
  IF ~firstSectionSeen THEN firstSectionSeen := TRUE; Line("=") END
END StartSection;

(* ---- Numbers ---- *)

PROCEDURE Points(n: INTEGER): String;
BEGIN RETURN Besm2Str.Int(n)
END Points;

(* A defect's points, always negative, with MinusGlyph for the sign.
   Inside a tbl text block reST never sees it, so unlike the grid
   format there is no backslash. *)
PROCEDURE DefectPoints(n: INTEGER): String;
  VAR minus, digits: String;
BEGIN
  minus := Besm2Layout.MinusGlyph(); digits := Points(ABS(n));
  RETURN Besm2Str.Concat(minus^, digits^)
END DefectPoints;

(* A total that may be negative, with MinusGlyph for the sign, as
   besm2-rst.scm's points->string (besm-tools commit 5cb3d92). *)
PROCEDURE SignedPoints(n: INTEGER): String;
BEGIN
  IF n < 0 THEN RETURN DefectPoints(n) END;
  RETURN Points(n)
END SignedPoints;

(* ---- Cell text: besm2-rst.scm's process-derived-raw-ms and friends ---- *)

(* s with every line feed made a blank: besm2-rst.scm's
   space-to-newline, misleadingly named (it turns newlines into
   blanks).  The same as Besm2Hmm's AllOneLine: a "details: |" block
   scalar's newline can't be left inside a tbl text block. *)
PROCEDURE SpaceToNewline(s: ARRAY OF CHAR): String;
  VAR b: Buffer; i: LONGINT;
BEGIN
  Besm2Str.Reset(b); i := 0;
  WHILE (i < LEN(s)) & (s[i] # 0X) DO
    IF s[i] = 0AX THEN Besm2Str.AddChar(b, " ") ELSE Besm2Str.AddChar(b, s[i]) END;
    INC(i)
  END;
  RETURN Besm2Str.Get(b)
END SpaceToNewline;

(* besm2-rst.scm's derived-abbreviations, as in Besm2Grid: only the
   grid and raw ms formats expand them. *)
PROCEDURE ExpandDerivedName(name: String): String;
BEGIN
  IF name^ = "ACV" THEN RETURN Besm2Str.Of("Attack Combat Value")
  ELSIF name^ = "DCV" THEN RETURN Besm2Str.Of("Defence Combat Value")
  ELSIF name^ = "DM" THEN RETURN Besm2Str.Of("Damage Multiplier")
  ELSIF name^ = "HP" THEN RETURN Besm2Str.Of("Health Points")
  ELSIF name^ = "EP" THEN RETURN Besm2Str.Of("Energy Points")
  ELSIF name^ = "SV" THEN RETURN Besm2Str.Of("Shock Value")
  ELSIF name^ = "AR" THEN RETURN Besm2Str.Of("Armour Rating")
  END;
  RETURN name
END ExpandDerivedName;

(* "NAME (TEXT)". *)
PROCEDURE Parens(name, text: String): String;
  VAR b: Buffer;
BEGIN
  Besm2Str.Reset(b);
  Besm2Str.Add(b, name^); Besm2Str.Add(b, " ("); Besm2Str.Add(b, text^); Besm2Str.AddChar(b, ")");
  RETURN Besm2Str.Get(b)
END Parens;

(* "NAME (TEXT)", or just NAME if TEXT is empty: for details. *)
PROCEDURE WithParens(name, text: String): String;
BEGIN
  IF Besm2Str.Length(text^) = 0 THEN RETURN name END;
  RETURN Parens(name, text)
END WithParens;

(* "NAME (A, B)", or just NAME if l has no items.  The test is the
   number of items, as in the Ada version and besm2-rst.scm, not the
   joined text: a list of one empty string gives "NAME ()" (PLAN.md,
   step 12). *)
PROCEDURE WithList(name: String; l: Besm2Str.List): String;
BEGIN
  IF l.n = 0 THEN RETURN name END;
  RETURN Parens(name, Besm2Str.Join(l, ", "))
END WithList;

(* ---- ProcessEntity ---- *)

(* Writes e.  entityNo is 1 for the first entity of a file, 2 for the
   second, and so on: entities after the first are underlined with
   -U/--subunderliner's character, if given. *)
PROCEDURE ProcessEntity*(e: Besm2Entities.Entity; entityNo: INTEGER);
  VAR i: INTEGER; underline: CHAR; paragraphSeen, firstSectionSeen: BOOLEAN;
    s: Besm2Entities.Stat; d: Besm2Entities.Derived; a: Besm2Entities.Attribute;
    df: Besm2Entities.Defect; sk: Besm2Entities.Skill;
BEGIN
  paragraphSeen := FALSE; firstSectionSeen := FALSE;

  IF e.name # NIL THEN
    IF (entityNo > 1) & (Besm2Config.subunderliner # 0X) THEN underline := Besm2Config.subunderliner
    ELSE underline := Besm2Config.underliner
    END;
    Besm2Out.Str(e.name); Besm2Out.Ln;
    (* As long as the name in bytes, as in the Ada version. *)
    Besm2Out.Repeat(underline, Besm2Str.Length(e.name^)); Besm2Out.Ln;
    Besm2Out.Ln
  END;

  IF e.tagline # NIL THEN
    paragraphSeen := TRUE;
    Besm2Out.Str(Besm2Layout.Italics(e.tagline^)); Besm2Out.Ln; Besm2Out.Ln
  END;

  IF ~Besm2Config.omitEntityDescription & (e.description # NIL) THEN
    paragraphSeen := TRUE;
    Besm2Out.Str(e.description); Besm2Out.Ln; Besm2Out.Ln;
    IF Besm2Config.pageAfterDescription THEN
      Besm2Out.String(".. raw:: ms"); Besm2Out.Ln; Besm2Out.Ln;
      Besm2Out.String("   .bp"); Besm2Out.Ln; Besm2Out.Ln
    END
  END;

  IF e.size # NIL THEN
    paragraphSeen := TRUE;
    Besm2Out.Str(Besm2Layout.Bold("Size:")); Besm2Out.Char(" "); Besm2Out.Str(e.size);
    Besm2Out.Ln; Besm2Out.Ln
  END;

  Besm2Out.String(".. raw:: ms"); Besm2Out.Ln; Besm2Out.Ln;

  (* groff from here on.  With no paragraph before it, the table gets
     an ".LP" of its own. *)
  IF ~paragraphSeen THEN Line(".LP") END;
  Line(".TS");
  Line("tab(#) ;");

  IF e.stats.n > 0 THEN
    StartSection("c c lx .", firstSectionSeen);
    Row(Tbold("VALUE"), Tbold("POINTS"), Tbold("STAT"));
    FOR i := 0 TO e.stats.n - 1 DO
      s := e.stats.items[i](Besm2Entities.Stat);
      Row(s.value, Points(s.points), s.name)
    END;
    IF Besm2Config.showSubtotals THEN TotalRow(Points(e.statsTotal), "STATS TOTAL") END;
    Line("")
  END;

  IF e.derived.n > 0 THEN
    StartSection("c l sx .", firstSectionSeen);
    Row(Tbold("VALUE"), Tbold("DERIVED VALUE"), NIL);
    FOR i := 0 TO e.derived.n - 1 DO
      d := e.derived.items[i](Besm2Entities.Derived);
      TextRow(d.value, NIL, WithList(ExpandDerivedName(d.name), d.alternatives))
    END;
    Line("")
  END;

  IF e.attributes.n > 0 THEN
    StartSection("c c lx .", firstSectionSeen);
    Row(Tbold("LEVEL"), Tbold("POINTS"), Tbold("ATTRIBUTE"));
    FOR i := 0 TO e.attributes.n - 1 DO
      a := e.attributes.items[i](Besm2Entities.Attribute);
      TextRow(a.level, Points(a.points), WithParens(a.name, SpaceToNewline(a.details^)))
    END;
    IF Besm2Config.showSubtotals THEN TotalRow(Points(e.attributesTotal), "ATTRIBUTES TOTAL") END;
    Line("")
  END;

  IF e.defects.n > 0 THEN
    StartSection("c c lx .", firstSectionSeen);
    Row(Besm2Str.Empty(), Tbold("POINTS"), Tbold("DEFECT"));
    FOR i := 0 TO e.defects.n - 1 DO
      df := e.defects.items[i](Besm2Entities.Defect);
      TextRow(Besm2Str.Empty(), DefectPoints(df.points), WithParens(df.name, SpaceToNewline(df.details^)))
    END;
    IF Besm2Config.showSubtotals THEN TotalRow(SignedPoints(e.defectsTotal), "DEFECTS TOTAL") END;
    Line("")
  END;

  IF e.skills.n > 0 THEN
    StartSection("c c lx .", firstSectionSeen);
    Row(Tbold("LEVEL"), Tbold("POINTS"), Tbold("SKILL"));
    FOR i := 0 TO e.skills.n - 1 DO
      sk := e.skills.items[i](Besm2Entities.Skill);
      TextRow(sk.level, Points(sk.points), WithList(sk.name, sk.specialisations))
    END;
    IF Besm2Config.showSubtotals THEN TotalRow(Points(e.skillsTotal), "SKILL POINTS TOTAL") END;
    Line("")
  END;

  (* The total row has three columns, so it needs a format of its own
     when there was no section, or the last was the derived values'
     two. *)
  IF ~firstSectionSeen
     OR (e.derived.n > 0) & (e.attributes.n = 0) & (e.defects.n = 0) & (e.skills.n = 0) THEN
    StartSection("c c lx .", firstSectionSeen)
  END;
  TotalRow(SignedPoints(e.entityTotal), "TOTAL");
  Line("=");
  Line(".TE");
  (* The blank line ends the raw block before the next entity's name. *)
  Besm2Out.Ln
END ProcessEntity;

END Besm2RawMs.
