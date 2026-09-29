MODULE Besm2Grid; (* reST grid tables: the default format *)

(* The Ada BESM2_Fmt.Format_Grid, a port of besm2-rst.scm's
   process-entity and its process-stat and friends: each section of an
   entity is a reST grid table, laid out by Besm2Layout.  Row2, Row3,
   Sep2 and so on match besm2-rst.scm's helpers of the same names, so
   this reads next to process-entity with little translation. *)

IMPORT Besm2Config, Besm2Entities, Besm2Layout, Besm2Out, Besm2Str;

TYPE
  String = Besm2Str.String;
  Buffer = Besm2Str.Buffer;

VAR
  empty: String;

(* ---- besm2-rst.scm's row and separator helpers ---- *)

PROCEDURE Row2(a, b: String);
BEGIN Besm2Layout.Row2(a, b)
END Row2;

PROCEDURE Row3(a, b, c: String);
BEGIN Besm2Layout.Row3(a, b, c)
END Row3;

PROCEDURE Sep2;
BEGIN Besm2Layout.SeparatorLine(2, "-")
END Sep2;

PROCEDURE Sep3;
BEGIN Besm2Layout.SeparatorLine(3, "-")
END Sep3;

PROCEDURE Headsep2;
BEGIN Besm2Layout.SeparatorLine(2, Besm2Config.headSep)
END Headsep2;

PROCEDURE Headsep3;
BEGIN Besm2Layout.SeparatorLine(3, Besm2Config.headSep)
END Headsep3;

(* After a section: a row of the one table under -1/--one, else a blank
   line between tables. *)
PROCEDURE EmptyOrBlankLine;
BEGIN
  IF Besm2Config.oneTable THEN Besm2Layout.EmptyRow ELSE Besm2Out.Ln END
END EmptyOrBlankLine;

(* Hbolding of text, and of a number, for header and total cells. *)
PROCEDURE H(s: ARRAY OF CHAR): String;
BEGIN RETURN Besm2Layout.Hbolding(s)
END H;

PROCEDURE HS(s: String): String;
BEGIN RETURN Besm2Layout.Hbolding(s^)
END HS;

(* ---- Numbers ---- *)

PROCEDURE Points(n: INTEGER): String;
BEGIN RETURN Besm2Str.Int(n)
END Points;

(* A defect's points, always negative, with a backslash before the
   sign, since reST would otherwise take a leading "-" for a bullet.
   besm2-rst.scm's process-defect adds the backslash whatever the sign,
   and so does this.  The sign is MinusGlyph, not AddInt's "-". *)
PROCEDURE DefectPoints(n: INTEGER): String;
  VAR b: Buffer; minus: String;
BEGIN
  Besm2Str.Reset(b);
  minus := Besm2Layout.MinusGlyph();
  Besm2Str.AddChar(b, "\"); Besm2Str.Add(b, minus^); Besm2Str.AddInt(b, ABS(n));
  RETURN Besm2Str.Get(b)
END DefectPoints;

(* A total that may be negative: the defects total, and the entity
   total when defects outweigh the rest.  With MinusGlyph for the sign,
   as besm2-rst.scm's points->string (besm-tools commit 5cb3d92). *)
PROCEDURE SignedPoints(n: INTEGER): String;
  VAR minus, digits: String;
BEGIN
  IF n < 0 THEN
    minus := Besm2Layout.MinusGlyph(); digits := Points(ABS(n));
    RETURN Besm2Str.Concat(minus^, digits^)
  END;
  RETURN Points(n)
END SignedPoints;

(* ---- Cell text: besm2-rst.scm's process-derived and friends ---- *)

(* besm2-rst.scm's derived-abbreviations.  Only the grid and raw ms
   formats expand them; the terse output keeps "ACV" and so on. *)
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

(* "NAME (TEXT)", or just NAME if TEXT is empty. *)
PROCEDURE WithParens(name, text: String): String;
  VAR b: Buffer;
BEGIN
  IF Besm2Str.Length(text^) = 0 THEN RETURN name END;
  Besm2Str.Reset(b);
  Besm2Str.Add(b, name^); Besm2Str.Add(b, " ("); Besm2Str.Add(b, text^); Besm2Str.AddChar(b, ")");
  RETURN Besm2Str.Get(b)
END WithParens;

PROCEDURE DerivedDescription(d: Besm2Entities.Derived): String;
BEGIN RETURN WithParens(ExpandDerivedName(d.name), Besm2Str.Join(d.alternatives, ", "))
END DerivedDescription;

PROCEDURE SkillDescription(s: Besm2Entities.Skill): String;
BEGIN RETURN WithParens(s.name, Besm2Str.Join(s.specialisations, ", "))
END SkillDescription;

(* ---- ProcessEntity ---- *)

(* Writes e.  entityNo is 1 for the first entity of a file, 2 for the
   second, and so on: entities after the first are underlined with
   -U/--subunderliner's character, if given. *)
PROCEDURE ProcessEntity*(e: Besm2Entities.Entity; entityNo: INTEGER);
  VAR i: INTEGER; underline: CHAR; s: Besm2Entities.Stat; d: Besm2Entities.Derived;
    a: Besm2Entities.Attribute; df: Besm2Entities.Defect; sk: Besm2Entities.Skill;
BEGIN
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
    Besm2Out.Str(Besm2Layout.Italics(e.tagline^)); Besm2Out.Ln; Besm2Out.Ln
  END;

  IF ~Besm2Config.omitEntityDescription & (e.description # NIL) THEN
    Besm2Out.Str(e.description); Besm2Out.Ln; Besm2Out.Ln
  END;

  IF e.size # NIL THEN
    Besm2Out.Str(Besm2Layout.Bold("Size:")); Besm2Out.Char(" "); Besm2Out.Str(e.size);
    Besm2Out.Ln; Besm2Out.Ln
  END;

  IF e.stats.n > 0 THEN
    Sep3;
    Row3(H("VALUE"), H("POINTS"), H("STAT"));
    Headsep3;
    FOR i := 0 TO e.stats.n - 1 DO
      s := e.stats.items[i](Besm2Entities.Stat);
      Row3(s.value, Points(s.points), s.name);
      Sep3
    END;
    IF Besm2Config.showSubtotals THEN
      Row3(empty, HS(Points(e.statsTotal)), H("STATS TOTAL"));
      Sep3
    END;
    EmptyOrBlankLine
  END;

  IF e.derived.n > 0 THEN
    Sep2;
    Row2(H("VALUE"), H("DERIVED VALUE"));
    Headsep2;
    FOR i := 0 TO e.derived.n - 1 DO
      d := e.derived.items[i](Besm2Entities.Derived);
      Row2(d.value, DerivedDescription(d));
      Sep2
    END;
    EmptyOrBlankLine
  END;

  IF e.attributes.n > 0 THEN
    Sep3;
    Row3(H("LEVEL"), H("POINTS"), H("ATTRIBUTE"));
    Headsep3;
    FOR i := 0 TO e.attributes.n - 1 DO
      a := e.attributes.items[i](Besm2Entities.Attribute);
      Row3(a.level, Points(a.points), WithParens(a.name, a.details));
      Sep3
    END;
    IF Besm2Config.showSubtotals THEN
      Row3(empty, HS(Points(e.attributesTotal)), H("ATTRIBUTES TOTAL"));
      Sep3
    END;
    EmptyOrBlankLine
  END;

  IF e.defects.n > 0 THEN
    Sep3;
    Row3(empty, H("POINTS"), H("DEFECT"));
    Headsep3;
    FOR i := 0 TO e.defects.n - 1 DO
      df := e.defects.items[i](Besm2Entities.Defect);
      Row3(empty, DefectPoints(df.points), WithParens(df.name, df.details));
      Sep3
    END;
    IF Besm2Config.showSubtotals THEN
      Row3(empty, HS(SignedPoints(e.defectsTotal)), H("DEFECTS TOTAL"));
      Sep3
    END;
    EmptyOrBlankLine
  END;

  IF e.skills.n > 0 THEN
    Sep3;
    Row3(H("LEVEL"), H("POINTS"), H("SKILL"));
    Headsep3;
    FOR i := 0 TO e.skills.n - 1 DO
      sk := e.skills.items[i](Besm2Entities.Skill);
      Row3(sk.level, Points(sk.points), SkillDescription(sk));
      Sep3
    END;
    (* Unlike the other subtotals, always shown: besm2-rst.scm's
       process-entity doesn't check *show-subtotals* here. *)
    Row3(empty, HS(Points(e.skillsTotal)), H("SKILL POINTS TOTAL"));
    Sep3;
    EmptyOrBlankLine
  END;

  (* The grand total: always shown, and followed by a plain blank line
     even under -1/--one, as in besm2-rst.scm. *)
  Sep3;
  Row3(empty, HS(SignedPoints(e.entityTotal)), H("TOTAL"));
  Sep3;
  Besm2Out.Ln
END ProcessEntity;

BEGIN
  empty := Besm2Str.Empty()
END Besm2Grid.
