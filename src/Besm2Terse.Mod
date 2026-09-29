MODULE Besm2Terse; (* The terse format (-t/--terse) *)

(* The Ada BESM2_Fmt.Format_Terse: the terse format of the BESM 1E and
   2E books, a port of besm2-rst.scm's process-entity-terse.  Each
   section is one paragraph: a bold heading, " — ", and the items
   separated by ", ". *)

IMPORT Besm2Config, Besm2Entities, Besm2Layout, Besm2Out, Besm2Str;

TYPE
  String = Besm2Str.String;
  Buffer = Besm2Str.Buffer;

(* "N CP" for points, "N BP" for a negative number (bonus points), or
   "N MP"/"N MBP" for a mecha: the number is always written without a
   sign. *)
PROCEDURE AddLabelPoints(VAR b: Buffer; points: INTEGER; mecha: BOOLEAN);
BEGIN
  Besm2Str.AddInt(b, ABS(points)); Besm2Str.AddChar(b, " ");
  IF mecha THEN
    IF points < 0 THEN Besm2Str.Add(b, "MBP") ELSE Besm2Str.Add(b, "MP") END
  ELSE
    IF points < 0 THEN Besm2Str.Add(b, "BP") ELSE Besm2Str.Add(b, "CP") END
  END
END AddLabelPoints;

PROCEDURE LabelPoints(points: INTEGER; mecha: BOOLEAN): String;
  VAR b: Buffer;
BEGIN Besm2Str.Reset(b); AddLabelPoints(b, points, mecha); RETURN Besm2Str.Get(b)
END LabelPoints;

(* s emphasized under -b or -i (besm2-rst.scm's emphasizing), appended. *)
PROCEDURE AddEmphasized(VAR b: Buffer; s: ARRAY OF CHAR);
  VAR e: String;
BEGIN e := Besm2Layout.Emphasizing(s); Besm2Str.Add(b, e^)
END AddEmphasized;

(* "NAME LEVEL", "NAME — LEVEL" under -M/--em-dash, with "Level " before
   LEVEL under -l/--level: the emphasized part of an attribute or
   skill. *)
PROCEDURE NameAndLevel(name, level: String): String;
  VAR b: Buffer;
BEGIN
  Besm2Str.Reset(b);
  Besm2Str.Add(b, name^);
  IF Besm2Config.emDash THEN Besm2Str.Add(b, " — ") ELSE Besm2Str.AddChar(b, " ") END;
  IF Besm2Config.level THEN Besm2Str.Add(b, "Level ") END;
  Besm2Str.Add(b, level^);
  RETURN Besm2Str.Get(b)
END NameAndLevel;

(* ---- Items: besm2-rst.scm's process-stat-terse and friends ---- *)

PROCEDURE Stat(s: Besm2Entities.Stat; mecha: BOOLEAN): String;
  VAR b: Buffer;
BEGIN
  Besm2Str.Reset(b);
  Besm2Str.Add(b, s.name^); Besm2Str.AddChar(b, " "); Besm2Str.Add(b, s.value^);
  Besm2Str.Add(b, " ("); AddLabelPoints(b, s.points, mecha); Besm2Str.AddChar(b, ")");
  RETURN Besm2Str.Get(b)
END Stat;

PROCEDURE Derived(d: Besm2Entities.Derived): String;
  VAR b: Buffer; alts: String;
BEGIN
  Besm2Str.Reset(b);
  Besm2Str.Add(b, d.name^); Besm2Str.AddChar(b, " "); Besm2Str.Add(b, d.value^);
  IF d.alternatives.n > 0 THEN
    alts := Besm2Str.Join(d.alternatives, ", ");
    Besm2Str.Add(b, " ("); Besm2Str.Add(b, alts^); Besm2Str.AddChar(b, ")")
  END;
  RETURN Besm2Str.Get(b)
END Derived;

PROCEDURE Attribute(a: Besm2Entities.Attribute; mecha: BOOLEAN): String;
  VAR b: Buffer; e: String;
BEGIN
  Besm2Str.Reset(b);
  e := NameAndLevel(a.name, a.level); AddEmphasized(b, e^);
  Besm2Str.Add(b, " (");
  IF Besm2Str.Length(a.details^) > 0 THEN Besm2Str.Add(b, a.details^); Besm2Str.Add(b, ". ") END;
  AddLabelPoints(b, a.points, mecha); Besm2Str.AddChar(b, ")");
  RETURN Besm2Str.Get(b)
END Attribute;

(* Defect details are followed by two blanks, attribute details by one:
   as in besm2-rst.scm. *)
PROCEDURE Defect(d: Besm2Entities.Defect; mecha: BOOLEAN): String;
  VAR b: Buffer;
BEGIN
  Besm2Str.Reset(b);
  AddEmphasized(b, d.name^);
  Besm2Str.Add(b, " (");
  IF Besm2Str.Length(d.details^) > 0 THEN Besm2Str.Add(b, d.details^); Besm2Str.Add(b, ".  ") END;
  AddLabelPoints(b, d.points, mecha); Besm2Str.AddChar(b, ")");
  RETURN Besm2Str.Get(b)
END Defect;

PROCEDURE Skill(s: Besm2Entities.Skill): String;
  VAR b: Buffer; e: String;
BEGIN
  Besm2Str.Reset(b);
  e := NameAndLevel(s.name, s.level); AddEmphasized(b, e^);
  Besm2Str.Add(b, " (");
  IF s.specialisations.n > 0 THEN
    e := Besm2Str.Join(s.specialisations, ", "); Besm2Str.Add(b, e^); Besm2Str.Add(b, ".  ")
  END;
  Besm2Str.AddInt(b, s.points); Besm2Str.Add(b, " SP)");
  RETURN Besm2Str.Get(b)
END Skill;

(* ---- Sections ---- *)

(* The items of l, formatted by kind, separated by ", ", then a blank
   line. *)
PROCEDURE Items(l: Besm2Entities.List; mecha: BOOLEAN);
  VAR i: INTEGER; x: Besm2Entities.Named;
BEGIN
  FOR i := 0 TO l.n - 1 DO
    IF i > 0 THEN Besm2Out.String(", ") END;
    x := l.items[i];
    WITH x: Besm2Entities.Stat DO Besm2Out.Str(Stat(x, mecha))
    | x: Besm2Entities.Derived DO Besm2Out.Str(Derived(x))
    | x: Besm2Entities.Attribute DO Besm2Out.Str(Attribute(x, mecha))
    | x: Besm2Entities.Defect DO Besm2Out.Str(Defect(x, mecha))
    | x: Besm2Entities.Skill DO Besm2Out.Str(Skill(x))
    END
  END;
  Besm2Out.Ln; Besm2Out.Ln
END Items;

(* " (N CP)" or the like after a section heading, under -s/--subtotals. *)
PROCEDURE Subtotal(points: INTEGER; mecha: BOOLEAN);
BEGIN
  IF Besm2Config.showSubtotals THEN
    Besm2Out.String(" ("); Besm2Out.Str(LabelPoints(points, mecha)); Besm2Out.Char(")")
  END
END Subtotal;

(* Writes e.  entityNo is 1 for the first entity of a file, 2 for the
   second, and so on: entities after the first are underlined with
   -U/--subunderliner's character, if given. *)
PROCEDURE ProcessEntity*(e: Besm2Entities.Entity; entityNo: INTEGER);
  VAR b: Buffer; header: String; underline: CHAR;
BEGIN
  IF e.name # NIL THEN
    Besm2Str.Reset(b);
    Besm2Str.Add(b, e.name^); Besm2Str.Add(b, " (");
    AddLabelPoints(b, e.entityTotal, e.mecha); Besm2Str.AddChar(b, ")");
    header := Besm2Str.Get(b);
    IF (entityNo > 1) & (Besm2Config.subunderliner # 0X) THEN underline := Besm2Config.subunderliner
    ELSE underline := Besm2Config.underliner
    END;
    Besm2Out.Str(header); Besm2Out.Ln;
    (* The underline is as long as the header in bytes, not characters,
       as in the Ada version (Header'Length). *)
    Besm2Out.Repeat(underline, Besm2Str.Length(header^)); Besm2Out.Ln;
    Besm2Out.Ln
  ELSE
    Besm2Out.Str(LabelPoints(e.entityTotal, e.mecha)); Besm2Out.Ln;
    Besm2Out.Ln
  END;

  IF e.tagline # NIL THEN
    Besm2Out.Str(Besm2Layout.Italics(e.tagline^)); Besm2Out.Ln; Besm2Out.Ln
  END;

  IF (e.description # NIL) & ~Besm2Config.omitEntityDescription THEN
    Besm2Out.Str(e.description); Besm2Out.Ln; Besm2Out.Ln;
    IF Besm2Config.pageAfterDescription THEN
      Besm2Out.String(".. raw:: ms"); Besm2Out.Ln; Besm2Out.Ln;
      Besm2Out.String("   .bp"); Besm2Out.Ln; Besm2Out.Ln
    END
  END;

  IF e.size # NIL THEN
    Besm2Out.Str(Besm2Layout.Bold("Size:")); Besm2Out.Char(" "); Besm2Out.Str(e.size);
    Besm2Out.Ln; Besm2Out.Ln
  END;

  IF e.stats.n > 0 THEN
    Besm2Out.Str(Besm2Layout.Bold("Statistics"));
    (* This subtotal alone has a trailing blank, in besm2-rst.scm too. *)
    IF Besm2Config.showSubtotals THEN Subtotal(e.statsTotal, e.mecha); Besm2Out.Char(" ") END;
    Besm2Out.String(" — "); Besm2Out.Ln;
    Items(e.stats, e.mecha)
  END;

  IF e.derived.n > 0 THEN
    (* No line break after this heading, unlike the others. *)
    Besm2Out.Str(Besm2Layout.Bold("Derived Values")); Besm2Out.String(" — ");
    Items(e.derived, e.mecha)
  END;

  IF e.attributes.n > 0 THEN
    IF e.mecha THEN Besm2Out.Str(Besm2Layout.Bold("Mecha Sub-Attributes"))
    ELSE Besm2Out.Str(Besm2Layout.Bold("Attributes"))
    END;
    Subtotal(e.attributesTotal, e.mecha);
    Besm2Out.String(" — "); Besm2Out.Ln;
    Items(e.attributes, e.mecha)
  END;

  IF e.defects.n > 0 THEN
    IF e.mecha THEN Besm2Out.Str(Besm2Layout.Bold("Mecha Defects"))
    ELSE Besm2Out.Str(Besm2Layout.Bold("Defects"))
    END;
    Subtotal(e.defectsTotal, e.mecha);
    Besm2Out.String(" — "); Besm2Out.Ln;
    Items(e.defects, e.mecha)
  END;

  IF e.skills.n > 0 THEN
    Besm2Out.Str(Besm2Layout.Bold("Skills"));
    IF Besm2Config.showSubtotals THEN
      Besm2Out.String(" ("); Besm2Out.Str(Besm2Str.Int(e.skillsTotal)); Besm2Out.String(" SP)")
    END;
    Besm2Out.String(" — "); Besm2Out.Ln;
    Items(e.skills, e.mecha)
  END
END ProcessEntity;

END Besm2Terse.
